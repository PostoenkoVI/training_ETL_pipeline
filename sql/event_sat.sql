-- ================================
-- 1. Ensure schema exists
-- ================================
CREATE SCHEMA IF NOT EXISTS dwh;

-- ================================
-- 2. Create satellite table (if not exists)
-- ================================
CREATE TABLE IF NOT EXISTS dwh.sat_event (
    event_hk          CHAR(32)    NOT NULL,
    load_datetime     TIMESTAMP   NOT NULL,
    customer_id       INTEGER,
    event_type        TEXT,
    event_timestamp   TIMESTAMP,
    product_id        INTEGER,
    hash_diff         CHAR(32)    NOT NULL,
    PRIMARY KEY (event_hk, load_datetime)
);

-- Index for fast lookups of the latest record per event
CREATE INDEX IF NOT EXISTS idx_sat_event_hk ON dwh.sat_event(event_hk);

-- ================================
-- 3. Load new/changed event data into satellite
-- ================================
WITH source AS (
    SELECT
        h.event_hk,
        c.event_id,
        c.customer_id,
        c.event_type,
        c.event_timestamp,
        c.product_id,
        -- Compute hash_diff from all descriptive attributes
        MD5(
            COALESCE(c.customer_id::text, '')     || '||' ||
            COALESCE(c.event_type, '')            || '||' ||
            COALESCE(c.event_timestamp::text, '') || '||' ||
            COALESCE(c.product_id::text, '')
        ) AS hash_diff
    FROM cleaned.events c
    JOIN dwh.hub_event h ON h.event_id = c.event_id
    WHERE c.event_id IS NOT NULL   -- defensive, but cleaned.events should already have no nulls
),
latest_sat AS (
    SELECT
        event_hk,
        hash_diff,
        ROW_NUMBER() OVER (PARTITION BY event_hk ORDER BY load_datetime DESC) AS rn
    FROM dwh.sat_event
)
INSERT INTO dwh.sat_event (event_hk, load_datetime, customer_id, event_type, event_timestamp, product_id, hash_diff)
SELECT
    s.event_hk,
    CURRENT_TIMESTAMP,
    s.customer_id,
    s.event_type,
    s.event_timestamp,
    s.product_id,
    s.hash_diff
FROM source s
LEFT JOIN latest_sat l ON l.event_hk = s.event_hk AND l.rn = 1
WHERE l.event_hk IS NULL           -- no satellite record yet
   OR l.hash_diff <> s.hash_diff;   -- attributes changed