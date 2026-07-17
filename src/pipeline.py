import os
import glob
import pandas as pd
from database_utils import get_db_engine, init_staging_schema

# Explicit dictionary mapping raw CSV filenames to targeted staging tables
DATA_FILES_MAP = {
    'olist_customers_dataset.csv': 'stg_customers',
    'olist_orders_dataset.csv': 'stg_orders',
    'olist_order_items_dataset.csv': 'stg_order_items',
    'olist_order_payments_dataset.csv': 'stg_order_payments',
    'olist_order_reviews_dataset.csv': 'stg_order_reviews',
    'olist_products_dataset.csv': 'stg_products',
    'olist_sellers_dataset.csv': 'stg_sellers',
    'olist_geolocation_dataset.csv': 'stg_geolocation',
    'product_category_name_translation.csv': 'stg_category_translation'
}

def transform_and_clean(file_name, df):
    """
    Applies strict data quality and cleaning constraints established during EDA.
    """
    print(f"-> Transforming: {file_name}")
    
    # Rule 0: Strip whitespace from object/string types to guarantee clean joins later
    for col in df.select_dtypes(include='object').columns:
        df[col] = df[col].astype(str).str.strip()

    # Rule 1: Temporal/Datetime Casting
    if file_name == 'olist_orders_dataset.csv':
        date_cols = ['order_purchase_timestamp', 'order_approved_at', 
                     'order_delivered_carrier_date', 'order_delivered_customer_date', 
                     'order_estimated_delivery_date']
        for col in date_cols:
            df[col] = pd.to_datetime(df[col], errors='coerce')
            
    elif file_name == 'olist_order_items_dataset.csv':
        df['shipping_limit_date'] = pd.to_datetime(df['shipping_limit_date'], errors='coerce')
        
    elif file_name == 'olist_order_reviews_dataset.csv':
        date_cols = ['review_creation_date', 'review_answer_timestamp']
        for col in date_cols:
            df[col] = pd.to_datetime(df[col], errors='coerce')
        # Impute review text nulls safely to preserve rows
        df['review_comment_title'] = df['review_comment_title'].fillna('No Title')
        df['review_comment_message'] = df['review_comment_message'].fillna('No Message')

    # Rule 2: Zip Code String Padding (Fixing integer zero-truncation)
    elif file_name == 'olist_customers_dataset.csv':
        df['customer_zip_code_prefix'] = df['customer_zip_code_prefix'].astype(str).str.split('.').str[0].str.zfill(5)
        
    elif file_name == 'olist_sellers_dataset.csv':
        df['seller_zip_code_prefix'] = df['seller_zip_code_prefix'].astype(str).str.split('.').str[0].str.zfill(5)
        
    elif file_name == 'olist_geolocation_dataset.csv':
        # Correctly targeted 'geolocation_zip_code_prefix' identified in audit
        df['geolocation_zip_code_prefix'] = df['geolocation_zip_code_prefix'].astype(str).str.split('.').str[0].str.zfill(5)

    # Rule 3: Missing Product Metadata and Metric Imputation
    elif file_name == 'olist_products_dataset.csv':
        df['product_category_name'] = df['product_category_name'].replace('nan', 'unknown').fillna('unknown')
        
        # Fill physical attribute details with 0 to prevent mathematical database calculation errors
        metric_cols = ['product_name_lenght', 'product_description_lenght', 'product_photos_qty',
                       'product_weight_g', 'product_length_cm', 'product_height_cm', 'product_width_cm']
        for col in metric_cols:
            df[col] = pd.to_numeric(df[col], errors='coerce').fillna(0)

    return df

def execute_etl_pipeline():
    # Initialize connection and setup isolated staging schema
    engine = get_db_engine()
    init_staging_schema(engine)
    
    # Path configuration - Adjust this path string to point to the raw data directory
    raw_data_dir = "C:/Users/User/OneDrive/Personal Projects/Data Analytics/Supply chain bottlenecks/data/raw/"
    
    print("========== Starting Olist Data Ingestion Pipeline ==========")
    
    for file_name, table_name in DATA_FILES_MAP.items():
        file_path = os.path.join(raw_data_dir, file_name)
        
        if os.path.exists(file_path):
            print(f"\n[Extracting] Reading {file_name} from disk...")
            df_raw = pd.read_csv(file_path)
            
            # Apply data governance transformation rules
            df_clean = transform_and_clean(file_name, df_raw)
            
            # Load into PostgreSQL staging schema
            print(f"[Loading] Streaming {len(df_clean)} rows to staging.{table_name}...")
            
            df_clean.to_sql(
                name=table_name,
                con=engine,
                schema='staging',
                if_exists='replace',  # Rewrites staging table fresh each run
                index=False,
                chunksize=4000,       # Optimizes local machine memory allocation
                method='multi'        # Drastically increases chunk loading performance
            )
            print(f"Successfully populated staging.{table_name}")
        else:
            print(f"Error: File not found at target directory: {file_path}")
            
    print("\n=============================================================")
    print("ETL Pipeline Successfully Completed! All staging tables loaded.")
    print("=============================================================")

if __name__ == "__main__":
    execute_etl_pipeline()