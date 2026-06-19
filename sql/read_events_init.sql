-- ================================
-- 5. Функции парсинга для каждой колонки
-- ================================
-- DROP FUNCTION IF EXISTS parse_event_id(text);
-- DROP FUNCTION IF EXISTS parse_customer_id_event(text);
-- DROP FUNCTION IF EXISTS parse_event_type(text);
-- DROP FUNCTION IF EXISTS parse_event_timestamp(text);
-- DROP FUNCTION IF EXISTS parse_product_id_event(text);
-- 5.1. event_id (валидный только если число > 0, обрабатывает 'BAD_ID')
CREATE OR REPLACE FUNCTION parse_event_id(input_text text)
RETURNS TABLE(event_id integer, format text) LANGUAGE plpgsql AS $$
DECLARE
    trimmed text;
    num     integer;
BEGIN
    trimmed := trim(input_text);
    IF trimmed IS NULL THEN
        event_id := NULL; format := 'null'; RETURN NEXT; RETURN;
    END IF;
    IF trimmed = '' THEN
        event_id := NULL; format := 'empty'; RETURN NEXT; RETURN;
    END IF;
    IF trimmed = 'BAD_ID' THEN
        event_id := NULL; format := 'bad_id'; RETURN NEXT; RETURN;
    END IF;
    BEGIN
        num := trimmed::integer;
        IF num > 0 THEN
            event_id := num;
            format := 'valid';
        ELSE
            event_id := NULL;
            format := 'invalid';  -- число <= 0
        END IF;
    EXCEPTION WHEN OTHERS THEN
        event_id := NULL;
        format := 'invalid';      -- не число
    END;
    RETURN NEXT;
END;
$$;

-- 5.2. customer_id (только числовая валидация, без FK)
CREATE OR REPLACE FUNCTION parse_customer_id_event(input_text text)
RETURNS TABLE(customer_id integer, format text) LANGUAGE plpgsql AS $$
DECLARE
    trimmed text;
    num     integer;
BEGIN
    trimmed := trim(input_text);
    IF trimmed IS NULL THEN
        customer_id := NULL; format := 'null'; RETURN NEXT; RETURN;
    END IF;
    IF trimmed = '' THEN
        customer_id := NULL; format := 'empty'; RETURN NEXT; RETURN;
    END IF;
    BEGIN
        num := trimmed::integer;
        IF num > 0 THEN
            customer_id := num;
            format := 'valid';
        ELSE
            customer_id := NULL;
            format := 'invalid';
        END IF;
    EXCEPTION WHEN OTHERS THEN
        customer_id := NULL;
        format := 'invalid';
    END;
    RETURN NEXT;
END;
$$;

-- 5.3. event_type (должен быть одним из пяти допустимых значений)
CREATE OR REPLACE FUNCTION parse_event_type(input_text text)
RETURNS TABLE(event_type text, format text) LANGUAGE plpgsql AS $$
DECLARE
    trimmed text;
BEGIN
    trimmed := trim(input_text);
    IF trimmed IS NULL THEN
        event_type := NULL; format := 'null'; RETURN NEXT; RETURN;
    END IF;
    IF trimmed = '' THEN
        event_type := NULL; format := 'empty'; RETURN NEXT; RETURN;
    END IF;
    IF trimmed IN ('view', 'login', 'purchase', 'click', 'logout') THEN
        event_type := trimmed;
        format := 'valid';
    ELSE
        event_type := NULL;
        format := 'invalid';
    END IF;
    RETURN NEXT;
END;
$$;

-- 5.4. event_timestamp (поддержка формата YYYY-MM-DD HH24:MI:SS и 'broken-date')
CREATE OR REPLACE FUNCTION parse_event_timestamp(input_text text)
RETURNS TABLE(event_timestamp timestamp, format text) LANGUAGE plpgsql AS $$
DECLARE
    trimmed text;
    parsed  timestamp;
    fmt     text;
BEGIN
    trimmed := trim(input_text);
    IF trimmed IS NULL THEN
        event_timestamp := NULL; format := 'null'; RETURN NEXT; RETURN;
    END IF;
    IF trimmed = '' THEN
        event_timestamp := NULL; format := 'empty'; RETURN NEXT; RETURN;
    END IF;
    IF trimmed = 'broken-date' THEN
        event_timestamp := NULL; format := 'broken-date'; RETURN NEXT; RETURN;
    END IF;
    IF trimmed ~ '^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$' THEN
        BEGIN
            parsed := trimmed::timestamp;
            fmt := 'yyyy-mm-dd hh24:mi:ss';
        EXCEPTION WHEN OTHERS THEN
            parsed := NULL;
            fmt := 'invalid';
        END;
    ELSE
        parsed := NULL;
        fmt := 'invalid';
    END IF;
    event_timestamp := parsed;
    format := fmt;
    RETURN NEXT;
END;
$$;

-- 5.5. product_id (только числовая валидация, без FK)
CREATE OR REPLACE FUNCTION parse_product_id_event(input_text text)
RETURNS TABLE(product_id integer, format text) LANGUAGE plpgsql AS $$
DECLARE
    trimmed text;
    num     integer;
BEGIN
    trimmed := trim(input_text);
    IF trimmed IS NULL THEN
        product_id := NULL; format := 'null'; RETURN NEXT; RETURN;
    END IF;
    IF trimmed = '' THEN
        product_id := NULL; format := 'empty'; RETURN NEXT; RETURN;
    END IF;
    BEGIN
        num := trimmed::integer;
        IF num > 0 THEN
            product_id := num;
            format := 'valid';
        ELSE
            product_id := NULL;
            format := 'invalid';
        END IF;
    EXCEPTION WHEN OTHERS THEN
        product_id := NULL;
        format := 'invalid';
    END;
    RETURN NEXT;
END;
$$;