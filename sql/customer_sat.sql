-- ================================
-- 1. Ensure schema exists
-- ================================
CREATE SCHEMA IF NOT EXISTS dwh;

-- ================================
-- 2. Create satellite table (if not exists)
-- ================================
CREATE TABLE IF NOT EXISTS dwh.sat_customer (
    customer_hk    CHAR(32)    NOT NULL,
    load_datetime  TIMESTAMP   NOT NULL,
    full_name      TEXT,
    email          TEXT,
    phone          TEXT,
    city           TEXT,
    created_at     DATE,
    hash_diff      CHAR(32)    NOT NULL,
    PRIMARY KEY (customer_hk, load_datetime)
);

-- Index for fast lookups of the latest record per customer
CREATE INDEX IF NOT EXISTS idx_sat_customer_hk ON dwh.sat_customer(customer_hk);

-- ================================
-- 3. Load new/changed customer data into satellite
-- ================================
WITH source AS (
    SELECT
        h.customer_hk,
        c.customer_id,
        c.full_name,
        c.email,
        c.phone,
        c.city,
        c.created_at,
        -- Compute hash_diff from all descriptive attributes
        MD5(
            COALESCE(c.full_name, '')  || '||' ||
            COALESCE(c.email, '')      || '||' ||
            COALESCE(c.phone, '')      || '||' ||
            COALESCE(c.city, '')       || '||' ||
            COALESCE(c.created_at::text, '')
        ) AS hash_diff
    FROM cleaned.customers c
    JOIN dwh.hub_customer h ON h.customer_id = c.customer_id
    WHERE c.customer_id IS NOT NULL
),
latest_sat AS (
    SELECT
        customer_hk,
        hash_diff,
        ROW_NUMBER() OVER (PARTITION BY customer_hk ORDER BY load_datetime DESC) AS rn
    FROM dwh.sat_customer
)
INSERT INTO dwh.sat_customer (customer_hk, load_datetime, full_name, email, phone, city, created_at, hash_diff)
SELECT
    s.customer_hk,
    CURRENT_TIMESTAMP,
    s.full_name,
    s.email,
    s.phone,
    s.city,
    s.created_at,
    s.hash_diff
FROM source s
LEFT JOIN latest_sat l ON l.customer_hk = s.customer_hk AND l.rn = 1
WHERE l.customer_hk IS NULL           -- no satellite record yet
   OR l.hash_diff <> s.hash_diff;     -- attributes changed