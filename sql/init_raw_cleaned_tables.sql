-- ================================
-- 1. Создание схем и таблиц
-- ================================
CREATE SCHEMA IF NOT EXISTS raw;
CREATE SCHEMA IF NOT EXISTS cleaned;
CREATE SCHEMA IF NOT EXISTS logs;


-- logs.rejected_records: single, generic error vault (JSONB)
CREATE TABLE IF NOT EXISTS logs.rejected_records (
    id            BIGSERIAL PRIMARY KEY,
    source_table  TEXT      NOT NULL,
    load_datetime TIMESTAMP NOT NULL,
    raw_payload   JSONB     NOT NULL,   -- full raw row as JSON
    error_details JSONB     NOT NULL    -- structured error info
);

CREATE INDEX IF NOT EXISTS idx_rejected_source ON logs.rejected_records(source_table);
CREATE INDEX IF NOT EXISTS idx_rejected_load  ON logs.rejected_records(load_datetime);

-- raw.customers: добавлен id (SERIAL), row_hash для дедупликации
CREATE TABLE IF NOT EXISTS raw.customers (
    id          SERIAL PRIMARY KEY,
    customer_id text,
    full_name   text,
    email       text,
    phone       text,
    city        text,
    created_at  text,
    row_hash    text -- UNIQUE  -- хэш исходных данных для быстрого поиска дубликатов
);

-- cleaned.customers: ONLY cleaned, typed columns + row_hash for dedup.
-- All _format / num_duplicated columns are REMOVED (they are ephemeral).
CREATE TABLE IF NOT EXISTS cleaned.customers (
    id          SERIAL PRIMARY KEY,
    customer_id INTEGER,
    full_name   TEXT,
    email       TEXT,
    phone       TEXT,
    city        TEXT,
    created_at  DATE,
    row_hash    TEXT UNIQUE   -- for deduplication across loads
);

-- Вспомогательная таблица для загрузки JSON-файла целиком
CREATE TABLE IF NOT EXISTS raw.json_import (
    json_data text
);

-- raw.orders: добавлен id (SERIAL), row_hash для дедупликации
CREATE TABLE IF NOT EXISTS raw.orders (
    id                SERIAL PRIMARY KEY,
    order_id          text,
    customer_id       text,
    product_id        text,
    quantity          text,
    unit_price        text,
    currency          text,
    order_timestamp   text,
    status            text,
    row_hash          text -- UNIQUE  -- хэш исходных данных для быстрого поиска дубликатов
);

-- cleaned.orders: только очищенные бизнес-данные + хэш для дедупликации
CREATE TABLE IF NOT EXISTS cleaned.orders (
    id                SERIAL PRIMARY KEY,
    order_id          INTEGER,
    customer_id       INTEGER,
    product_id        INTEGER,
    quantity          INTEGER,
    unit_price        NUMERIC,
    currency          TEXT,
    order_timestamp   TIMESTAMP,
    status            TEXT,
    row_hash          TEXT UNIQUE
);

CREATE TABLE IF NOT EXISTS raw.products (
    id           SERIAL PRIMARY KEY,
    product_id   text,
    product_name text,
    category     text,
    price        text,
    currency     text,
    is_active    text,
    row_hash     text -- UNIQUE  -- хэш исходных данных для быстрого поиска дубликатов
);

-- cleaned.products: только очищенные бизнес-данные + хэш для дедупликации
CREATE TABLE IF NOT EXISTS cleaned.products (
    id           SERIAL PRIMARY KEY,
    product_id   INTEGER,
    product_name TEXT,
    category     TEXT,
    price        NUMERIC,
    currency     TEXT,
    is_active    BOOLEAN,
    row_hash     TEXT UNIQUE
);

-- raw.events: добавлен id (SERIAL), row_hash для дедупликации
CREATE TABLE IF NOT EXISTS raw.events (
    id                SERIAL PRIMARY KEY,
    event_id          text,
    customer_id       text,
    event_type        text,
    event_timestamp   text,
    product_id        text,
    row_hash          text -- UNIQUE  -- хэш исходных данных для быстрого поиска дубликатов
);

-- cleaned.events: только очищенные бизнес-данные + хэш для дедупликации
CREATE TABLE IF NOT EXISTS cleaned.events (
    id                SERIAL PRIMARY KEY,
    event_id          INTEGER,
    customer_id       INTEGER,
    event_type        TEXT,
    event_timestamp   TIMESTAMP,
    product_id        INTEGER,
    row_hash          TEXT UNIQUE
);

-- raw.payments: добавлен id (SERIAL), row_hash для дедупликации
CREATE TABLE IF NOT EXISTS raw.payments (
    id                SERIAL PRIMARY KEY,
    payment_id        text,
    order_id          text,
    payment_method    text,
    amount            text,
    currency          text,
    payment_timestamp text,
    row_hash          text --  UNIQUE  -- хэш исходных данных для быстрого поиска дубликатов
);

-- cleaned.payments: только очищенные бизнес-данные + хэш для дедупликации
CREATE TABLE IF NOT EXISTS cleaned.payments (
    id                SERIAL PRIMARY KEY,
    payment_id        INTEGER,
    order_id          INTEGER,
    payment_method    TEXT,
    amount            NUMERIC,
    currency          TEXT,
    payment_timestamp TIMESTAMP,
    row_hash          TEXT UNIQUE
);