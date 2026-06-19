-- ================================
-- 1. Ensure schema exists
-- ================================
CREATE SCHEMA IF NOT EXISTS dwh;

-- ================================
-- 2. Create all hub tables (if not exists)
-- ================================
CREATE TABLE IF NOT EXISTS dwh.hub_customer (
    customer_hk   CHAR(32)    PRIMARY KEY,
    customer_id   INTEGER     NOT NULL,
    load_datetime TIMESTAMP   NOT NULL
);

CREATE TABLE IF NOT EXISTS dwh.hub_product (
    product_hk    CHAR(32)    PRIMARY KEY,
    product_id    INTEGER     NOT NULL,
    load_datetime TIMESTAMP   NOT NULL
);

CREATE TABLE IF NOT EXISTS dwh.hub_event (
    event_hk      CHAR(32)    PRIMARY KEY,
    event_id      INTEGER     NOT NULL,
    load_datetime TIMESTAMP   NOT NULL
);

CREATE TABLE IF NOT EXISTS dwh.hub_order (
    order_hk      CHAR(32)    PRIMARY KEY,
    order_id      INTEGER     NOT NULL,
    load_datetime TIMESTAMP   NOT NULL
);

CREATE TABLE IF NOT EXISTS dwh.hub_payment (
    payment_hk    CHAR(32)    PRIMARY KEY,
    payment_id    INTEGER     NOT NULL,
    load_datetime TIMESTAMP   NOT NULL
);

-- ================================
-- 2b. Unique indexes on business keys (required for ON CONFLICT)
-- ================================
CREATE UNIQUE INDEX IF NOT EXISTS idx_hub_customer_customer_id 
    ON dwh.hub_customer(customer_id);
CREATE UNIQUE INDEX IF NOT EXISTS idx_hub_product_product_id 
    ON dwh.hub_product(product_id);
CREATE UNIQUE INDEX IF NOT EXISTS idx_hub_event_event_id
    ON dwh.hub_event(event_id);
CREATE UNIQUE INDEX IF NOT EXISTS idx_hub_order_order_id 
    ON dwh.hub_order(order_id);
CREATE UNIQUE INDEX IF NOT EXISTS idx_hub_payment_payment_id 
    ON dwh.hub_payment(payment_id);

-- ================================
-- 3. Insert new business keys with ON CONFLICT
-- ================================

-- 3.1 Customer hub
INSERT INTO dwh.hub_customer (customer_hk, customer_id, load_datetime)
SELECT DISTINCT
    MD5(CAST(customer_id AS text)),
    customer_id,
    CURRENT_TIMESTAMP
FROM cleaned.customers
WHERE customer_id IS NOT NULL
ON CONFLICT (customer_id) DO NOTHING;

-- 3.2 Product hub
INSERT INTO dwh.hub_product (product_hk, product_id, load_datetime)
SELECT DISTINCT
    MD5(CAST(product_id AS text)),
    product_id,
    CURRENT_TIMESTAMP
FROM cleaned.products
WHERE product_id IS NOT NULL
ON CONFLICT (product_id) DO NOTHING;

-- 3.3 Event hub
INSERT INTO dwh.hub_event (event_hk, event_id, load_datetime)
SELECT DISTINCT
    MD5(CAST(event_id AS text)),
    event_id,
    CURRENT_TIMESTAMP
FROM cleaned.events
WHERE event_id IS NOT NULL
ON CONFLICT (event_id) DO NOTHING;

-- 3.4 Order hub
INSERT INTO dwh.hub_order (order_hk, order_id, load_datetime)
SELECT DISTINCT
    MD5(CAST(order_id AS text)),
    order_id,
    CURRENT_TIMESTAMP
FROM cleaned.orders
WHERE order_id IS NOT NULL
ON CONFLICT (order_id) DO NOTHING;

-- 3.5 Payment hub
INSERT INTO dwh.hub_payment (payment_hk, payment_id, load_datetime)
SELECT DISTINCT
    MD5(CAST(payment_id AS text)),
    payment_id,
    CURRENT_TIMESTAMP
FROM cleaned.payments
WHERE payment_id IS NOT NULL
ON CONFLICT (payment_id) DO NOTHING;