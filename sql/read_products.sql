-- Вычисляем хэш для каждой строки (MD5 от всех полей, включая NULL)
UPDATE raw.products
SET row_hash = MD5(
    COALESCE(product_id, '')   || '||' ||
    COALESCE(product_name, '') || '||' ||
    COALESCE(category, '')     || '||' ||
    COALESCE(price, '')        || '||' ||
    COALESCE(currency, '')     || '||' ||
    COALESCE(is_active, '')
)
WHERE row_hash IS NULL;

-- ================================
-- 4. Функции парсинга для каждой колонки
-- ================================

-- 4.1. Название продукта
CREATE OR REPLACE FUNCTION parse_product_name(input_text text)
RETURNS TABLE(name text, format text) LANGUAGE plpgsql AS $$
DECLARE
    trimmed text;
BEGIN
    trimmed := trim(input_text);
    IF trimmed IS NULL THEN
        name := NULL; format := 'null'; RETURN NEXT; RETURN;
    END IF;
    IF trimmed = '' THEN
        name := NULL; format := 'empty'; RETURN NEXT; RETURN;
    END IF;
    -- Любое непустое значение считаем валидным (проверка на специфичные плейсхолдеры не требуется)
    name := trimmed;
    format := 'valid';
    RETURN NEXT;
END;
$$;

-- 4.2. Категория (должна быть одной из пяти)
CREATE OR REPLACE FUNCTION parse_category(input_text text)
RETURNS TABLE(category text, format text) LANGUAGE plpgsql AS $$
DECLARE
    trimmed text;
BEGIN
    trimmed := trim(input_text);
    IF trimmed IS NULL THEN
        category := NULL; format := 'null'; RETURN NEXT; RETURN;
    END IF;
    IF trimmed = '' THEN
        category := NULL; format := 'empty'; RETURN NEXT; RETURN;
    END IF;
    -- Проверка на допустимые значения: Home, Books, Electronics, Clothing, Sports
    IF trimmed IN ('Home', 'Books', 'Electronics', 'Clothing', 'Sports') THEN
        category := trimmed;
        format := 'valid';
    ELSE
        category := NULL;
        format := 'invalid';
    END IF;
    RETURN NEXT;
END;
$$;

-- 4.3. Цена (обработка 'N/A' и нечисловых значений)
CREATE OR REPLACE FUNCTION parse_price(input_text text)
RETURNS TABLE(price numeric, format text) LANGUAGE plpgsql AS $$
DECLARE
    trimmed text;
    num     numeric;
BEGIN
    trimmed := trim(input_text);
    IF trimmed IS NULL THEN
        price := NULL; format := 'null'; RETURN NEXT; RETURN;
    END IF;
    IF trimmed = '' THEN
        price := NULL; format := 'empty'; RETURN NEXT; RETURN;
    END IF;
    IF trimmed = 'N/A' THEN
        price := NULL; format := 'na'; RETURN NEXT; RETURN;
    END IF;
    -- Пытаемся преобразовать в число
    BEGIN
        num := trimmed::numeric;
        price := num;
        format := 'valid';
    EXCEPTION WHEN OTHERS THEN
        price := NULL;
        format := 'invalid';
    END;
    RETURN NEXT;
END;
$$;

-- 4.4. Валюта (должна быть USD, EUR или RUB)
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

-- 4.5. Активность (приведение к boolean с проверкой)
CREATE OR REPLACE FUNCTION parse_is_active(input_text text)
RETURNS TABLE(is_active boolean, format text) LANGUAGE plpgsql AS $$
DECLARE
    trimmed text;
BEGIN
    trimmed := trim(input_text);
    IF trimmed IS NULL THEN
        is_active := NULL; format := 'null'; RETURN NEXT; RETURN;
    END IF;
    IF trimmed = '' THEN
        is_active := NULL; format := 'empty'; RETURN NEXT; RETURN;
    END IF;
    -- Поддерживаем True/False, 1/0, yes/no (регистронезависимо)
    IF lower(trimmed) IN ('true', '1', 'yes') THEN
        is_active := TRUE; format := 'valid';
    ELSIF lower(trimmed) IN ('false', '0', 'no') THEN
        is_active := FALSE; format := 'valid';
    ELSE
        is_active := NULL; format := 'invalid';
    END IF;
    RETURN NEXT;
END;
$$;

-- ================================
-- 5. Преобразование, логирование и вставка (изменено)
-- ================================
CREATE TEMP TABLE parsed_products AS (
    SELECT
        r.id,
        r.product_id,
        r.row_hash,
        -- сырые значения для логирования
        r.product_name AS raw_product_name,
        r.category     AS raw_category,
        r.price        AS raw_price,
        r.currency     AS raw_currency,
        r.is_active    AS raw_is_active,
        -- очищенные значения (могут быть NULL)
        pn.name        AS clean_product_name,
        cat.category   AS clean_category,
        pr.price       AS clean_price,
        cur.currency   AS clean_currency,
        act.is_active  AS clean_is_active,
        -- форматы для оценки качества
        pn.format      AS product_name_format,
        cat.format     AS category_format,
        pr.format      AS price_format,
        cur.format     AS currency_format,
        act.format     AS is_active_format,
        COUNT(*) OVER (PARTITION BY r.row_hash) AS duplicate_count,
        -- фатальная ошибка: отсутствует business key
        (r.product_id IS NULL OR r.product_id = '') AS is_fatal,
        -- нефатальная ошибка: хотя бы одна описательная колонка невалидна
        (pn.format != 'valid' OR
         cat.format != 'valid' OR
         pr.format != 'valid' OR
         cur.format != 'valid' OR
         act.format != 'valid') AS has_non_fatal_error
    FROM raw.products r
    CROSS JOIN LATERAL parse_product_name(r.product_name) pn
    CROSS JOIN LATERAL parse_category(r.category)         cat
    CROSS JOIN LATERAL parse_price(r.price)               pr
    CROSS JOIN LATERAL parse_currency(r.currency)         cur
    CROSS JOIN LATERAL parse_is_active(r.is_active)       act
);

-- 5a. Логируем фатальные ошибки (нет product_id)
INSERT INTO logs.rejected_records (source_table, load_datetime, raw_payload, error_details)
SELECT
    'products',
    CURRENT_TIMESTAMP,
    row_to_json(r),
    jsonb_build_object(
        'level',  'fatal',
        'reason', 'missing_or_null_product_id'
    )
FROM raw.products r
WHERE r.product_id IS NULL OR r.product_id = '';

-- 5b. Логируем нефатальные ошибки (product_id есть, но часть атрибутов невалидна)
INSERT INTO logs.rejected_records (source_table, load_datetime, raw_payload, error_details)
SELECT
    'products',
    CURRENT_TIMESTAMP,
    row_to_json(r),
    jsonb_build_object(
        'level',  'warn',
        'reason', 'invalid_descriptive_attributes',
        'details', jsonb_strip_nulls(jsonb_build_object(
            'product_name_format', p.product_name_format,
            'category_format',     p.category_format,
            'price_format',        p.price_format,
            'currency_format',     p.currency_format,
            'is_active_format',    p.is_active_format,
            'num_duplicates',      p.duplicate_count
        ))
    )
FROM raw.products r
JOIN parsed_products p ON p.id = r.id
WHERE p.is_fatal = false
  AND (p.has_non_fatal_error = true OR duplicate_count > 1);

-- 5c. Вставляем только нефатальные строки в cleaned.products (с очищенными значениями)
INSERT INTO cleaned.products (product_id, product_name, category, price, currency, is_active, row_hash)
SELECT
    p.product_id::INTEGER,
    p.clean_product_name,
    p.clean_category,
    p.clean_price,
    p.clean_currency,
    p.clean_is_active,
    p.row_hash
FROM parsed_products p
WHERE p.is_fatal = false
ON CONFLICT (row_hash) DO NOTHING;

DROP TABLE IF EXISTS parsed_products;