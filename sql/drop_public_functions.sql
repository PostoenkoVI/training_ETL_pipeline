DO $$
DECLARE
    r RECORD;
BEGIN
    FOR r IN (
        SELECT 
            p.proname AS function_name,
            pg_get_function_identity_arguments(p.oid) AS args
        FROM pg_proc p
        JOIN pg_namespace n ON p.pronamespace = n.oid
        WHERE n.nspname = 'public'
          AND p.prokind = 'f'
    ) LOOP
        EXECUTE format('DROP FUNCTION IF EXISTS public.%I(%s) CASCADE;', 
                       r.function_name, r.args);
    END LOOP;
END;
$$;