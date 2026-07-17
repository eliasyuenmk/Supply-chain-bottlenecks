-- DDL Script: Dimension Tables
-- 1. Create analytics.dim_customers
DROP TABLE IF EXISTS analytics.dim_customers CASCADE;
CREATE TABLE analytics.dim_customers (
	customer_unique_id VARCHAR(50) PRIMARY KEY,
	customer_city VARCHAR(50),
	customer_state VARCHAR(10)
);

-- 2. Create analytics.dim_products
DROP TABLE IF EXISTS analytics.dim_products CASCADE;
CREATE TABLE analytics.dim_products (
	product_id VARCHAR(50) PRIMARY KEY,
	product_category_name_english VARCHAR(50),
	product_weight_g NUMERIC(10, 2),
	product_volume_cm3 NUMERIC(10, 2)
);

-- 3. Create analytics.dim_sellers
DROP TABLE IF EXISTS analytics.dim_sellers CASCADE;
CREATE TABLE analytics.dim_sellers (
	seller_id VARCHAR(50) PRIMARY KEY,
	seller_city VARCHAR(50),
	seller_state VARCHAR(50)	
);

-- 4. Create analytics.dim_geography
DROP TABLE IF EXISTS analytics.dim_geography CASCADE;
CREATE TABLE analytics.dim_geography (
	zip_code_prefix VARCHAR(10) PRIMARY KEY,
	latitude DOUBLE PRECISION,
	longitude DOUBLE PRECISION,
	state VARCHAR(10),
	city VARCHAR(50)
);

-- 5. Create analytics.dim_payments
DROP TABLE IF EXISTS analytics.dim_payments CASCADE;
CREATE TABLE analytics.dim_payments (
	order_id VARCHAR(50) NOT NULL,
	payment_sequential INT NOT NULL,
	payment_type VARCHAR(50),
	payment_installments INT,
	payment_value NUMERIC (10,2),
	PRIMARY KEY (order_id, payment_sequential)
);

-- 6. Create analytics.dim_date
DROP TABLE IF EXISTS analytics.dim_date CASCADE;
CREATE TABLE analytics.dim_date (
	date_key INT PRIMARY KEY, -- Format: YYYYMMDD
	date DATE NOT NULL,
	year INT NOT NULL,
	quarter VARCHAR(10)  NOT NULL,
	month_name VARCHAR(20)  NOT NULL,
	month_number INT  NOT NULL,
	day_of_week VARCHAR(20)  NOT NULL,
	is_weekend INT NOT NULL -- 1 if weekend, 0 if weekday
);

-- Indexing Strategy to optimize future Power BI Dashboard rendering speeds
CREATE INDEX idx_dim_customers_state ON analytics.dim_customers(customer_state);
CREATE INDEX idx_dim_sellers_state ON analytics.dim_sellers(seller_state);
CREATE INDEX idx_dim_products_cat ON analytics.dim_products(product_category_name_english);


-- DML script: populate analytics.dim_customers from staging.stg_customers
TRUNCATE TABLE analytics.dim_customers CASCADE;
INSERT INTO analytics.dim_customers (customer_unique_id, customer_city, customer_state)
SELECT
	DISTINCT ON (customer_unique_id)
	customer_unique_id,
	customer_city,
	customer_state
FROM staging.stg_customers
ORDER BY customer_unique_id;

-- DML script: populate analytics.dim_products from staging.stg_products & staging.stg_category_translation
TRUNCATE TABLE analytics.dim_products CASCADE;
INSERT INTO analytics.dim_products (product_id, product_category_name_english, product_weight_g,product_volume_cm3)
SELECT
	p.product_id,
	COALESCE(ct.product_category_name_english, 'unknown') AS product_category_name_english,
	p.product_weight_g,
	(p.product_length_cm * p.product_height_cm * p.product_width_cm) AS product_volume_cm3
FROM staging.stg_products p
LEFT JOIN staging.stg_category_translation ct
ON p.product_category_name = ct.product_category_name;

-- DML script: populate analytics.dim_sellers from staging.stg_sellers
TRUNCATE TABLE analytics.dim_sellers CASCADE;
INSERT INTO analytics.dim_sellers (seller_id, seller_city, seller_state)
SELECT
	DISTINCT seller_id, 
	seller_city,
	seller_state
FROM staging.stg_sellers;

-- DML script: populate analytics.dim_geography from staging.stg_geolocation
TRUNCATE TABLE analytics.dim_geography CASCADE;
INSERT INTO analytics.dim_geography (zip_code_prefix, latitude, longitude, state, city)
SELECT
	geolocation_zip_code_prefix AS zip_code_prefix,
	AVG(geolocation_lat) AS latitude,
	AVG(geolocation_lng) AS longitude,
	MAX(geolocation_state) AS state, -- To maintain a strict 1:1 zip relationship
	MAX(geolocation_city) AS city
FROM staging.stg_geolocation
GROUP BY geolocation_zip_code_prefix;

-- DML script: populate analytics.dim_payments from staging.stg_order_payments
TRUNCATE TABLE analytics.dim_payments CASCADE;
INSERT INTO analytics.dim_payments (order_id, payment_sequential, payment_type, payment_installments, payment_value)
SELECT
	order_id,
	payment_sequential,
	payment_type,
	payment_installments,
	payment_value
FROM staging.stg_order_payments;

-- DML script: populate analytics.dim_date from SQL sequence
TRUNCATE TABLE analytics.dim_date CASCADE;
INSERT INTO analytics.dim_date (date_key, date, year, quarter, month_name, month_number, day_of_week, is_weekend)
SELECT 
    CAST(TO_CHAR(datum, 'YYYYMMDD') AS INT) AS date_key,
    datum AS date,
    EXTRACT(YEAR FROM datum) AS year,
    'Q' || EXTRACT(QUARTER FROM datum) AS quarter,
    TO_CHAR(datum, 'Month') AS month_name,
    EXTRACT(MONTH FROM datum) AS month_number,
    TO_CHAR(datum, 'Day') AS day_of_week,
    CASE 
        WHEN EXTRACT(ISODOW FROM datum) IN (6, 7) THEN 1 
        ELSE 0 
    END AS is_weekend
FROM (
    -- Automatically generate every sequential single day between the earliest and furthest transaction date
    SELECT generate_series(
        '2016-01-01'::DATE, 
        '2018-12-31'::DATE, 
        '1 day'::INTERVAL
    )::DATE AS datum
) calendar_stream;

-- View 1: Executive Logistics & Revenue
CREATE OR REPLACE VIEW analytics.vw_executive_overview AS
SELECT 
    f.order_id,
    f.clean_order_status,
    f.purchase_date_key,
    d.date,
    d.year,
    d.quarter,
    d.month_name,
    c.customer_state,
    c.customer_city,
    f.price,
    f.freight_value,
    f.total_item_value,
    f.actual_delivery_days,
    f.is_late
FROM analytics.fact_order_items f
INNER JOIN analytics.dim_date d ON f.purchase_date_key = d.date_key
INNER JOIN analytics.dim_customers c ON f.customer_unique_id = c.customer_unique_id;

-- View 2: Logistics Bottleneck Analysis
CREATE OR REPLACE VIEW analytics.vw_bottleneck_analysis AS
SELECT 
    f.order_id,
    f.order_item_id,
    p.product_category_name_english,
    p.product_weight_g,
    p.product_volume_cm3,
    s.seller_state,
    f.seller_processing_days,
    f.carrier_transit_days,
    f.actual_delivery_days,
    f.delivery_variance_days,
    f.is_late
FROM analytics.fact_order_items f
INNER JOIN analytics.dim_products p ON f.product_id = p.product_id
INNER JOIN analytics.dim_sellers s ON f.seller_id = s.seller_id;

-- View 3: Review & Risk Analysis Bridge
CREATE OR REPLACE VIEW analytics.vw_customer_sentiment AS
SELECT 
    f.order_id,
    f.clean_order_status,
    f.actual_delivery_days,
    f.delivery_variance_days,
    f.is_late,
    s.seller_id,
    s.seller_state,
    p.product_category_name_english,
    r.review_score,
    f.total_item_value
FROM analytics.fact_order_items f
INNER JOIN staging.stg_order_reviews r ON f.order_id = r.order_id
INNER JOIN analytics.dim_sellers s ON f.seller_id = s.seller_id
INNER JOIN analytics.dim_products p ON f.product_id = p.product_id;