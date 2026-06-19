-- ================================
-- 1. Ensure schema exists
-- ================================
CREATE SCHEMA IF NOT EXISTS dwh;

-- ================================
-- 2. Create satellite table (if not exists)
-- ================================
CREATE TABLE IF NOT EXISTS dwh.sat_product (
    product_hk     CHAR(32)    NOT NULL,
    load_datetime  TIMESTAMP   NOT NULL,
    product_name   TEXT,
    category       TEXT,
    price          NUMERIC,
    currency       TEXT,
    is_active      BOOLEAN,
    hash_diff      CHAR(32)    NOT NULL,
    PRIMARY KEY (product_hk, load_datetime)
);

-- Index for fast lookups of the latest record per product
CREATE INDEX IF NOT EXISTS idx_sat_product_hk ON dwh.sat_product(product_hk);

-- ================================
-- 3. Load new/changed product data into satellite
-- ================================
WITH source AS (
    SELECT
        h.product_hk,
        c.product_id,
        c.product_name,
        c.category,
        c.price,
        c.currency,
        c.is_active,
        -- Compute hash_diff from all descriptive attributes
        MD5(
            COALESCE(c.product_name, '') || '||' ||
            COALESCE(c.category, '')     || '||' ||
            COALESCE(c.price::text, '')  || '||' ||
            COALESCE(c.currency, '')     || '||' ||
            COALESCE(c.is_active::text, '')
        ) AS hash_diff
    FROM cleaned.products c
    JOIN dwh.hub_product h ON h.product_id = c.product_id
    WHERE c.product_id IS NOT NULL   -- defensive, but cleaned.products should already have no nulls
),
latest_sat AS (
    SELECT
        product_hk,
        hash_diff,
        ROW_NUMBER() OVER (PARTITION BY product_hk ORDER BY load_datetime DESC) AS rn
    FROM dwh.sat_product
)
INSERT INTO dwh.sat_product (product_hk, load_datetime, product_name, category, price, currency, is_active, hash_diff)
SELECT
    s.product_hk,
    CURRENT_TIMESTAMP,
    s.product_name,
    s.category,
    s.price,
    s.currency,
    s.is_active,
    s.hash_diff
FROM source s
LEFT JOIN latest_sat l ON l.product_hk = s.product_hk AND l.rn = 1
WHERE l.product_hk IS NULL           -- no satellite record yet
   OR l.hash_diff <> s.hash_diff;     -- attributes changed