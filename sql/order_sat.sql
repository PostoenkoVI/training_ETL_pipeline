-- ================================
-- 1. Ensure schema exists
-- ================================
CREATE SCHEMA IF NOT EXISTS dwh;

-- ================================
-- 2. Create satellite table (if not exists)
-- ================================
CREATE TABLE IF NOT EXISTS dwh.sat_order (
    order_hk          CHAR(32)    NOT NULL,
    load_datetime     TIMESTAMP   NOT NULL,
    customer_id       INTEGER,
    product_id        INTEGER,
    quantity          INTEGER,
    unit_price        NUMERIC,
    currency          TEXT,
    order_timestamp   TIMESTAMP,
    status            TEXT,
    hash_diff         CHAR(32)    NOT NULL,
    PRIMARY KEY (order_hk, load_datetime)
);

-- Index for fast lookups of the latest record per order
CREATE INDEX IF NOT EXISTS idx_sat_order_hk ON dwh.sat_order(order_hk);

-- ================================
-- 3. Load new/changed order data into satellite
-- ================================
WITH source AS (
    SELECT
        h.order_hk,
        c.order_id,
        c.customer_id,
        c.product_id,
        c.quantity,
        c.unit_price,
        c.currency,
        c.order_timestamp,
        c.status,
        -- Compute hash_diff from all descriptive attributes
        MD5(
            COALESCE(c.customer_id::text, '')     || '||' ||
            COALESCE(c.product_id::text, '')      || '||' ||
            COALESCE(c.quantity::text, '')        || '||' ||
            COALESCE(c.unit_price::text, '')      || '||' ||
            COALESCE(c.currency, '')              || '||' ||
            COALESCE(c.order_timestamp::text, '') || '||' ||
            COALESCE(c.status, '')
        ) AS hash_diff
    FROM cleaned.orders c
    JOIN dwh.hub_order h ON h.order_id = c.order_id
    WHERE c.order_id IS NOT NULL   -- defensive, but cleaned.orders should already have no nulls
),
latest_sat AS (
    SELECT
        order_hk,
        hash_diff,
        ROW_NUMBER() OVER (PARTITION BY order_hk ORDER BY load_datetime DESC) AS rn
    FROM dwh.sat_order
)
INSERT INTO dwh.sat_order (order_hk, load_datetime, customer_id, product_id, quantity, unit_price, currency, order_timestamp, status, hash_diff)
SELECT
    s.order_hk,
    CURRENT_TIMESTAMP,
    s.customer_id,
    s.product_id,
    s.quantity,
    s.unit_price,
    s.currency,
    s.order_timestamp,
    s.status,
    s.hash_diff
FROM source s
LEFT JOIN latest_sat l ON l.order_hk = s.order_hk AND l.rn = 1
WHERE l.order_hk IS NULL           -- no satellite record yet
   OR l.hash_diff <> s.hash_diff;   -- attributes changed