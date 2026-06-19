-- ============================================================
-- FUNCTION 1: Top products by number of 'view' events
-- ============================================================
CREATE OR REPLACE FUNCTION get_top_products_by_views(
    N INT DEFAULT 10
)
RETURNS TABLE(product_id TEXT, product_name TEXT, popularity BIGINT)
LANGUAGE plpgsql STABLE AS $$
BEGIN
    RETURN QUERY
    WITH
    latest_events AS (
        SELECT DISTINCT ON (se.event_hk)
            se.event_hk,
            se.event_type
        FROM dwh.sat_event se
        ORDER BY se.event_hk, se.load_datetime DESC
    ),
    latest_products AS (
        SELECT DISTINCT ON (sp.product_hk)
            sp.product_hk,
            sp.product_name
        FROM dwh.sat_product sp
        ORDER BY sp.product_hk, sp.load_datetime DESC
    ),
    counts AS (
        SELECT
            lecp.product_hk,
            COUNT(*) AS cnt
        FROM latest_events le
        JOIN dwh.link_event_customer_product lecp ON le.event_hk = lecp.event_hk
        WHERE le.event_type = 'view'
        GROUP BY lecp.product_hk
    )
    SELECT
        hp.product_id::TEXT,            -- приведение к TEXT
        lp.product_name,
        c.cnt                           -- уже BIGINT
    FROM counts c
    JOIN dwh.hub_product hp ON c.product_hk = hp.product_hk
    JOIN latest_products lp ON c.product_hk = lp.product_hk
    ORDER BY c.cnt DESC
    LIMIT N;
END;
$$;


-- ============================================================
-- FUNCTION 2: Top products by number of 'click' events
-- ============================================================
CREATE OR REPLACE FUNCTION get_top_products_by_clicks(
    N INT DEFAULT 10
)
RETURNS TABLE(product_id TEXT, product_name TEXT, popularity BIGINT)
LANGUAGE plpgsql STABLE AS $$
BEGIN
    RETURN QUERY
    WITH
    latest_events AS (
        SELECT DISTINCT ON (se.event_hk)
            se.event_hk,
            se.event_type
        FROM dwh.sat_event se
        ORDER BY se.event_hk, se.load_datetime DESC
    ),
    latest_products AS (
        SELECT DISTINCT ON (sp.product_hk)
            sp.product_hk,
            sp.product_name
        FROM dwh.sat_product sp
        ORDER BY sp.product_hk, sp.load_datetime DESC
    ),
    counts AS (
        SELECT
            lecp.product_hk,
            COUNT(*) AS cnt
        FROM latest_events le
        JOIN dwh.link_event_customer_product lecp ON le.event_hk = lecp.event_hk
        WHERE le.event_type = 'click'
        GROUP BY lecp.product_hk
    )
    SELECT
        hp.product_id::TEXT,
        lp.product_name,
        c.cnt
    FROM counts c
    JOIN dwh.hub_product hp ON c.product_hk = hp.product_hk
    JOIN latest_products lp ON c.product_hk = lp.product_hk
    ORDER BY c.cnt DESC
    LIMIT N;
END;
$$;


-- ============================================================
-- FUNCTION 3: Top products by number of 'purchase' events
-- ============================================================
CREATE OR REPLACE FUNCTION get_top_products_by_purchases(
    N INT DEFAULT 10
)
RETURNS TABLE(product_id TEXT, product_name TEXT, popularity BIGINT)
LANGUAGE plpgsql STABLE AS $$
BEGIN
    RETURN QUERY
    WITH
    latest_events AS (
        SELECT DISTINCT ON (se.event_hk)
            se.event_hk,
            se.event_type
        FROM dwh.sat_event se
        ORDER BY se.event_hk, se.load_datetime DESC
    ),
    latest_products AS (
        SELECT DISTINCT ON (sp.product_hk)
            sp.product_hk,
            sp.product_name
        FROM dwh.sat_product sp
        ORDER BY sp.product_hk, sp.load_datetime DESC
    ),
    counts AS (
        SELECT
            lecp.product_hk,
            COUNT(*) AS cnt
        FROM latest_events le
        JOIN dwh.link_event_customer_product lecp ON le.event_hk = lecp.event_hk
        WHERE le.event_type = 'purchase'
        GROUP BY lecp.product_hk
    )
    SELECT
        hp.product_id::TEXT,
        lp.product_name,
        c.cnt
    FROM counts c
    JOIN dwh.hub_product hp ON c.product_hk = hp.product_hk
    JOIN latest_products lp ON c.product_hk = lp.product_hk
    ORDER BY c.cnt DESC
    LIMIT N;
END;
$$;


-- ============================================================
-- FUNCTION 4: Top products by number of completed orders
-- ============================================================
CREATE OR REPLACE FUNCTION get_top_products_by_completed_orders(
    N INT DEFAULT 10
)
RETURNS TABLE(product_id TEXT, product_name TEXT, popularity BIGINT)
LANGUAGE plpgsql STABLE AS $$
BEGIN
    RETURN QUERY
    WITH
    latest_orders AS (
        SELECT DISTINCT ON (so.order_hk)
            so.order_hk,
            so.status
        FROM dwh.sat_order so
        ORDER BY so.order_hk, so.load_datetime DESC
    ),
    latest_products AS (
        SELECT DISTINCT ON (sp.product_hk)
            sp.product_hk,
            sp.product_name
        FROM dwh.sat_product sp
        ORDER BY sp.product_hk, sp.load_datetime DESC
    ),
    counts AS (
        SELECT
            locp.product_hk,
            COUNT(*) AS cnt
        FROM latest_orders lo
        JOIN dwh.link_order_customer_product locp ON lo.order_hk = locp.order_hk
        WHERE lo.status = 'completed'
        GROUP BY locp.product_hk
    )
    SELECT
        hp.product_id::TEXT,
        lp.product_name,
        c.cnt
    FROM counts c
    JOIN dwh.hub_product hp ON c.product_hk = hp.product_hk
    JOIN latest_products lp ON c.product_hk = lp.product_hk
    ORDER BY c.cnt DESC
    LIMIT N;
END;
$$;