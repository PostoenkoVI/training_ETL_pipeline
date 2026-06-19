-- ================================
-- 1. Ensure schema exists
-- ================================
CREATE SCHEMA IF NOT EXISTS dwh;

-- ================================
-- 2. Create satellite table (if not exists)
-- ================================
CREATE TABLE IF NOT EXISTS dwh.sat_payment (
    payment_hk        CHAR(32)    NOT NULL,
    load_datetime     TIMESTAMP   NOT NULL,
    order_id          INTEGER,
    payment_method    TEXT,
    amount            NUMERIC,
    currency          TEXT,
    payment_timestamp TIMESTAMP,
    hash_diff         CHAR(32)    NOT NULL,
    PRIMARY KEY (payment_hk, load_datetime)
);

-- Index for fast lookups of the latest record per payment
CREATE INDEX IF NOT EXISTS idx_sat_payment_hk ON dwh.sat_payment(payment_hk);

-- ================================
-- 3. Load new/changed payment data into satellite
-- ================================
WITH source AS (
    SELECT
        h.payment_hk,
        c.payment_id,
        c.order_id,
        c.payment_method,
        c.amount,
        c.currency,
        c.payment_timestamp,
        -- Compute hash_diff from all descriptive attributes
        MD5(
            COALESCE(c.order_id::text, '')          || '||' ||
            COALESCE(c.payment_method, '')          || '||' ||
            COALESCE(c.amount::text, '')            || '||' ||
            COALESCE(c.currency, '')                || '||' ||
            COALESCE(c.payment_timestamp::text, '')
        ) AS hash_diff
    FROM cleaned.payments c
    JOIN dwh.hub_payment h ON h.payment_id = c.payment_id
    WHERE c.payment_id IS NOT NULL   -- defensive, but cleaned.payments should already have no nulls
),
latest_sat AS (
    SELECT
        payment_hk,
        hash_diff,
        ROW_NUMBER() OVER (PARTITION BY payment_hk ORDER BY load_datetime DESC) AS rn
    FROM dwh.sat_payment
)
INSERT INTO dwh.sat_payment (payment_hk, load_datetime, order_id, payment_method, amount, currency, payment_timestamp, hash_diff)
SELECT
    s.payment_hk,
    CURRENT_TIMESTAMP,
    s.order_id,
    s.payment_method,
    s.amount,
    s.currency,
    s.payment_timestamp,
    s.hash_diff
FROM source s
LEFT JOIN latest_sat l ON l.payment_hk = s.payment_hk AND l.rn = 1
WHERE l.payment_hk IS NULL           -- no satellite record yet
   OR l.hash_diff <> s.hash_diff;     -- attributes changed