-- Вычисляем хэш для каждой строки (MD5 от всех полей, включая NULL)
UPDATE raw.customers
SET row_hash = MD5(
    COALESCE(customer_id, '') || '||' ||
    COALESCE(full_name, '')   || '||' ||
    COALESCE(email, '')       || '||' ||
    COALESCE(phone, '')       || '||' ||
    COALESCE(city, '')        || '||' ||
    COALESCE(created_at, '')
)
WHERE row_hash IS NULL;

-- ================================
-- 4. Функции парсинга для каждой колонки
-- ================================
-- 4.1. Полное имя
CREATE OR REPLACE FUNCTION parse_full_name(input_text text)
RETURNS TABLE(name text, format text) LANGUAGE plpgsql AS $$
DECLARE
    trimmed   text;
    collapsed text;   -- для нормализации пробелов
    match     text[];
BEGIN
    trimmed := trim(input_text);
    
    -- 1. Пустые значения
    IF trimmed IS NULL THEN
        name := NULL; format := 'invalid null'; RETURN NEXT; RETURN;
    END IF;
    IF trimmed = '' THEN
        name := NULL; format := 'invalid empty'; RETURN NEXT; RETURN;
    END IF;

    -- 2. Нормализуем множественные пробелы для точной проверки плейсхолдера
    collapsed := regexp_replace(trimmed, '\s+', ' ', 'g');

    -- 3. Проверка на строго заданный плейсхолдер 'ivan IVANOV'
    IF lower(collapsed) = 'ivan ivanov' THEN
        name := NULL;
        format := 'invalid placeholder';
        RETURN NEXT;
        RETURN;
    END IF;

    -- 4. Валидация структуры: 2 или 3 слова с заглавной буквы в каждом
    --    Поддерживает кириллицу и латиницу (через POSIX-классы [[:upper:]]/[[:lower:]])
    --    Разделители: пробел, точка, дефис
    match := regexp_match(
        trimmed,
        '^([[:lower:][:space:].\-]*?)\s*(([[:upper:]][[:lower:]]*)([\s\.\-]+[[:upper:]][[:lower:]]*){1,2})\s*$'
    );

    IF match IS NOT NULL THEN
        -- Структура корректна
        IF match[1] IS NOT NULL AND match[1] != '' THEN
            name := match[2];
            format := 'valid with prefix';   -- например, 'тов. Иван Иванов'
        ELSE
            name := match[2];
            format := 'valid';               -- например, 'Иван Иванов' или 'John Smith'
        END IF;
    ELSE
        -- Невалидная структура и НЕ является плейсхолдером
        name := NULL;
        format := 'invalid';
    END IF;

    RETURN NEXT;
END;
$$;


-- 4.2. Email
CREATE OR REPLACE FUNCTION parse_email(input_text text)
RETURNS TABLE(email text, format text) LANGUAGE plpgsql AS $$
DECLARE
    trimmed text;
BEGIN
    trimmed := trim(input_text);
    IF trimmed IS NULL THEN
        email := NULL; format := 'invalid null'; RETURN NEXT; RETURN;
    END IF;
    IF trimmed = '' THEN
        email := NULL; format := 'invalid empty'; RETURN NEXT; RETURN;
    END IF;
    IF trimmed = 'UNKNOWN' THEN
        email := NULL; format := 'invalid unknown'; RETURN NEXT; RETURN;
    END IF;

    IF trimmed ~ '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$' THEN
        email := trimmed;
        format := 'valid';
    ELSE
        email := NULL;
        format := 'invalid';
    END IF;
    RETURN NEXT;
END;
$$;


-- 4.3. Телефон
CREATE OR REPLACE FUNCTION parse_phone(input_text text)
RETURNS TABLE(phone text, phone_code text, format text) LANGUAGE plpgsql AS $$
DECLARE
    trimmed     text;
    digits      text;
    invalid_chars text;
BEGIN
    trimmed := trim(input_text);

    -- 1. Проверка NULL / пустая строка / 'UNKNOWN'
    IF trimmed IS NULL THEN
        phone := NULL; phone_code := NULL; format := 'invalid null'; RETURN NEXT; RETURN;
    END IF;
    IF trimmed = '' THEN
        phone := NULL; phone_code := NULL; format := 'invalid empty'; RETURN NEXT; RETURN;
    END IF;
    IF trimmed = 'UNKNOWN' THEN
        phone := NULL; phone_code := NULL; format := 'invalid unknown'; RETURN NEXT; RETURN;
    END IF;

    -- 2. Проверка на недопустимые символы (разрешены только цифры, -, +, (, ), )
    invalid_chars := regexp_replace(trimmed, '[0-9\-+() ]', '', 'g');
    IF length(invalid_chars) > 0 THEN
        phone := NULL; phone_code := NULL; format := 'invalid symb';
        RETURN NEXT;
        RETURN;
    END IF;

    -- 3. Извлечение всех цифр
    digits := regexp_replace(trimmed, '[^0-9]', '', 'g');

    -- 4. Если цифр меньше 10 → невалидный номер
    IF length(digits) < 10 THEN
        phone := NULL; phone_code := NULL; format := 'invalid short';
        RETURN NEXT;
        RETURN;
    END IF;

    -- 5. Валидный номер: берём последние 10 цифр, остальные – в код (если есть)
    phone := right(digits, 10);
    IF length(digits) > 10 THEN
        phone_code := left(digits, length(digits) - 10);
    ELSE
        phone_code := NULL;
    END IF;
    format := 'valid';

    RETURN NEXT;
END;
$$;


-- 4.4. Город
CREATE OR REPLACE FUNCTION parse_city(input_text text)
RETURNS TABLE(city text, format text) LANGUAGE plpgsql AS $$
DECLARE
    trimmed text;
BEGIN
    trimmed := trim(input_text);
    IF trimmed IS NULL THEN
        city := NULL; format := 'invalid null'; RETURN NEXT; RETURN;
    END IF;
    IF trimmed = '' THEN
        city := NULL; format := 'invalid empty'; RETURN NEXT; RETURN;
    END IF;
    IF trimmed = 'UNKNOWN' THEN
        city := NULL; format := 'invalid unknown'; RETURN NEXT; RETURN;
    END IF;

    -- Любое другое значение считается валидным адресом
    city := trimmed;
    format := 'valid';
    RETURN NEXT;
END;
$$;


-- 4.5. Дата создания
CREATE OR REPLACE FUNCTION parse_created_at(input_text text)
RETURNS TABLE(created_at date, format text) LANGUAGE plpgsql AS $$
DECLARE
    trimmed text;
    parsed date;
    fmt     text;
BEGIN
    trimmed := trim(input_text);
    IF trimmed IS NULL THEN
        created_at := NULL; format := 'invalid null'; RETURN NEXT; RETURN;
    END IF;
    IF trimmed = '' THEN
        created_at := NULL; format := 'invalid empty'; RETURN NEXT; RETURN;
    END IF;
    IF trimmed = 'UNKNOWN' THEN
        created_at := NULL; format := 'invalid unknown'; RETURN NEXT; RETURN;
    END IF;

    IF trimmed ~ '^\d{4}-\d{2}-\d{2}$' THEN
        BEGIN
            parsed := trimmed::date;
            fmt := 'yyyy-mm-dd';
        EXCEPTION WHEN OTHERS THEN
            parsed := NULL;
            fmt := 'invalid';
        END;
    ELSIF trimmed ~ '^\d{2}\.\d{2}\.\d{4}$' THEN
        BEGIN
            parsed := to_date(trimmed, 'DD.MM.YYYY');
            fmt := 'dd.mm.yyyy';
        EXCEPTION WHEN OTHERS THEN
            parsed := NULL;
            fmt := 'invalid';
        END;
    ELSE
        parsed := NULL;
        fmt := 'invalid';
    END IF;

    created_at := parsed;
    format := fmt;
    RETURN NEXT;
END;
$$;

-- ================================
-- 5. Преобразование и вставка в cleaned.customers (только новые строки)
-- ================================

-- Create a temp table with the parsed data
CREATE TEMP TABLE parsed_customers AS (
SELECT
    r.id,
    r.customer_id,
    r.row_hash,
    -- Raw values (для логирования)
    r.full_name   AS raw_full_name,
    r.email       AS raw_email,
    r.phone       AS raw_phone,
    r.city        AS raw_city,
    r.created_at  AS raw_created_at,
    -- Очищенные значения (могут быть NULL)
    fn.name        AS clean_full_name,
    em.email       AS clean_email,
    ph.phone       AS clean_phone,
    ci.city        AS clean_city,
    da.created_at  AS clean_created_at,
    -- Форматы для оценки качества
    fn.format      AS full_name_format,
    em.format      AS email_format,
    ph.format      AS phone_format,
    ci.format      AS city_format,
    da.format      AS created_at_format,
    COUNT(*) OVER (PARTITION BY r.row_hash) AS duplicate_count,
    -- Флаг фатальной ошибки (нет бизнес-ключа)
    (r.customer_id IS NULL OR r.customer_id = '' OR r.customer_id = 'UNKNOWN') AS is_fatal,
    -- Флаг наличия НЕфатальных ошибок (в описательных колонках)
    (fn.format NOT IN ('valid', 'valid with prefix') OR
     em.format != 'valid' OR
     ph.format != 'valid' OR
     ci.format != 'valid' OR
     da.format NOT IN ('yyyy-mm-dd', 'dd.mm.yyyy')) AS has_non_fatal_error
FROM raw.customers r
CROSS JOIN LATERAL parse_full_name(r.full_name) fn
CROSS JOIN LATERAL parse_email(r.email)         em
CROSS JOIN LATERAL parse_phone(r.phone)         ph
CROSS JOIN LATERAL parse_city(r.city)           ci
CROSS JOIN LATERAL parse_created_at(r.created_at) da
);

-- 5a. Логируем ФАТАЛЬНЫЕ ошибки (нет customer_id) → НЕ попадают в cleaned
INSERT INTO logs.rejected_records (source_table, load_datetime, raw_payload, error_details)
SELECT
    'customers',
    CURRENT_TIMESTAMP,
    row_to_json(r),   -- вся сырая строка как JSON
    jsonb_build_object(
        'level',  'fatal',
        'reason', 'missing_or_null_customer_id'
    )
FROM raw.customers r
WHERE r.customer_id IS NULL OR r.customer_id = '' OR r.customer_id = 'UNKNOWN';

-- 5b. Логируем НЕФАТАЛЬНЫЕ ошибки (customer_id есть, но часть атрибутов невалидна)
INSERT INTO logs.rejected_records (source_table, load_datetime, raw_payload, error_details)
SELECT
    'customers',
    CURRENT_TIMESTAMP,
    row_to_json(r),
    jsonb_build_object(
        'level',  'warn',
        'reason', 'invalid_descriptive_attributes',
        'details', jsonb_strip_nulls(jsonb_build_object(
            'full_name_format',  p.full_name_format,
            'email_format',      p.email_format,
            'phone_format',      p.phone_format,
            'city_format',       p.city_format,
            'created_at_format', p.created_at_format,
            'num_duplicates',    p.duplicate_count
        ))
    )
FROM raw.customers r
JOIN parsed_customers p ON p.id = r.id
WHERE p.is_fatal = false
  AND (p.has_non_fatal_error = true OR duplicate_count > 1);

-- 5c. Вставляем ОЧИЩЕННЫЕ данные в cleaned.customers (только для НЕфатальных строк)
INSERT INTO cleaned.customers (customer_id, full_name, email, phone, city, created_at, row_hash)
SELECT
    p.customer_id::INTEGER,
    p.clean_full_name,   -- может быть NULL, если парсинг не удался
    p.clean_email,
    p.clean_phone,
    p.clean_city,
    p.clean_created_at,
    p.row_hash
FROM parsed_customers p
WHERE p.is_fatal = false
ON CONFLICT (row_hash) DO NOTHING;   -- пропускаем дубликаты (уже загруженные ранее)

DROP TABLE IF EXISTS parsed_customers;