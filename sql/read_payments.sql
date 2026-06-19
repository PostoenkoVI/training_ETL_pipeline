-- Вычисляем хэш для каждой строки (MD5 от всех полей, включая NULL)
UPDATE raw.payments
SET row_hash = MD5(
    COALESCE(payment_id, '')        || '||' ||
    COALESCE(order_id, '')          || '||' ||
    COALESCE(payment_method, '')    || '||' ||
    COALESCE(amount, '')            || '||' ||
    COALESCE(currency, '')          || '||' ||
    COALESCE(payment_timestamp, '')
)
WHERE row_hash IS NULL;

-- ================================
-- 4. Функции парсинга для каждой колонки
-- ================================

-- 4.1. order_id (валидный только если число > 0)
CREATE OR REPLACE FUNCTION parse_order_id(input_text text)
RETURNS TABLE(order_id integer, format text) LANGUAGE plpgsql AS $$
DECLARE
    trimmed text;
    num     integer;
BEGIN
    trimmed := trim(input_text);
    IF trimmed IS NULL THEN
        order_id := NULL; format := 'null'; RETURN NEXT; RETURN;
    END IF;
    IF trimmed = '' THEN
        order_id := NULL; format := 'empty'; RETURN NEXT; RETURN;
    END IF;
    BEGIN
        num := trimmed::integer;
        IF num > 0 THEN
            order_id := num;
            format := 'valid';
        ELSE
            order_id := NULL;
            format := 'invalid';  -- число <= 0
        END IF;
    EXCEPTION WHEN OTHERS THEN
        order_id := NULL;
        format := 'invalid';      -- не число
    END;
    RETURN NEXT;
END;
$$;

-- 4.2. payment_method (должен быть bank_transfer, card или paypal)
CREATE OR REPLACE FUNCTION parse_payment_method(input_text text)
RETURNS TABLE(payment_method text, format text) LANGUAGE plpgsql AS $$
DECLARE
    trimmed text;
BEGIN
    trimmed := trim(input_text);
    IF trimmed IS NULL THEN
        payment_method := NULL; format := 'null'; RETURN NEXT; RETURN;
    END IF;
    IF trimmed = '' THEN
        payment_method := NULL; format := 'empty'; RETURN NEXT; RETURN;
    END IF;
    IF trimmed IN ('bank_transfer', 'card', 'paypal') THEN
        payment_method := trimmed;
        format := 'valid';
    ELSE
        payment_method := NULL;
        format := 'invalid';
    END IF;
    RETURN NEXT;
END;
$$;

-- 4.3. amount (обработка 'error_amount' и нечисловых значений)
CREATE OR REPLACE FUNCTION parse_amount(input_text text)
RETURNS TABLE(amount numeric, format text) LANGUAGE plpgsql AS $$
DECLARE
    trimmed text;
    num     numeric;
BEGIN
    trimmed := trim(input_text);
    IF trimmed IS NULL THEN
        amount := NULL; format := 'null'; RETURN NEXT; RETURN;
    END IF;
    IF trimmed = '' THEN
        amount := NULL; format := 'empty'; RETURN NEXT; RETURN;
    END IF;
    IF trimmed = 'error_amount' THEN
        amount := NULL; format := 'error_amount'; RETURN NEXT; RETURN;
    END IF;
    BEGIN
        num := trimmed::numeric;
        IF num > 0 THEN
            amount := num;
            format := 'valid';
        ELSE
            amount := NULL;
            format := 'invalid';  -- <= 0
        END IF;
    EXCEPTION WHEN OTHERS THEN
        amount := NULL;
        format := 'invalid';      -- не число
    END;
    RETURN NEXT;
END;
$$;

-- 4.4. currency (должна быть USD, EUR или RUB)
CREATE OR REPLACE FUNCTION parse_currency(input_text text)
RETURNS TABLE(currency text, format text) LANGUAGE plpgsql AS $$
DECLARE
    trimmed text;
BEGIN
    trimmed := trim(input_text);
    IF trimmed IS NULL THEN
        currency := NULL; format := 'null'; RETURN NEXT; RETURN;
    END IF;
    IF trimmed = '' THEN
        currency := NULL; format := 'empty'; RETURN NEXT; RETURN;
    END IF;
    IF trimmed IN ('USD', 'EUR', 'RUB') THEN
        currency := trimmed;
        format := 'valid';
    ELSE
        currency := NULL;
        format := 'invalid';
    END IF;
    RETURN NEXT;
END;
$$;

-- 4.5. payment_timestamp (поддержка стандартного формата и dd.mm.yyyy)
CREATE OR REPLACE FUNCTION parse_payment_timestamp(input_text text)
RETURNS TABLE(payment_timestamp timestamp, format text) LANGUAGE plpgsql AS $$
DECLARE
    trimmed text;
    parsed  timestamp;
    fmt     text;
BEGIN
    trimmed := trim(input_text);
    IF trimmed IS NULL THEN
        payment_timestamp := NULL; format := 'null'; RETURN NEXT; RETURN;
    END IF;
    IF trimmed = '' THEN
        payment_timestamp := NULL; format := 'empty'; RETURN NEXT; RETURN;
    END IF;

    -- Попытка парсинга как YYYY-MM-DD HH24:MI:SS
    IF trimmed ~ '^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$' THEN
        BEGIN
            parsed := trimmed::timestamp;
            fmt := 'yyyy-mm-dd hh24:mi:ss';
        EXCEPTION WHEN OTHERS THEN
            parsed := NULL;
            fmt := 'invalid';
        END;
    -- Попытка парсинга как DD.MM.YYYY (встречается как '13/45/2025', но это будет invalid)
    ELSIF trimmed ~ '^\d{2}\.\d{2}\.\d{4}$' THEN
        BEGIN
            parsed := to_timestamp(trimmed, 'DD.MM.YYYY')::timestamp;
            fmt := 'dd.mm.yyyy';
        EXCEPTION WHEN OTHERS THEN
            parsed := NULL;
            fmt := 'invalid';
        END;
    ELSE
        parsed := NULL;
        fmt := 'invalid';
    END IF;

    payment_timestamp := parsed;
    format := fmt;
    RETURN NEXT;
END;
$$;

-- ================================
-- 5. Преобразование, логирование и вставка (изменено)
-- ================================
CREATE TEMP TABLE parsed_payments AS (
SELECT
    r.id,
    r.payment_id,
    r.row_hash,
    -- сырые значения для логирования
    r.order_id          AS raw_order_id,
    r.payment_method    AS raw_payment_method,
    r.amount            AS raw_amount,
    r.currency          AS raw_currency,
    r.payment_timestamp AS raw_payment_timestamp,
    -- очищенные значения (могут быть NULL)
    oi.order_id         AS clean_order_id,
    pm.payment_method   AS clean_payment_method,
    am.amount           AS clean_amount,
    cu.currency         AS clean_currency,
    ts.payment_timestamp AS clean_payment_timestamp,
    -- форматы для оценки качества
    oi.format      AS order_id_format,
    pm.format      AS payment_method_format,
    am.format      AS amount_format,
    cu.format      AS currency_format,
    ts.format      AS payment_timestamp_format,
    COUNT(*) OVER (PARTITION BY r.row_hash) AS duplicate_count,
    -- фатальная ошибка: отсутствует business key
    (r.payment_id IS NULL OR r.payment_id = '') AS is_fatal,
    -- нефатальная ошибка: хотя бы одна описательная колонка невалидна
    (oi.format != 'valid' OR
     pm.format != 'valid' OR
     am.format != 'valid' OR
     cu.format != 'valid' OR
     ts.format NOT IN ('yyyy-mm-dd hh24:mi:ss', 'dd.mm.yyyy')) AS has_non_fatal_error
FROM raw.payments r
CROSS JOIN LATERAL parse_order_id(r.order_id)           oi
CROSS JOIN LATERAL parse_payment_method(r.payment_method) pm
CROSS JOIN LATERAL parse_amount(r.amount)               am
CROSS JOIN LATERAL parse_currency(r.currency)           cu
CROSS JOIN LATERAL parse_payment_timestamp(r.payment_timestamp) ts
);

-- 5a. Логируем фатальные ошибки (нет payment_id)
INSERT INTO logs.rejected_records (source_table, load_datetime, raw_payload, error_details)
SELECT
    'payments',
    CURRENT_TIMESTAMP,
    row_to_json(r),
    jsonb_build_object(
        'level',  'fatal',
        'reason', 'missing_or_null_payment_id'
    )
FROM raw.payments r
WHERE r.payment_id IS NULL OR r.payment_id = '';

-- 5b. Логируем нефатальные ошибки (payment_id есть, но часть атрибутов невалидна)
INSERT INTO logs.rejected_records (source_table, load_datetime, raw_payload, error_details)
SELECT
    'payments',
    CURRENT_TIMESTAMP,
    row_to_json(r),
    jsonb_build_object(
        'level',  'warn',
        'reason', 'invalid_descriptive_attributes',
        'details', jsonb_strip_nulls(jsonb_build_object(
            'order_id_format',          p.order_id_format,
            'payment_method_format',    p.payment_method_format,
            'amount_format',            p.amount_format,
            'currency_format',          p.currency_format,
            'payment_timestamp_format', p.payment_timestamp_format,
            'num_duplicates',    p.duplicate_count
        ))
    )
FROM raw.payments r
JOIN parsed_payments p ON p.id = r.id
WHERE p.is_fatal = false
  AND (p.has_non_fatal_error = true OR duplicate_count > 1);

-- 5c. Вставляем только нефатальные строки в cleaned.payments (с очищенными значениями)
INSERT INTO cleaned.payments (payment_id, order_id, payment_method, amount, currency, payment_timestamp, row_hash)
SELECT
    p.payment_id::INTEGER,
    p.clean_order_id,
    p.clean_payment_method,
    p.clean_amount,
    p.clean_currency,
    p.clean_payment_timestamp,
    p.row_hash
FROM parsed_payments p
WHERE p.is_fatal = false
ON CONFLICT (row_hash) DO NOTHING;

DROP TABLE IF EXISTS parsed_payments;