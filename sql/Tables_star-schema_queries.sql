USE OListEcommerceDB;
GO

CREATE TABLE customers_clean (
    customer_id VARCHAR(50) PRIMARY KEY,
    customer_unique_id VARCHAR(50),
    customer_zip_code_prefix INT,
    customer_city VARCHAR(100),
    customer_state VARCHAR(5)
);

CREATE TABLE sellers_clean (
    seller_id VARCHAR(50) PRIMARY KEY,
    seller_zip_code_prefix INT,
    seller_city VARCHAR(100),
    seller_state VARCHAR(5)
);

CREATE TABLE category_translation_clean (
    product_category_name VARCHAR(100) PRIMARY KEY,
    product_category_name_english VARCHAR(100)
);

CREATE TABLE products_clean (
    product_id VARCHAR(50) PRIMARY KEY,
    product_category_name VARCHAR(100),
    product_name_lenght FLOAT,
    product_description_lenght FLOAT,
    product_photos_qty FLOAT,
    product_weight_g FLOAT,
    product_length_cm FLOAT,
    product_height_cm FLOAT,
    product_width_cm FLOAT,
    zero_weight_flag BIT,
    missing_category_flag BIT
);

CREATE TABLE orders_clean (
    order_id VARCHAR(50) PRIMARY KEY,
    customer_id VARCHAR(50),
    order_status VARCHAR(20),
    order_purchase_timestamp DATETIME,
    order_approved_at DATETIME,
    order_delivered_carrier_date DATETIME,
    order_delivered_customer_date DATETIME,
    order_estimated_delivery_date DATETIME,
    delivery_date_missing_flag BIT,
    approval_date_suspicious_flag BIT,
    delivery_time_days FLOAT,
    extreme_delivery_delay_flag BIT
);

CREATE TABLE order_items_clean (
    order_id VARCHAR(50),
    order_item_id INT,
    product_id VARCHAR(50),
    seller_id VARCHAR(50),
    shipping_limit_date DATETIME,
    price FLOAT,
    freight_value FLOAT
);

CREATE TABLE order_payments_clean (
    order_id VARCHAR(50),
    payment_sequential INT,
    payment_type VARCHAR(20),
    payment_installments INT,
    payment_value FLOAT
);

CREATE TABLE order_reviews_clean (
    review_id VARCHAR(50),
    order_id VARCHAR(50),
    review_score INT,
    review_comment_title NVARCHAR(200),
    review_comment_message NVARCHAR(MAX),
    review_creation_date DATETIME,
    review_answer_timestamp DATETIME,
    shared_review_id_flag BIT
);
GO


USE OListEcommerceDB;
GO

SELECT TOP 5 * FROM dbo.category_translation_clean;
SELECT TOP 5 * FROM dbo.customers_clean;
SELECT TOP 5 * FROM dbo.order_items_clean;
SELECT TOP 5 * FROM dbo.order_payments_clean;
SELECT TOP 5 * FROM dbo.order_reviews_clean;
SELECT TOP 5 * FROM dbo.orders_clean;
SELECT TOP 5 * FROM dbo.products_clean;
SELECT TOP 5 * FROM dbo.sellers_clean;

USE OListEcommerceDB;
GO

SELECT
    TABLE_NAME,
    COLUMN_NAME,
    DATA_TYPE,
    CHARACTER_MAXIMUM_LENGTH
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_SCHEMA = 'dbo'
ORDER BY TABLE_NAME, ORDINAL_POSITION;

/* ============================================================
   OLIST E-COMMERCE PROJECT — STAR SCHEMA (Step: SQL Modeling)
   Database: OListEcommerceDB
   ============================================================
   Design notes:
   - fact_order_items = line-item grain (revenue, product, seller analysis)
   - fact_orders      = order grain (delivery, payments, review score)
     Payments and reviews are aggregated to order level because an
     order can have multiple payment rows (installments) and,
     occasionally, a shared review_id across orders.
   - dim_date is a physical TABLE (not a view) because SQL Server
     doesn't allow the MAXRECURSION hint inside a view definition,
     which the recursive CTE needs to generate the date range.
   ============================================================ */


/* ---------------------------------------------------------
   DIMENSION VIEWS
   --------------------------------------------------------- */

USE OListEcommerceDB;
GO

CREATE OR ALTER VIEW dim_customers AS
SELECT
    customer_id,
    customer_unique_id,
    customer_zip_code_prefix,
    customer_city,
    customer_state
FROM customers_clean;
GO

CREATE OR ALTER VIEW dim_sellers AS
SELECT
    seller_id,
    seller_zip_code_prefix,
    seller_city,
    seller_state
FROM sellers_clean;
GO

CREATE OR ALTER VIEW dim_products AS
SELECT
    p.product_id,
    p.product_category_name,
    COALESCE(c.product_category_name_english, 'unknown') AS product_category_english,
    p.product_weight_g,
    p.product_length_cm,
    p.product_height_cm,
    p.product_width_cm,
    p.zero_weight_flag,
    p.missing_category_flag
FROM products_clean p
LEFT JOIN category_translation_clean c
    ON p.product_category_name = c.product_category_name;
GO


/* ---------------------------------------------------------
   DIM_DATE — physical table, built once via recursive CTE.
   Range covers the Olist dataset (2016–2018) with a buffer.
   Re-run this block once; it doesn't need to be a view.
   --------------------------------------------------------- */

IF OBJECT_ID('dim_date', 'U') IS NOT NULL
    DROP TABLE dim_date;
GO

WITH DateRange AS (
    SELECT CAST('2016-01-01' AS DATE) AS date_key
    UNION ALL
    SELECT DATEADD(DAY, 1, date_key)
    FROM DateRange
    WHERE date_key < '2018-12-31'
)
SELECT
    date_key,
    YEAR(date_key)                         AS [year],
    MONTH(date_key)                        AS [month],
    DATENAME(MONTH, date_key)              AS month_name,
    DAY(date_key)                          AS [day],
    DATEPART(QUARTER, date_key)            AS [quarter],
    DATENAME(WEEKDAY, date_key)            AS weekday_name,
    CASE WHEN DATEPART(WEEKDAY, date_key) IN (1, 7)
         THEN 1 ELSE 0 END                 AS is_weekend
INTO dim_date
FROM DateRange
OPTION (MAXRECURSION 1500);
GO


/* ---------------------------------------------------------
   FACT VIEWS
   --------------------------------------------------------- */

-- Grain: one row per order item (order_id + order_item_id)
CREATE OR ALTER VIEW fact_order_items AS
SELECT
    oi.order_id,
    oi.order_item_id,
    oi.product_id,
    oi.seller_id,
    o.customer_id,
    CAST(o.order_purchase_timestamp AS DATE) AS order_date_key,
    oi.price,
    oi.freight_value,
    oi.price + oi.freight_value AS item_total,
    oi.shipping_limit_date
FROM order_items_clean oi
INNER JOIN orders_clean o
    ON oi.order_id = o.order_id;
GO

-- Grain: one row per order (payments and reviews aggregated up)
CREATE OR ALTER VIEW fact_orders AS
SELECT
    o.order_id,
    o.customer_id,
    CAST(o.order_purchase_timestamp AS DATE) AS order_date_key,
    o.order_status,
    o.order_purchase_timestamp,
    o.order_approved_at,
    o.order_delivered_carrier_date,
    o.order_delivered_customer_date,
    o.order_estimated_delivery_date,
    o.delivery_time_days,
    o.delivery_date_missing_flag,
    o.approval_date_suspicious_flag,
    o.extreme_delivery_delay_flag,
    pay.total_payment_value,
    pay.payment_count,
    rev.avg_review_score,
    rev.review_count
FROM orders_clean o
LEFT JOIN (
    SELECT
        order_id,
        SUM(payment_value) AS total_payment_value,
        COUNT(*)           AS payment_count
    FROM order_payments_clean
    GROUP BY order_id
) pay ON o.order_id = pay.order_id
LEFT JOIN (
    SELECT
        order_id,
        AVG(CAST(review_score AS FLOAT)) AS avg_review_score,
        COUNT(*)                         AS review_count
    FROM order_reviews_clean
    GROUP BY order_id
) rev ON o.order_id = rev.order_id;
GO


SELECT TABLE_NAME, TABLE_TYPE
FROM INFORMATION_SCHEMA.TABLES
WHERE TABLE_NAME IN ('dim_customers', 'dim_sellers', 'dim_products', 'dim_date', 'fact_order_items', 'fact_orders');




USE OListEcommerceDB;
GO

/* ============================================================
   OLIST E-COMMERCE PROJECT — ANALYTICAL QUERIES
   Run against the star schema views (dim_*, fact_*)
   ============================================================ */


/* ---------------------------------------------------------
   1. REVENUE BY PRODUCT CATEGORY
   Which categories drive the most revenue?
   --------------------------------------------------------- */
SELECT
    dp.product_category_english,
    COUNT(DISTINCT foi.order_id) AS order_count,
    SUM(foi.item_total)          AS total_revenue
FROM fact_order_items foi
JOIN dim_products dp
    ON foi.product_id = dp.product_id
GROUP BY dp.product_category_english
ORDER BY total_revenue DESC;


/* ---------------------------------------------------------
   2. TOP 10 SELLERS BY REVENUE
   --------------------------------------------------------- */
SELECT
    ds.seller_id,
    ds.seller_state,
    COUNT(DISTINCT foi.order_id) AS order_count,
    SUM(foi.item_total)          AS total_revenue
FROM fact_order_items foi
JOIN dim_sellers ds
    ON foi.seller_id = ds.seller_id
GROUP BY ds.seller_id, ds.seller_state
ORDER BY total_revenue DESC
OFFSET 0 ROWS FETCH NEXT 10 ROWS ONLY;


/* ---------------------------------------------------------
   3. DELIVERY PERFORMANCE BY CUSTOMER STATE
   Avg delivery time + extreme delay rate per state
   --------------------------------------------------------- */
SELECT
    dc.customer_state,
    COUNT(*)                                   AS total_orders,
    AVG(fo.delivery_time_days)                 AS avg_delivery_days,
    SUM(CAST(fo.extreme_delivery_delay_flag AS INT)) AS extreme_delay_orders,
    CAST(SUM(CAST(fo.extreme_delivery_delay_flag AS INT)) AS FLOAT)
        / COUNT(*)                             AS extreme_delay_rate
FROM fact_orders fo
JOIN dim_customers dc
    ON fo.customer_id = dc.customer_id
WHERE fo.order_status = 'delivered'
GROUP BY dc.customer_state
ORDER BY avg_delivery_days DESC;


/* ---------------------------------------------------------
   4. MONTHLY REVENUE TREND
   Feeds the YTD / YoY DAX measures later
   --------------------------------------------------------- */
SELECT
    dd.[year],
    dd.[month],
    dd.month_name,
    SUM(foi.item_total)          AS total_revenue,
    COUNT(DISTINCT foi.order_id) AS order_count
FROM fact_order_items foi
JOIN dim_date dd
    ON foi.order_date_key = dd.date_key
GROUP BY dd.[year], dd.[month], dd.month_name
ORDER BY dd.[year], dd.[month];


/* ---------------------------------------------------------
   5. PAYMENT TYPE BREAKDOWN
   --------------------------------------------------------- */
SELECT
    payment_type,
    COUNT(*)                    AS payment_rows,
    COUNT(DISTINCT order_id)    AS distinct_orders,
    SUM(payment_value)          AS total_value,
    AVG(payment_installments)   AS avg_installments
FROM order_payments_clean
GROUP BY payment_type
ORDER BY total_value DESC;


/* ---------------------------------------------------------
   6. REVIEW SCORE VS. DELIVERY DELAY
   Does slower delivery correlate with lower review scores?
   --------------------------------------------------------- */
SELECT
    CASE
        WHEN fo.delivery_time_days IS NULL THEN 'Unknown / Not Delivered'
        WHEN fo.delivery_time_days <= 7   THEN '0-7 days'
        WHEN fo.delivery_time_days <= 14  THEN '8-14 days'
        WHEN fo.delivery_time_days <= 30  THEN '15-30 days'
        ELSE '30+ days'
    END AS delivery_bucket,
    COUNT(*)                    AS order_count,
    AVG(fo.avg_review_score)    AS avg_review_score
FROM fact_orders fo
GROUP BY
    CASE
        WHEN fo.delivery_time_days IS NULL THEN 'Unknown / Not Delivered'
        WHEN fo.delivery_time_days <= 7   THEN '0-7 days'
        WHEN fo.delivery_time_days <= 14  THEN '8-14 days'
        WHEN fo.delivery_time_days <= 30  THEN '15-30 days'
        ELSE '30+ days'
    END
ORDER BY MIN(fo.delivery_time_days);


/* ---------------------------------------------------------
   BONUS: REPEAT CUSTOMER RATE
   Quick SQL check ahead of the Power BI DAX measure
   --------------------------------------------------------- */
SELECT
    COUNT(DISTINCT customer_unique_id) AS total_unique_customers,
    SUM(CASE WHEN order_count > 1 THEN 1 ELSE 0 END) AS repeat_customers,
    CAST(SUM(CASE WHEN order_count > 1 THEN 1 ELSE 0 END) AS FLOAT)
        / COUNT(DISTINCT customer_unique_id) AS repeat_customer_rate
FROM (
    SELECT
        dc.customer_unique_id,
        COUNT(fo.order_id) AS order_count
    FROM fact_orders fo
    JOIN dim_customers dc
        ON fo.customer_id = dc.customer_id
    GROUP BY dc.customer_unique_id
) t;