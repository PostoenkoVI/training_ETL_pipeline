-- ================================
-- 6. Преобразование, логирование и вставка (изменено)
-- ================================
CREATE TEMP TABLE parsed_orders AS (
    SELECT
        r.id,
        r.order_id,
        r.row_hash,
        -- сырые значения для логирования
        r.customer_id       AS raw_customer_id,
        r.product_id        AS raw_product_id,
        r.quantity          AS raw_quantity,
        r.unit_price        AS raw_unit_price,
        r.currency          AS raw_currency,
        r.order_timestamp   AS raw_order_timestamp,
        r.status            AS raw_status,
        -- очищенные значения (могут быть NULL)
        oi.order_id         AS clean_order_id,
        ci.customer_id      AS clean_customer_id,
        pi.product_id       AS clean_product_id,
        qty.quantity        AS clean_quantity,
        up.unit_price       AS clean_unit_price,
        cur.currency        AS clean_currency,
        ts.order_timestamp  AS clean_order_timestamp,
        st.status           AS clean_status,
        -- форматы для оценки качества
        oi.format      AS order_id_format,
        ci.format      AS customer_id_format,
        pi.format      AS product_id_format,
        qty.format     AS quantity_format,
        up.format      AS unit_price_format,
        cur.format     AS currency_format,
        ts.format      AS order_timestamp_format,
        st.format      AS status_format,
        COUNT(*) OVER (PARTITION BY r.row_hash) AS duplicate_count,
        -- фатальная ошибка: отсутствует business key
        (r.order_id IS NULL OR r.order_id = '') AS is_fatal,
        -- нефатальная ошибка: хотя бы одна описательная колонка невалидна
        (oi.format != 'valid' OR
         ci.format != 'valid' OR
         pi.format != 'valid' OR
         qty.format != 'valid' OR
         up.format != 'valid' OR
         cur.format != 'valid' OR
         ts.format NOT IN ('yyyy-mm-dd hh24:mi:ss', 'yyyy-mm-dd') OR  -- допустимые форматы
         st.format != 'valid') AS has_non_fatal_error
    FROM raw.orders r
    CROSS JOIN LATERAL parse_order_id(r.order_id)             oi
    CROSS JOIN LATERAL parse_customer_id(r.customer_id)       ci
    CROSS JOIN LATERAL parse_product_id(r.product_id)         pi
    CROSS JOIN LATERAL parse_quantity(r.quantity)             qty
    CROSS JOIN LATERAL parse_unit_price(r.unit_price)         up
    CROSS JOIN LATERAL parse_currency(r.currency)             cur
    CROSS JOIN LATERAL parse_order_timestamp(r.order_timestamp) ts
    CROSS JOIN LATERAL parse_status(r.status)                 st
);

-- 6a. Логируем фатальные ошибки (нет order_id)
INSERT INTO logs.rejected_records (source_table, load_datetime, raw_payload, error_details)
SELECT
    'orders',
    CURRENT_TIMESTAMP,
    row_to_json(r),
    jsonb_build_object(
        'level',  'fatal',
        'reason', 'missing_or_null_order_id'
    )
FROM raw.orders r
WHERE r.order_id IS NULL OR r.order_id = '';

-- 6b. Логируем нефатальные ошибки (order_id есть, но часть атрибутов невалидна)
INSERT INTO logs.rejected_records (source_table, load_datetime, raw_payload, error_details)
SELECT
    'orders',
    CURRENT_TIMESTAMP,
    row_to_json(r),
    jsonb_build_object(
        'level',  'warn',
        'reason', 'invalid_descriptive_attributes',
        'details', jsonb_strip_nulls(jsonb_build_object(
            'customer_id_format',       p.customer_id_format,
            'product_id_format',        p.product_id_format,
            'quantity_format',          p.quantity_format,
            'unit_price_format',        p.unit_price_format,
            'currency_format',          p.currency_format,
            'order_timestamp_format',   p.order_timestamp_format,
            'status_format',            p.status_format,
            'num_duplicates',    p.duplicate_count
        ))
    )
FROM raw.orders r
JOIN parsed_orders p ON p.id = r.id
WHERE p.is_fatal = false
  AND (p.has_non_fatal_error = true OR duplicate_count > 1);

-- 6c. Вставляем только нефатальные строки в cleaned.orders (с очищенными значениями)
INSERT INTO cleaned.orders (order_id, customer_id, product_id, quantity, unit_price, currency, order_timestamp, status, row_hash)
SELECT
    p.clean_order_id,
    p.clean_customer_id,
    p.clean_product_id,
    p.clean_quantity,
    p.clean_unit_price,
    p.clean_currency,
    p.clean_order_timestamp,
    p.clean_status,
    p.row_hash
FROM parsed_orders p
WHERE p.is_fatal = false
ON CONFLICT (row_hash) DO NOTHING;

DROP TABLE IF EXISTS parsed_orders;