-- DDL Script: Create analytics.fact_order_items
DROP TABLE IF EXISTS analytics.fact_order_items CASCADE;

CREATE TABLE analytics.fact_order_items (
    -- Primary Composite Key Structure (For tracking individual items per order)
    order_id VARCHAR(50) NOT NULL,
    order_item_id INT NOT NULL,
    
    -- Foreign Keys (Dimension Linkages)
    customer_unique_id VARCHAR(50) NOT NULL,
    product_id VARCHAR(50) NOT NULL,
    seller_id VARCHAR(50) NOT NULL,
    customer_zip_code_prefix VARCHAR(10) NOT NULL,
    purchase_date_key INT NOT NULL,  -- Format: YYYYMMDD
    
    -- Degenerate Operational Dimensions
    order_status VARCHAR(30) NOT NULL,
    clean_order_status VARCHAR(40) NOT NULL, -- Custom flag tracking the data anomalies
    
    -- Transactional Timestamps
    order_purchase_timestamp TIMESTAMP,
    order_approved_at TIMESTAMP,
    order_delivered_carrier_date TIMESTAMP,
    order_delivered_customer_date TIMESTAMP,
    order_estimated_delivery_date TIMESTAMP,
    shipping_limit_date TIMESTAMP,
    
    -- Base Numerical Financial Measures
    price NUMERIC(10, 2) NOT NULL,
    freight_value NUMERIC(10, 2) NOT NULL,
    total_item_value NUMERIC(10, 2) NOT NULL,
    
    -- Calculated Logistics Durations (Stored as Integers/Days)
    seller_processing_days INT,
    carrier_transit_days INT,
    actual_delivery_days INT,
    delivery_variance_days INT,
    is_late INT NOT NULL,  -- 1 if late, 0 if on-time/early
    
    -- Set Composite Primary Key Constraints
    PRIMARY KEY (order_id, order_item_id)
);

-- Indexing Strategy to optimize future Power BI Dashboard rendering speeds
CREATE INDEX idx_fact_order_items_product ON analytics.fact_order_items(product_id);
CREATE INDEX idx_fact_order_items_seller ON analytics.fact_order_items(seller_id);
CREATE INDEX idx_fact_order_items_customer ON analytics.fact_order_items(customer_unique_id);
CREATE INDEX idx_fact_order_items_date ON analytics.fact_order_items(purchase_date_key);

-- Add FK constraints
ALTER TABLE analytics.fact_order_items
    ADD CONSTRAINT fk_fact_customer FOREIGN KEY (customer_unique_id) REFERENCES analytics.dim_customers(customer_unique_id),
    ADD CONSTRAINT fk_fact_product FOREIGN KEY (product_id) REFERENCES analytics.dim_products(product_id),
    ADD CONSTRAINT fk_fact_seller FOREIGN KEY (seller_id) REFERENCES analytics.dim_sellers(seller_id),
    ADD CONSTRAINT fk_fact_date FOREIGN KEY (purchase_date_key) REFERENCES analytics.dim_date(date_key);

-- DML Script: Populate analytics.fact_order_items from Staging Tier
TRUNCATE TABLE analytics.fact_order_items CASCADE;

INSERT INTO analytics.fact_order_items
WITH transformed_logistics AS (
    SELECT 
        oi.order_id,
        oi.order_item_id,
        c.customer_unique_id,
        oi.product_id,
        oi.seller_id,
        c.customer_zip_code_prefix,
        
        -- Create a unified integer date key (YYYYMMDD) for your Date Dimension linkage
        CAST(TO_CHAR(o.order_purchase_timestamp, 'YYYYMMDD') AS INT) AS purchase_date_key,
        
        o.order_status,
        -- Operational Anomaly Flagging (Resolving the EDA findings)
        CASE 
            WHEN o.order_status = 'delivered' AND o.order_delivered_customer_date IS NULL 
                THEN 'Status Mismatch (Anomalous Delivery)'
            WHEN o.order_status = 'canceled' AND o.order_delivered_customer_date IS NOT NULL 
                THEN 'Canceled but Delivered (Anomalous Flow)'
            ELSE o.order_status 
        END AS clean_order_status,
        
        o.order_purchase_timestamp,
        o.order_approved_at,
        o.order_delivered_carrier_date,
        o.order_delivered_customer_date,
        o.order_estimated_delivery_date,
        oi.shipping_limit_date,
        
        oi.price,
        oi.freight_value,
        (oi.price + oi.freight_value) AS total_item_value,
        
        -- Safe Duration Calculations using AGE functions 
        -- Wrapped in conditional logic to bypass anomalous or missing timestamp fields
        CASE 
            WHEN o.order_approved_at IS NOT NULL AND o.order_delivered_carrier_date IS NOT NULL 
                 AND o.order_delivered_carrier_date >= o.order_approved_at
            THEN EXTRACT(DAY FROM (o.order_delivered_carrier_date - o.order_approved_at))
            ELSE NULL 
        END AS seller_processing_days,
        
        CASE 
            WHEN o.order_delivered_carrier_date IS NOT NULL AND o.order_delivered_customer_date IS NOT NULL
                 AND o.order_delivered_customer_date >= o.order_delivered_carrier_date
            THEN EXTRACT(DAY FROM (o.order_delivered_customer_date - o.order_delivered_carrier_date))
            ELSE NULL 
        END AS carrier_transit_days,
        
        -- Defensively excluding the 8 un-timestamped delivered records to prevent calculations
        CASE 
            WHEN o.order_status = 'delivered' AND o.order_delivered_customer_date IS NOT NULL 
            THEN EXTRACT(DAY FROM (o.order_delivered_customer_date - o.order_purchase_timestamp))
            ELSE NULL 
        END AS actual_delivery_days,
        
        CASE 
            WHEN o.order_delivered_customer_date IS NOT NULL 
            THEN EXTRACT(DAY FROM (o.order_delivered_customer_date - o.order_estimated_delivery_date))
            ELSE NULL 
        END AS delivery_variance_days

    FROM staging.stg_order_items oi
    INNER JOIN staging.stg_orders o ON oi.order_id = o.order_id
    INNER JOIN staging.stg_customers c ON o.customer_id = c.customer_id
)
SELECT 
    *,
    -- Dynamic Binary Classification Metric: Is Late Flag?
    -- Returns 1 if actual destination arrival breached the promised timeline, else 0
    CASE 
        WHEN delivery_variance_days > 0 THEN 1 
        ELSE 0 
    END AS is_late
FROM transformed_logistics;