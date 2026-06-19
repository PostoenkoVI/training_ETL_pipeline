
-- ================================
-- 6. Преобразование, логирование и вставка (изменено)
-- ================================

CREATE TEMP TABLE parsed_events AS (
    SELECT
        r.id,
        r.event_id,
        r.row_hash,
        -- сырые значения для логирования
        r.customer_id       AS raw_customer_id,
        r.event_type        AS raw_event_type,
        r.event_timestamp   AS raw_event_timestamp,
        r.product_id        AS raw_product_id,
        -- очищенные значения (могут быть NULL)
        ei.event_id         AS clean_event_id,
        ci.customer_id      AS clean_customer_id,
        et.event_type       AS clean_event_type,
        ts.event_timestamp  AS clean_event_timestamp,
        pi.product_id       AS clean_product_id,
        COUNT(*) OVER (PARTITION BY r.row_hash) AS duplicate_count,
        -- форматы для оценки качества
        ei.format      AS event_id_format,
        ci.format      AS customer_id_format,
        et.format      AS event_type_format,
        ts.format      AS event_timestamp_format,
        pi.format      AS product_id_format,
        -- фатальная ошибка: отсутствует business key
        (r.event_id IS NULL OR r.event_id = '') AS is_fatal,
        -- нефатальная ошибка: хотя бы одна описательная колонка невалидна
        (ei.format != 'valid' OR
         ci.format != 'valid' OR
         et.format != 'valid' OR
         ts.format NOT IN ('yyyy-mm-dd hh24:mi:ss') OR
         pi.format != 'valid') AS has_non_fatal_error
    FROM raw.events r
    CROSS JOIN LATERAL parse_event_id(r.event_id)             ei
    CROSS JOIN LATERAL parse_customer_id_event(r.customer_id)       ci
    CROSS JOIN LATERAL parse_event_type(r.event_type)         et
    CROSS JOIN LATERAL parse_event_timestamp(r.event_timestamp) ts
    CROSS JOIN LATERAL parse_product_id_event(r.product_id)         pi
);

-- 6a. Логируем фатальные ошибки (нет event_id)
INSERT INTO logs.rejected_records (source_table, load_datetime, raw_payload, error_details)
SELECT
    'events',
    CURRENT_TIMESTAMP,
    row_to_json(r),
    jsonb_build_object(
        'level',  'fatal',
        'reason', 'missing_or_null_event_id'
    )
FROM raw.events r
WHERE r.event_id IS NULL OR r.event_id = '';

-- 6b. Логируем нефатальные ошибки (event_id есть, но часть атрибутов невалидна)
INSERT INTO logs.rejected_records (source_table, load_datetime, raw_payload, error_details)
SELECT
    'events',
    CURRENT_TIMESTAMP,
    row_to_json(r),
    jsonb_build_object(
        'level',  'warn',
        'reason', 'invalid_descriptive_attributes',
        'details', jsonb_strip_nulls(jsonb_build_object(
            'customer_id_format',       p.customer_id_format,
            'event_type_format',        p.event_type_format,
            'event_timestamp_format',   p.event_timestamp_format,
            'product_id_format',        p.product_id_format,
            'num_duplicates',    p.duplicate_count
        ))
    )
FROM raw.events r
JOIN parsed_events p ON p.id = r.id
WHERE p.is_fatal = false
  AND (p.has_non_fatal_error = true OR duplicate_count > 1);

-- 6c. Вставляем только нефатальные строки в cleaned.events (с очищенными значениями)
INSERT INTO cleaned.events (event_id, customer_id, event_type, event_timestamp, product_id, row_hash)
SELECT
    p.clean_event_id,
    p.clean_customer_id,
    p.clean_event_type,
    p.clean_event_timestamp,
    p.clean_product_id,
    p.row_hash
FROM parsed_events p
WHERE p.is_fatal = false
ON CONFLICT (row_hash) DO NOTHING;

DROP TABLE IF EXISTS parsed_events;