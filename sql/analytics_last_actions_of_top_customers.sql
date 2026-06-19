-- ===================================================================
-- FUNCTION 1: Top customers by number of completed orders
-- ===================================================================
CREATE OR REPLACE FUNCTION get_top_customers_by_orders(
    N INT DEFAULT 5
)
RETURNS TABLE(
    customer_id INTEGER,      -- изменено с TEXT на INTEGER
    full_name TEXT,
    order_count BIGINT,
    last_action_date DATE
) LANGUAGE plpgsql STABLE AS $$
BEGIN
    RETURN QUERY
    WITH
    -- Latest order satellite (status)
    latest_orders AS (
        SELECT DISTINCT ON (so.order_hk)
            so.order_hk,
            so.status
        FROM dwh.sat_order so
        ORDER BY so.order_hk, so.load_datetime DESC
    ),
    -- Latest event satellite (for last action date)
    latest_events AS (
        SELECT DISTINCT ON (se.event_hk)
            se.event_hk,
            se.event_timestamp
        FROM dwh.sat_event se
        ORDER BY se.event_hk, se.load_datetime DESC
    ),
    -- Completed orders per customer
    customer_order_counts AS (
        SELECT
            locp.customer_hk,
            COUNT(*) AS cnt
        FROM dwh.link_order_customer_product locp
        JOIN latest_orders lo ON locp.order_hk = lo.order_hk
        WHERE lo.status = 'completed'
        GROUP BY locp.customer_hk
    ),
    -- Top N customers by order count
    top_customers AS (
        SELECT
            coc.customer_hk,
            coc.cnt
        FROM customer_order_counts coc
        ORDER BY coc.cnt DESC
        LIMIT N
    ),
    -- Latest customer satellite + hub to get customer_id (INTEGER)
    latest_customers AS (
        SELECT DISTINCT ON (sc.customer_hk)
            sc.customer_hk,
            hc.customer_id,   -- INTEGER
            sc.full_name
        FROM dwh.sat_customer sc
        JOIN dwh.hub_customer hc ON sc.customer_hk = hc.customer_hk
        ORDER BY sc.customer_hk, sc.load_datetime DESC
    ),
    -- Last action date per customer (from all events, not only purchases)
    last_actions AS (
        SELECT
            lecp.customer_hk,
            MAX(le.event_timestamp)::DATE AS last_date
        FROM latest_events le
        JOIN dwh.link_event_customer_product lecp ON le.event_hk = lecp.event_hk
        GROUP BY lecp.customer_hk
    )
    SELECT
        lc.customer_id,       -- теперь INTEGER
        lc.full_name,
        tc.cnt AS order_count,
        la.last_date
    FROM top_customers tc
    JOIN latest_customers lc ON tc.customer_hk = lc.customer_hk
    LEFT JOIN last_actions la ON tc.customer_hk = la.customer_hk
    ORDER BY tc.cnt DESC;
END;
$$;


-- ===================================================================
-- FUNCTION 2: Top customers by number of purchase events
-- ===================================================================
CREATE OR REPLACE FUNCTION get_top_customers_by_purchases(
    N INT DEFAULT 5
)
RETURNS TABLE(
    customer_id INTEGER,      -- изменено с TEXT на INTEGER
    full_name TEXT,
    purchase_count BIGINT,
    last_action_date DATE
) LANGUAGE plpgsql STABLE AS $$
BEGIN
    RETURN QUERY
    WITH
    -- Latest event satellite (to filter purchase events)
    latest_events AS (
        SELECT DISTINCT ON (se.event_hk)
            se.event_hk,
            se.event_type,
            se.event_timestamp
        FROM dwh.sat_event se
        ORDER BY se.event_hk, se.load_datetime DESC
    ),
    -- Purchase events per customer
    customer_event_counts AS (
        SELECT
            lecp.customer_hk,
            COUNT(*) AS cnt
        FROM latest_events le
        JOIN dwh.link_event_customer_product lecp ON le.event_hk = lecp.event_hk
        WHERE le.event_type = 'purchase'
        GROUP BY lecp.customer_hk
    ),
    -- Top N customers by purchase count
    top_customers AS (
        SELECT
            cec.customer_hk,
            cec.cnt
        FROM customer_event_counts cec
        ORDER BY cec.cnt DESC
        LIMIT N
    ),
    -- Latest customer satellite + hub to get customer_id (INTEGER)
    latest_customers AS (
        SELECT DISTINCT ON (sc.customer_hk)
            sc.customer_hk,
            hc.customer_id,   -- INTEGER
            sc.full_name
        FROM dwh.sat_customer sc
        JOIN dwh.hub_customer hc ON sc.customer_hk = hc.customer_hk
        ORDER BY sc.customer_hk, sc.load_datetime DESC
    ),
    -- Last action date per customer (from all events, not only purchases)
    last_actions AS (
        SELECT
            lecp.customer_hk,
            MAX(le.event_timestamp)::DATE AS last_date
        FROM latest_events le
        JOIN dwh.link_event_customer_product lecp ON le.event_hk = lecp.event_hk
        GROUP BY lecp.customer_hk
    )
    SELECT
        lc.customer_id,       -- теперь INTEGER
        lc.full_name,
        tc.cnt AS purchase_count,
        la.last_date
    FROM top_customers tc
    JOIN latest_customers lc ON tc.customer_hk = lc.customer_hk
    LEFT JOIN last_actions la ON tc.customer_hk = la.customer_hk
    ORDER BY tc.cnt DESC;
END;
$$;