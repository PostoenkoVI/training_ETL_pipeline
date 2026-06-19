CREATE OR REPLACE FUNCTION get_customers_without_orders(
    N INT DEFAULT NULL
)
RETURNS TABLE(
    customer_id INTEGER,  -- теперь INTEGER, как в hub_customer
    full_name TEXT
) LANGUAGE plpgsql STABLE AS $$
BEGIN
    RETURN QUERY
    WITH latest_customer AS (
        SELECT DISTINCT ON (sc.customer_hk)
            sc.customer_hk,
            hc.customer_id,
            sc.full_name
        FROM dwh.sat_customer sc
        JOIN dwh.hub_customer hc ON sc.customer_hk = hc.customer_hk
        ORDER BY sc.customer_hk, sc.load_datetime DESC
    )
    SELECT
        lc.customer_id,   -- прямое использование, без приведения
        lc.full_name
    FROM latest_customer lc
    WHERE NOT EXISTS (
        SELECT 1
        FROM dwh.link_order_customer_product locp
        WHERE locp.customer_hk = lc.customer_hk
    )
    ORDER BY lc.customer_id
    LIMIT COALESCE(N, 9223372036854775807);
END;
$$;