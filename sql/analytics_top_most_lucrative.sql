CREATE OR REPLACE FUNCTION get_top_customers(
    preferred_currency TEXT,
    exchange_rates JSONB DEFAULT NULL,
    top_n INT DEFAULT 10
)
RETURNS TABLE(
    customer_id INTEGER,   -- изменено с TEXT на INTEGER
    full_name TEXT,
    total_spent NUMERIC
) LANGUAGE plpgsql STABLE AS $$
DECLARE
    base_rate NUMERIC;
BEGIN
    -- Normalize exchange rates: divide all rates by the rate of preferred_currency
    IF exchange_rates IS NOT NULL THEN
        base_rate := COALESCE((exchange_rates ->> preferred_currency)::NUMERIC, 1.0);
    END IF;

    RETURN QUERY
    WITH
    -- 0. Normalized rates (if exchange_rates provided)
    normalized_rates AS (
        SELECT
            key AS currency,
            (value::NUMERIC / base_rate) AS rate
        FROM jsonb_each(exchange_rates)
        WHERE exchange_rates IS NOT NULL
    ),

    -- 1. Latest payment satellite (amount & currency per payment)
    latest_payment_sat AS (
        SELECT DISTINCT ON (sp.payment_hk)
            sp.payment_hk,
            sp.amount,
            sp.currency
        FROM dwh.sat_payment sp
        ORDER BY sp.payment_hk, sp.load_datetime DESC
    ),

    -- 2. Latest order satellite (status per order)
    latest_order_sat AS (
        SELECT DISTINCT ON (so.order_hk)
            so.order_hk,
            so.status
        FROM dwh.sat_order so
        ORDER BY so.order_hk, so.load_datetime DESC
    ),

    -- 3. Link payments → orders → customers
    payment_order_customer AS (
        SELECT
            lpo.payment_hk,
            lpo.order_hk,
            locp.customer_hk,
            lp.amount,
            lp.currency
        FROM dwh.link_payment_order lpo
        JOIN latest_payment_sat lp ON lpo.payment_hk = lp.payment_hk
        JOIN latest_order_sat lo ON lpo.order_hk = lo.order_hk
        JOIN dwh.link_order_customer_product locp ON lpo.order_hk = locp.order_hk
        WHERE lo.status = 'completed'
    ),

    -- 4. Convert amounts to preferred currency (using normalized rates)
    converted AS (
        SELECT
            poc.customer_hk,
            CASE
                WHEN poc.currency = preferred_currency THEN poc.amount
                WHEN exchange_rates IS NOT NULL
                     AND EXISTS (SELECT 1 FROM normalized_rates nr WHERE nr.currency = poc.currency)
                THEN poc.amount * (SELECT nr.rate FROM normalized_rates nr WHERE nr.currency = poc.currency)
                ELSE NULL
            END AS converted_amount
        FROM payment_order_customer poc
    ),

    -- 5. Sum per customer
    customer_spend AS (
        SELECT
            conv.customer_hk,
            SUM(conv.converted_amount) AS total_spent
        FROM converted conv
        WHERE conv.converted_amount IS NOT NULL
        GROUP BY conv.customer_hk
    ),

    -- 6. Latest customer satellite + hub to get customer_id (INTEGER)
    latest_customer_sat AS (
        SELECT DISTINCT ON (sc.customer_hk)
            sc.customer_hk,
            hc.customer_id,   -- INTEGER
            sc.full_name
        FROM dwh.sat_customer sc
        JOIN dwh.hub_customer hc ON sc.customer_hk = hc.customer_hk
        ORDER BY sc.customer_hk, sc.load_datetime DESC
    )

    -- 7. Join and return top N
    SELECT
        lcs.customer_id,    -- теперь INTEGER, без приведения
        lcs.full_name,
        cs.total_spent
    FROM customer_spend cs
    JOIN latest_customer_sat lcs ON cs.customer_hk = lcs.customer_hk
    ORDER BY cs.total_spent DESC
    LIMIT top_n;
END;
$$;