CREATE OR REPLACE FUNCTION get_monthly_revenue(
    preferred_currency TEXT,
    exchange_rates JSONB DEFAULT NULL
)
RETURNS TABLE(month DATE, total_revenue NUMERIC) 
LANGUAGE plpgsql STABLE AS $$
DECLARE
    base_rate NUMERIC;
BEGIN
    -- Normalize exchange rates: divide all rates by the rate of preferred_currency
    IF exchange_rates IS NOT NULL THEN
        base_rate := COALESCE((exchange_rates ->> preferred_currency)::NUMERIC, 1.0);
    END IF;

    RETURN QUERY
    WITH
    -- 0. Normalized rates (if provided)
    normalized_rates AS (
        SELECT
            key AS currency,
            (value::NUMERIC / base_rate) AS rate
        FROM jsonb_each(exchange_rates)
        WHERE exchange_rates IS NOT NULL
    ),

    -- 1. Latest payment satellite (amount, currency, timestamp)
    latest_payment_sat AS (
        SELECT DISTINCT ON (sp.payment_hk)
            sp.payment_hk,
            sp.amount,
            sp.currency,
            sp.payment_timestamp,
            sp.order_id
        FROM dwh.sat_payment sp
        ORDER BY sp.payment_hk, sp.load_datetime DESC
    ),

    -- 2. Latest order satellite (status)
    latest_order_sat AS (
        SELECT DISTINCT ON (so.order_hk)
            so.order_hk,
            so.status
        FROM dwh.sat_order so
        ORDER BY so.order_hk, so.load_datetime DESC
    ),

    -- 3. Join payments → orders (filter completed and non-null timestamp)
    payment_order AS (
        SELECT
            lpo.order_hk,
            lpo.payment_hk,
            lp.amount,
            lp.currency,
            lp.payment_timestamp
        FROM dwh.link_payment_order lpo
        JOIN latest_payment_sat lp ON lpo.payment_hk = lp.payment_hk
        JOIN latest_order_sat lo ON lpo.order_hk = lo.order_hk
        WHERE lo.status = 'completed'
          AND lp.payment_timestamp IS NOT NULL   -- <-- добавлено
    ),

    -- 4. Convert amounts to preferred currency
    converted AS (
        SELECT
            po.payment_timestamp,
            CASE
                WHEN po.currency = preferred_currency THEN po.amount
                WHEN exchange_rates IS NOT NULL
                     AND EXISTS (SELECT 1 FROM normalized_rates nr WHERE nr.currency = po.currency)
                THEN po.amount * (SELECT nr.rate FROM normalized_rates nr WHERE nr.currency = po.currency)
                ELSE NULL
            END AS converted_amount
        FROM payment_order po
    ),

    -- 5. Aggregate by month
    monthly AS (
        SELECT
            DATE_TRUNC('month', conv.payment_timestamp) AS month,
            SUM(conv.converted_amount) AS total_revenue
        FROM converted conv
        WHERE conv.converted_amount IS NOT NULL
        GROUP BY month
    )

    -- 6. Return results
    SELECT m.month::DATE, m.total_revenue
    FROM monthly m
    ORDER BY m.month;
END;
$$;