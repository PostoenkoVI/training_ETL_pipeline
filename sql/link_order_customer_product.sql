-- ================================
-- 1. Create link table if not exists
-- ================================
CREATE TABLE IF NOT EXISTS dwh.link_order_customer_product (
    link_hk        CHAR(32)    PRIMARY KEY,
    order_hk       CHAR(32)    NOT NULL,
    customer_hk    CHAR(32)    NOT NULL,
    product_hk     CHAR(32)    NOT NULL,
    load_datetime  TIMESTAMP   NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_link_order_customer_product_order    ON dwh.link_order_customer_product(order_hk);
CREATE INDEX IF NOT EXISTS idx_link_order_customer_product_customer ON dwh.link_order_customer_product(customer_hk);
CREATE INDEX IF NOT EXISTS idx_link_order_customer_product_product  ON dwh.link_order_customer_product(product_hk);

-- ================================
-- 2. Load link with FK validation and logging
-- ================================

-- 2a. Log rows with missing references
INSERT INTO logs.rejected_records (source_table, load_datetime, raw_payload, error_details)
SELECT
    'orders',
    CURRENT_TIMESTAMP,
    row_to_json(o),
    jsonb_build_object(
        'level',  'warn',
        'reason', 'missing_reference',
        'details', jsonb_build_object(
            'missing_type',
            CASE 
                WHEN ho.order_hk IS NULL    THEN 'order_id'
                WHEN hc.customer_hk IS NULL THEN 'customer_id'
                WHEN hp.product_hk IS NULL  THEN 'product_id'
            END,
            'missing_value',
            CASE 
                WHEN ho.order_hk IS NULL    THEN o.order_id
                WHEN hc.customer_hk IS NULL THEN o.customer_id
                WHEN hp.product_hk IS NULL  THEN o.product_id
            END,
            'source_table', 'cleaned.orders'
        )
    )
FROM cleaned.orders o
LEFT JOIN dwh.hub_order    ho ON ho.order_id    = o.order_id
LEFT JOIN dwh.hub_customer hc ON hc.customer_id = o.customer_id
LEFT JOIN dwh.hub_product  hp ON hp.product_id  = o.product_id
WHERE o.order_id IS NOT NULL
  AND o.customer_id IS NOT NULL
  AND o.product_id  IS NOT NULL
  AND (ho.order_hk IS NULL OR hc.customer_hk IS NULL OR hp.product_hk IS NULL);


-- 2b. Insert only rows with all references present (and not already linked)
WITH source AS (
    SELECT
        o.order_id,
        o.customer_id,
        o.product_id,
        ho.order_hk,
        hc.customer_hk,
        hp.product_hk,
        MD5(
            COALESCE(o.order_id::text, '')    || '||' ||
            COALESCE(o.customer_id::text, '') || '||' ||
            COALESCE(o.product_id::text, '')
        ) AS link_hk
    FROM cleaned.orders o
    LEFT JOIN dwh.hub_order    ho ON ho.order_id    = o.order_id
    LEFT JOIN dwh.hub_customer hc ON hc.customer_id = o.customer_id
    LEFT JOIN dwh.hub_product  hp ON hp.product_id  = o.product_id
    WHERE o.order_id IS NOT NULL
      AND o.customer_id IS NOT NULL
      AND o.product_id  IS NOT NULL
)
INSERT INTO dwh.link_order_customer_product (link_hk, order_hk, customer_hk, product_hk, load_datetime)
SELECT
    s.link_hk,
    s.order_hk,
    s.customer_hk,
    s.product_hk,
    CURRENT_TIMESTAMP
FROM source s
WHERE s.order_hk    IS NOT NULL
  AND s.customer_hk IS NOT NULL
  AND s.product_hk  IS NOT NULL
ON CONFLICT (link_hk) DO NOTHING;