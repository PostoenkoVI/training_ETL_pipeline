
-- ================================
-- 5. Функции парсинга для каждой колонки
-- ================================

-- 5.1. order_id (валидный только если число > 0)
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

-- 5.2. customer_id (без FK-проверки, только числовой формат)
CREATE OR REPLACE FUNCTION parse_customer_id(input_text text)
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

-- 5.3. product_id (без FK-проверки, только числовой формат)
CREATE OR REPLACE FUNCTION parse_product_id(input_text text)
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

-- 5.4. quantity (должен быть целым положительным числом)
CREATE OR REPLACE FUNCTION parse_quantity(input_text text)
RETURNS TABLE(quantity integer, format text) LANGUAGE plpgsql AS $$
DECLARE
    trimmed text;
    num     integer;
BEGIN
    trimmed := trim(input_text);
    IF trimmed IS NULL THEN
        quantity := NULL; format := 'null'; RETURN NEXT; RETURN;
    END IF;
    IF trimmed = '' THEN
        quantity := NULL; format := 'empty'; RETURN NEXT; RETURN;
    END IF;
    BEGIN
        num := trimmed::integer;
        IF num > 0 THEN
            quantity := num;
            format := 'valid';
        ELSE
            quantity := NULL;
            format := 'invalid';
        END IF;
    EXCEPTION WHEN OTHERS THEN
        quantity := NULL;
        format := 'invalid';
    END;
    RETURN NEXT;
END;
$$;

-- 5.5. unit_price (должен быть числом > 0)
CREATE OR REPLACE FUNCTION parse_unit_price(input_text text)
RETURNS TABLE(unit_price numeric, format text) LANGUAGE plpgsql AS $$
DECLARE
    trimmed text;
    num     numeric;
BEGIN
    trimmed := trim(input_text);
    IF trimmed IS NULL THEN
        unit_price := NULL; format := 'null'; RETURN NEXT; RETURN;
    END IF;
    IF trimmed = '' THEN
        unit_price := NULL; format := 'empty'; RETURN NEXT; RETURN;
    END IF;
    BEGIN
        num := trimmed::numeric;
        IF num > 0 THEN
            unit_price := num;
            format := 'valid';
        ELSE
            unit_price := NULL;
            format := 'invalid';
        END IF;
    EXCEPTION WHEN OTHERS THEN
        unit_price := NULL;
        format := 'invalid';
    END;
    RETURN NEXT;
END;
$$;

-- 5.6. currency (должна быть USD, EUR или RUB)
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

-- 5.7. order_timestamp (поддержка формата YYYY-MM-DD HH24:MI:SS и обработка '2025-99-99')
CREATE OR REPLACE FUNCTION parse_order_timestamp(input_text text)
RETURNS TABLE(order_timestamp timestamp, format text) LANGUAGE plpgsql AS $$
DECLARE
    trimmed text;
    parsed  timestamp;
    fmt     text;
BEGIN
    trimmed := trim(input_text);
    IF trimmed IS NULL THEN
        order_timestamp := NULL; format := 'null'; RETURN NEXT; RETURN;
    END IF;
    IF trimmed = '' THEN
        order_timestamp := NULL; format := 'empty'; RETURN NEXT; RETURN;
    END IF;
    -- Проверка на специфический плейсхолдер '2025-99-99'
    IF trimmed = '2025-99-99' THEN
        order_timestamp := NULL; format := 'placeholder_date'; RETURN NEXT; RETURN;
    END IF;
    -- Попытка парсинга стандартного формата
    IF trimmed ~ '^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$' THEN
        BEGIN
            parsed := trimmed::timestamp;
            fmt := 'yyyy-mm-dd hh24:mi:ss';
        EXCEPTION WHEN OTHERS THEN
            parsed := NULL;
            fmt := 'invalid';
        END;
    -- Попытка парсинга как даты без времени (YYYY-MM-DD) – встречается в данных?
    -- По данным анализа, все имеют время, но оставим на всякий случай
    ELSIF trimmed ~ '^\d{4}-\d{2}-\d{2}$' THEN
        BEGIN
            parsed := trimmed::date;
            fmt := 'yyyy-mm-dd';
        EXCEPTION WHEN OTHERS THEN
            parsed := NULL;
            fmt := 'invalid';
        END;
    ELSE
        parsed := NULL;
        fmt := 'invalid';
    END IF;
    order_timestamp := parsed;
    format := fmt;
    RETURN NEXT;
END;
$$;

-- 5.8. status (должен быть processing, completed или cancelled)
CREATE OR REPLACE FUNCTION parse_status(input_text text)
RETURNS TABLE(status text, format text) LANGUAGE plpgsql AS $$
DECLARE
    trimmed text;
BEGIN
    trimmed := trim(input_text);
    IF trimmed IS NULL THEN
        status := NULL; format := 'null'; RETURN NEXT; RETURN;
    END IF;
    IF trimmed = '' THEN
        status := NULL; format := 'empty'; RETURN NEXT; RETURN;
    END IF;
    IF trimmed IN ('processing', 'completed', 'cancelled') THEN
        status := trimmed;
        format := 'valid';
    ELSE
        status := NULL;
        format := 'invalid';
    END IF;
    RETURN NEXT;
END;
$$;