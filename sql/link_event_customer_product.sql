-- ================================
-- 1. Create link table if not exists
-- ================================
CREATE TABLE IF NOT EXISTS dwh.link_event_customer_product (
    link_hk        CHAR(32)    PRIMARY KEY,
    event_hk       CHAR(32)    NOT NULL,
    customer_hk    CHAR(32)    NOT NULL,
    product_hk     CHAR(32)    NOT NULL,
    load_datetime  TIMESTAMP   NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_link_event_customer_product_event    ON dwh.link_event_customer_product(event_hk);
CREATE INDEX IF NOT EXISTS idx_link_event_customer_product_customer ON dwh.link_event_customer_product(customer_hk);
CREATE INDEX IF NOT EXISTS idx_link_event_customer_product_product  ON dwh.link_event_customer_product(product_hk);

-- ================================
-- 2. Load link with FK validation and logging
-- ================================

-- 2a. Log rows with missing references
INSERT INTO logs.rejected_records (source_table, load_datetime, raw_payload, error_details)
SELECT
    'events',
    CURRENT_TIMESTAMP,
    row_to_json(e),
    jsonb_build_object(
        'level',  'warn',
        'reason', 'missing_reference',
        'details', jsonb_build_object(
            'missing_type',
            CASE 
                WHEN he.event_hk IS NULL    THEN 'event_id'
                WHEN hc.customer_hk IS NULL THEN 'customer_id'
                WHEN hp.product_hk IS NULL  THEN 'product_id'
            END,
            'missing_value',
            CASE 
                WHEN he.event_hk IS NULL    THEN e.event_id
                WHEN hc.customer_hk IS NULL THEN e.customer_id
                WHEN hp.product_hk IS NULL  THEN e.product_id
            END,
            'source_table', 'cleaned.events'
        )
    )
FROM cleaned.events e
LEFT JOIN dwh.hub_event    he ON he.event_id    = e.event_id
LEFT JOIN dwh.hub_customer hc ON hc.customer_id = e.customer_id
LEFT JOIN dwh.hub_product  hp ON hp.product_id  = e.product_id
WHERE e.event_id IS NOT NULL
  AND e.customer_id IS NOT NULL
  AND e.product_id  IS NOT NULL
  AND (he.event_hk IS NULL OR hc.customer_hk IS NULL OR hp.product_hk IS NULL);

WITH source AS (
    SELECT
        e.event_id,
        e.customer_id,
        e.product_id,
        he.event_hk,
        hc.customer_hk,
        hp.product_hk,
        MD5(
            COALESCE(e.event_id::text, '')    || '||' ||
            COALESCE(e.customer_id::text, '') || '||' ||
            COALESCE(e.product_id::text, '')
        ) AS link_hk
    FROM cleaned.events e
    LEFT JOIN dwh.hub_event    he ON he.event_id    = e.event_id
    LEFT JOIN dwh.hub_customer hc ON hc.customer_id = e.customer_id
    LEFT JOIN dwh.hub_product  hp ON hp.product_id  = e.product_id
    WHERE e.event_id IS NOT NULL
      AND e.customer_id IS NOT NULL
      AND e.product_id  IS NOT NULL
)
-- 2b. Insert only rows with all references present (and not already linked)
INSERT INTO dwh.link_event_customer_product (link_hk, event_hk, customer_hk, product_hk, load_datetime)
SELECT
    s.link_hk,
    s.event_hk,
    s.customer_hk,
    s.product_hk,
    CURRENT_TIMESTAMP
FROM source s
WHERE s.event_hk    IS NOT NULL
  AND s.customer_hk IS NOT NULL
  AND s.product_hk  IS NOT NULL
ON CONFLICT (link_hk) DO NOTHING;