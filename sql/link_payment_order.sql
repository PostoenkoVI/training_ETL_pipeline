-- ================================
-- 1. Create link table if not exists
-- ================================
CREATE TABLE IF NOT EXISTS dwh.link_payment_order (
    link_hk        CHAR(32)    PRIMARY KEY,
    payment_hk     CHAR(32)    NOT NULL,
    order_hk       CHAR(32)    NOT NULL,
    load_datetime  TIMESTAMP   NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_link_payment_order_payment ON dwh.link_payment_order(payment_hk);
CREATE INDEX IF NOT EXISTS idx_link_payment_order_order   ON dwh.link_payment_order(order_hk);

-- ================================
-- 2. Load link with FK validation and logging
-- ================================


-- 2a. Log rows with missing references
INSERT INTO logs.rejected_records (source_table, load_datetime, raw_payload, error_details)
SELECT
    'payments',
    CURRENT_TIMESTAMP,
    row_to_json(p),
    jsonb_build_object(
        'level',  'warn',
        'reason', 'missing_reference',
        'details', jsonb_build_object(
            'missing_type',
            CASE 
                WHEN hp.payment_hk IS NULL THEN 'payment_id'
                WHEN ho.order_hk   IS NULL THEN 'order_id'
            END,
            'missing_value',
            CASE 
                WHEN hp.payment_hk IS NULL THEN p.payment_id
                WHEN ho.order_hk   IS NULL THEN p.order_id
            END,
            'source_table', 'cleaned.payments'
        )
    )
FROM cleaned.payments p
LEFT JOIN dwh.hub_payment hp ON hp.payment_id = p.payment_id
LEFT JOIN dwh.hub_order   ho ON ho.order_id   = p.order_id
WHERE p.payment_id IS NOT NULL
  AND p.order_id   IS NOT NULL
  AND (hp.payment_hk IS NULL OR ho.order_hk IS NULL);

-- 2b. Insert only rows with all references present (and not already linked)
WITH source AS (
    SELECT
        p.payment_id,
        p.order_id,
        hp.payment_hk,
        ho.order_hk,
        MD5(
            COALESCE(p.payment_id::text, '') || '||' ||
            COALESCE(p.order_id::text, '')
        ) AS link_hk
    FROM cleaned.payments p
    LEFT JOIN dwh.hub_payment hp ON hp.payment_id = p.payment_id
    LEFT JOIN dwh.hub_order   ho ON ho.order_id   = p.order_id
    WHERE p.payment_id IS NOT NULL
      AND p.order_id   IS NOT NULL   -- skip rows with null FKs in cleaned data
)
INSERT INTO dwh.link_payment_order (link_hk, payment_hk, order_hk, load_datetime)
SELECT
    s.link_hk,
    s.payment_hk,
    s.order_hk,
    CURRENT_TIMESTAMP
FROM source s
WHERE s.payment_hk IS NOT NULL
  AND s.order_hk   IS NOT NULL
ON CONFLICT (link_hk) DO NOTHING;