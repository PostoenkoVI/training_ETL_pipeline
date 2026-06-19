import os
import sys
import argparse
import psycopg2
import pandas as pd
import time
import hashlib
import xml.etree.ElementTree as ET
import ijson
from datetime import datetime  # <-- added


class GeneratorReader:
    """A file-like object that reads from a generator of strings."""
    def __init__(self, generator):
        self.generator = generator
        self.buffer = ''

    def read(self, size=-1):
        if size < 0:
            return ''.join(self.generator)
        while len(self.buffer) < size:
            try:
                self.buffer += next(self.generator)
            except StopIteration:
                break
        chunk = self.buffer[:size]
        self.buffer = self.buffer[size:]
        return chunk


def q(v):
    if '|' in v or '"' in v or '\n' in v:
        return '"' + v.replace('"', '""') + '"'
    return v


def row_generator_json(file_path):
    with open(file_path, 'rb') as f:
        for obj in ijson.items(f, 'item'):
            order_id = str(obj.get('order_id', '')) or ''
            customer_id = str(obj.get('customer_id', '')) or ''
            product_id = str(obj.get('product_id', '')) or ''
            quantity = str(obj.get('quantity', '')) or ''
            unit_price = str(obj.get('unit_price', '')) or ''
            currency = str(obj.get('currency', '')) or ''
            order_timestamp = str(obj.get('order_timestamp', '')) or ''
            status = str(obj.get('status', '')) or ''

            raw = '||'.join([order_id, customer_id, product_id, quantity,
                             unit_price, currency, order_timestamp, status])
            row_hash = hashlib.md5(raw.encode('utf-8')).hexdigest()

            yield '|'.join(q(str(f)) for f in (order_id, customer_id, product_id,
                                           quantity, unit_price, currency,
                                           order_timestamp, status, row_hash)) + '\n'


def row_generator_xml(file_path):
    for event, elem in ET.iterparse(file_path, events=('end',)):
        if elem.tag == 'event':
            event_id = str(elem.findtext('event_id', '')) or ''
            customer_id = str(elem.findtext('customer_id', '')) or ''
            event_type = str(elem.findtext('event_type', '')) or ''
            event_timestamp = str(elem.findtext('event_timestamp', '')) or ''
            product_id = str(elem.findtext('product_id', '')) or ''

            raw = '||'.join([event_id, customer_id, event_type, event_timestamp, product_id])
            row_hash = hashlib.md5(raw.encode('utf-8')).hexdigest()

            yield '|'.join(q(str(f)) for f in (event_id, customer_id, event_type,
                                           event_timestamp, product_id, row_hash)) + '\n'
            elem.clear()


def wait_for_db():
    retries = 30
    while retries > 0:
        try:
            conn = psycopg2.connect(os.getenv('DATABASE_URL'))
            conn.close()
            print("Database is ready!")
            return True
        except psycopg2.OperationalError:
            print(f"Database not ready ({retries} retries)")
            time.sleep(2)
            retries -= 1
    raise Exception("Database not ready at all")


def validate_paths(paths):
    """Check that each path exists and is a file."""
    for name, p in paths.items():
        if not os.path.exists(p):
            raise FileNotFoundError(f"{name} file not found: {p}")
        if not os.path.isfile(p):
            raise IsADirectoryError(f"{name} path is not a file: {p}")


def get_top_products_query(by, n=5):
    func_map = {
        'views': 'get_top_products_by_views',
        'clicks': 'get_top_products_by_clicks',
        'purchases': 'get_top_products_by_purchases',
        'orders': 'get_top_products_by_completed_orders'
    }
    if by not in func_map:
        raise ValueError(f"by must be one of {list(func_map.keys())}")
    if n < 1:
        raise ValueError("n must be >= 1")
    func_name = func_map[by]
    return f"SELECT * FROM {func_name}({n});"


def get_top_customers_query(by, n=5):
    func_map = {
        'orders': "get_top_customers_by_orders",
        'purchases': "get_top_customers_by_purchases",
    }
    if by not in func_map:
        raise ValueError(f"by must be one of {list(func_map.keys())}")
    if n < 1:
        raise ValueError("n must be >= 1")
    func_name = func_map[by]
    return f"SELECT * FROM {func_name}({n});"


def main():
    parser = argparse.ArgumentParser(description='ETL pipeline for loading data into Data Vault.')
    parser.add_argument('--reset-db', action='store_true',
                        help='Drop and recreate schemas (raw, cleaned, dwh, logs)')
    parser.add_argument('--products-path', default='/app_data/products.xlsx',
                        help='Path to products Excel file')
    parser.add_argument('--customers-path', default='/app_data/customers.csv',
                        help='Path to customers CSV file')
    parser.add_argument('--payments-path', default='/app_data/payments.csv',
                        help='Path to payments CSV file')
    parser.add_argument('--orders-path', default='/app_data/orders.json',
                        help='Path to orders JSON file')
    parser.add_argument('--events-path', default='/app_data/events.xml',
                        help='Path to events XML file')
    parser.add_argument('--prefered_currency', default='RUB',
                        help='Prefered currency for analytics')
    parser.add_argument('--rub', default='1',
                        help='RUB exchange value')
    parser.add_argument('--usd', default='75',
                        help='USD exchange value')
    parser.add_argument('--eur', default='85',
                        help='EUR exchange value')
    parser.add_argument('--top_products_by', default='views',
                        help='Sort top products by number of views, clicks, purchases, orders')
    parser.add_argument('--top_customers_last_date_by', default='orders',
                        help='Sort top customers by number of orders or purchases')

    args = parser.parse_args()

    # Fixed timestamp for this run
    run_timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")

    # Validate all input files
    path_dict = {
        'products': args.products_path,
        'customers': args.customers_path,
        'payments': args.payments_path,
        'orders': args.orders_path,
        'events': args.events_path,
    }
    try:
        validate_paths(path_dict)
    except (FileNotFoundError, IsADirectoryError) as e:
        print(f"ERROR: {e}", file=sys.stderr)
        sys.exit(1)

    # Create output directory for result files
    OUTPUT_DIR = '/app_data/output'
    os.makedirs(OUTPUT_DIR, exist_ok=True)
    print(f"Output directory ensured: {OUTPUT_DIR}")

    # Convert products Excel to CSV (use same directory, replace extension)
    products_csv_path = args.products_path.replace('.xlsx', '.csv')
    try:
        pd.read_excel(args.products_path).to_csv(products_csv_path, index=False)
        print(f"Converted {args.products_path} to {products_csv_path}")
    except Exception as e:
        print(f"ERROR: Failed to convert Excel file: {e}", file=sys.stderr)
        sys.exit(1)

    # Wait for DB
    wait_for_db()

    DATABASE_URL = os.getenv("DATABASE_URL")
    if not DATABASE_URL:
        print("ERROR: DATABASE_URL environment variable not set", file=sys.stderr)
        sys.exit(1)

    conn = psycopg2.connect(DATABASE_URL)
    conn.autocommit = True

    with conn.cursor() as cur:
        # Reset schemas if requested
        if args.reset_db:
            print("Resetting database schemas...")
            cur.execute(open("/app/sql/reset_schemas.sql", "r").read())
            cur.execute(open("/app/sql/drop_public_functions.sql", "r").read())
        cur.execute(open("/app/sql/init_raw_cleaned_tables.sql", "r").read())

        # Load customers
        query = f"""
        COPY raw.customers (customer_id, full_name, email, phone, city, created_at)
        FROM '{args.customers_path}'
        WITH (FORMAT CSV, HEADER true, DELIMITER ',');
        """
        cur.execute(query)
        cur.execute(open("/app/sql/read_customers.sql", "r").read())

        # Load products (using the converted CSV)
        query = f"""
        COPY raw.products (product_id, product_name, category, price, currency, is_active)
        FROM '{products_csv_path}'
        WITH (FORMAT CSV, HEADER true, DELIMITER ',');
        """
        cur.execute(query)
        cur.execute(open("/app/sql/read_products.sql", "r").read())

        # Load payments
        query = f"""
        COPY raw.payments (payment_id, order_id, payment_method, amount, currency, payment_timestamp)
        FROM '{args.payments_path}'
        WITH (FORMAT CSV, HEADER true, DELIMITER '^');
        """
        cur.execute(query)
        cur.execute(open("/app/sql/read_payments.sql", "r").read())

        # Load orders (JSON)
        cur.execute(open("/app/sql/read_orders_init.sql", "r").read())
        copy_sql_json = """
        COPY raw.orders (order_id, customer_id, product_id, quantity,
                         unit_price, currency, order_timestamp, status, row_hash)
        FROM STDIN WITH (FORMAT CSV, DELIMITER '|', QUOTE '"')
        """
        reader = GeneratorReader(row_generator_json(args.orders_path))
        cur.copy_expert(copy_sql_json, reader, size=65536)
        cur.execute(open("/app/sql/read_orders_update.sql", "r").read())

        # Load events (XML)
        cur.execute(open("/app/sql/read_events_init.sql", "r").read())
        copy_sql_events = """
        COPY raw.events (event_id, customer_id, event_type, event_timestamp, product_id, row_hash)
        FROM STDIN WITH (FORMAT CSV, DELIMITER '|', QUOTE '"')
        """
        reader = GeneratorReader(row_generator_xml(args.events_path))
        cur.copy_expert(copy_sql_events, reader, size=65536)
        cur.execute(open("/app/sql/read_events_update.sql", "r").read())

        # Build Data Vault
        cur.execute(open("/app/sql/update_hubs.sql", "r").read())
        cur.execute(open("/app/sql/customer_sat.sql", "r").read())
        cur.execute(open("/app/sql/event_sat.sql", "r").read())
        cur.execute(open("/app/sql/order_sat.sql", "r").read())
        cur.execute(open("/app/sql/payment_sat.sql", "r").read())
        cur.execute(open("/app/sql/product_sat.sql", "r").read())
        cur.execute(open("/app/sql/link_event_customer_product.sql", "r").read())
        cur.execute(open("/app/sql/link_order_customer_product.sql", "r").read())
        cur.execute(open("/app/sql/link_payment_order.sql", "r").read())

    # Write verification queries results
    results_path = os.path.join(OUTPUT_DIR, f'structure_example_{run_timestamp}.txt')  # modified
    queries = [
        ("cleaned.customers", "SELECT COUNT(*) FROM cleaned.customers;"),
        ("cleaned.customers", "SELECT * FROM cleaned.customers LIMIT 5;"),
        ("cleaned.products", "SELECT COUNT(*) FROM cleaned.products;"),
        ("cleaned.products", "SELECT * FROM cleaned.products LIMIT 5;"),
        ("cleaned.payments", "SELECT COUNT(*) FROM cleaned.payments;"),
        ("cleaned.payments", "SELECT * FROM cleaned.payments LIMIT 5;"),
        ("cleaned.orders", "SELECT COUNT(*) FROM cleaned.orders;"),
        ("cleaned.orders", "SELECT * FROM cleaned.orders LIMIT 5;"),
        ("cleaned.events", "SELECT COUNT(*) FROM cleaned.events;"),
        ("cleaned.events", "SELECT * FROM cleaned.events LIMIT 5;"),
        ("logs.rejected_records", "SELECT COUNT(*) FROM logs.rejected_records;"),
        ("logs.rejected_records", "SELECT * FROM logs.rejected_records LIMIT 5;"),
        ("dwh.hub_customer", "SELECT COUNT(*) FROM dwh.hub_customer;"),
        ("dwh.hub_customer", "SELECT * FROM dwh.hub_customer LIMIT 5;"),
        ("dwh.hub_product", "SELECT COUNT(*) FROM dwh.hub_product;"),
        ("dwh.hub_product", "SELECT * FROM dwh.hub_product LIMIT 5;"),
        ("dwh.hub_event", "SELECT COUNT(*) FROM dwh.hub_event;"),
        ("dwh.hub_event", "SELECT * FROM dwh.hub_event LIMIT 5;"),
        ("dwh.hub_order", "SELECT COUNT(*) FROM dwh.hub_order;"),
        ("dwh.hub_order", "SELECT * FROM dwh.hub_order LIMIT 5;"),
        ("dwh.hub_payment", "SELECT COUNT(*) FROM dwh.hub_payment;"),
        ("dwh.hub_payment", "SELECT * FROM dwh.hub_payment LIMIT 5;"),
        ("dwh.sat_customer", "SELECT COUNT(*) FROM dwh.sat_customer;"),
        ("dwh.sat_customer", "SELECT * FROM dwh.sat_customer LIMIT 5;"),
        ("dwh.sat_product", "SELECT COUNT(*) FROM dwh.sat_product;"),
        ("dwh.sat_product", "SELECT * FROM dwh.sat_product LIMIT 5;"),
        ("dwh.sat_payment", "SELECT COUNT(*) FROM dwh.sat_payment;"),
        ("dwh.sat_payment", "SELECT * FROM dwh.sat_payment LIMIT 5;"),
        ("dwh.sat_order", "SELECT COUNT(*) FROM dwh.sat_order;"),
        ("dwh.sat_order", "SELECT * FROM dwh.sat_order LIMIT 5;"),
        ("dwh.sat_event", "SELECT COUNT(*) FROM dwh.sat_event;"),
        ("dwh.sat_event", "SELECT * FROM dwh.sat_event LIMIT 5;"),
        ("dwh.link_payment_order", "SELECT COUNT(*) FROM dwh.link_payment_order;"),
        ("dwh.link_payment_order", "SELECT * FROM dwh.link_payment_order LIMIT 5;"),
        ("dwh.link_event_customer_product", "SELECT COUNT(*) FROM dwh.link_event_customer_product;"),
        ("dwh.link_event_customer_product", "SELECT * FROM dwh.link_event_customer_product LIMIT 5;"),
        ("dwh.link_order_customer_product", "SELECT COUNT(*) FROM dwh.link_order_customer_product;"),
        ("dwh.link_order_customer_product", "SELECT * FROM dwh.link_order_customer_product LIMIT 5;"),
    ]

    with open(results_path, 'w') as f:
        with conn.cursor() as cur:
            for table_name, query in queries:
                try:
                    cur.execute(query)
                except Exception:
                    f.write(query + ' throws error\n')
                    continue
                if 'COUNT' in query:
                    count = cur.fetchone()[0]
                    f.write(f"{table_name}: {count}\n")
                else:
                    headers = [desc[0] for desc in cur.description]
                    rows = cur.fetchall()
                    f.write(",".join(headers) + "\n")
                    for row in rows:
                        f.write(",".join(str(val) if val is not None else "" for val in row) + "\n")
                    f.write("\n")
            cur.execute("DROP SCHEMA IF EXISTS raw CASCADE; DROP SCHEMA IF EXISTS cleaned CASCADE;")

    # Execute analytics functions and write separate results
    with conn.cursor() as cur:
        # Load analytics SQL (these should create functions if not already)
        cur.execute(open("/app/sql/analytics_top_most_lucrative.sql", "r").read())
        cur.execute(open("/app/sql/analytics_popular_products.sql", "r").read())
        cur.execute(open("/app/sql/analytics_mouthly_revenue.sql", "r").read())
        cur.execute(open("/app/sql/analytics_last_actions_of_top_customers.sql", "r").read())
        cur.execute(open("/app/sql/analytics_customers_without_orders.sql", "r").read())

        analytics_queries = [
            # ("get_top_customers_default", 'get_top_customers', "SELECT * FROM get_top_customers('EUR');"),
            # ("get_top_customers_with_rates", 'get_top_customers', "SELECT * FROM get_top_customers('EUR', '{\"USD\": 0.85, \"RUB\": 0.011, \"EUR\": 1.0}'::JSONB, 5);"),
            ("top_most_lucrative", 
             "SELECT * FROM get_top_customers('{}', '{{\"EUR\": {}, \"RUB\": {}, \"USD\": {}}}'::JSONB, 10);".format( args.prefered_currency, 
                                                                                                                    args.rub, 
                                                                                                                    args.usd, 
                                                                                                                    args.eur)),
            # ("get_monthly_revenue_default", 'get_monthly_revenue', "SELECT * FROM get_monthly_revenue('EUR');"),
            ("mouthly_revenue", 
             "SELECT * FROM get_monthly_revenue('{}', '{{\"EUR\": {}, \"RUB\": {}, \"USD\": {}}}'::JSONB);".format(args.prefered_currency, 
                                                                                                                 args.rub, 
                                                                                                                 args.usd, 
                                                                                                                 args.eur)),
            ("top_products", get_top_products_query(args.top_products_by, 10)),
            ("top_customers_last_date", get_top_customers_query(args.top_customers_last_date_by, 5)),
            # ("get_top_customers_by_orders_10", 'get_top_customers_by_orders', "SELECT * FROM get_top_customers_by_orders(10);"),
            ("customers_without_orders", "SELECT * FROM get_customers_without_orders();"),
        ]

        # 3. Execute each query and write CSV
        for case_name, query in analytics_queries:
            csv_path = os.path.join(OUTPUT_DIR, f"{case_name}_{run_timestamp}.csv")  # modified
            try:
                cur.execute(query)
                with open(csv_path, 'w', newline='') as csvfile:
                    headers = [desc[0] for desc in cur.description]
                    rows = cur.fetchall()
                    csvfile.write(",".join(headers) + "\n")
                    for row in rows:
                        csvfile.write(",".join(str(val) if val is not None else "" for val in row) + "\n")

                print(f"Analytics written: {csv_path} ({len(rows)} rows)")

            except Exception as e:
                # Log error to a separate file
                error_path = os.path.join(OUTPUT_DIR, f"{case_name}_{run_timestamp}.error")  # modified
                with open(error_path, 'w') as ef:
                    ef.write(f"Query: {query}\n")
                    ef.write(f"Error: {str(e)}\n")
                print(f"Analytics failed: {case_name} : {e}", file=sys.stderr)

        conn.close()
        print(f"\nResults written to {OUTPUT_DIR}")


if __name__ == "__main__":
    main()