# SQL Data Analytics Script Documentation
This repository contains a SQL script (SQLQuery3.sql) designed for advanced data analytics on sales and product datasets. It leverages complex queries, Window functions, Common Table Expressions (CTEs), and subqueries to extract valuable business insights and generate comprehensive reports.

# Table of Contents

1.  Introduction

2.  Dataset Assumptions

3.  Script Overview

4.  Detailed Query Analysis

- Total Sales Trend Over the Year (Monthly)

- Total Sales and Running Totals (Monthly)

- Yearly Product Performance Analysis

- Category Contribution to Overall Sales

- Product Segmentation by Cost Ranges

- Customer Segmentation by Spending Behaviour

- Customer Report View (dbo.customer_report)

- Product Report View (dbo.product_report)

5.  How to Use

6.  Technologies Used

# 1. Introduction
This SQL script provides a robust framework for analysing sales and product data. It addresses several key business questions, offering insights into sales trends, product performance, customer behavior, and category contributions. The script is structured to be clear, efficient, and easily understandable, making use of modern SQL features to achieve its analytical goals. It empowers data-driven decision-making by providing actionable insights into various business facets.

# 2. Dataset
This dataset file is in the file section, which includes the following tables with a gold schema:

- gold.fact_sales

- gold.dim_products

- gold.dim_customers

# 3. Script Overview
The script is organised into several distinct sections, each addressing a specific analytical objective:

- Sales Trend Analysis: Queries to understand monthly sales performance and running totals.

- Product Performance: Analysis of product sales year-over-year and against average performance.

- Categorical Analysis: Examination of sales contribution by product categories.

- Segmentation: Grouping products by cost and customers by spending behaviour.

- Reporting Views: Creation of (customer_report) and (product_report) views for comprehensive, aggregated insights, which were also used for dashboard creation using PowerBI.

# 4. Detailed Query Analysis
Each section below provides a detailed explanation of the SQL query, its purpose, and the logic behind it.

## Total Sales Trend Over the Year (Monthly)
This query calculates the total sales, total customers, and total quantity sold aggregated by month.

```sql
SELECT
    DATETRUNC(MONTH, order_date) AS order_year,
    SUM(sales_amount) AS total_sales,
    COUNT(DISTINCT customer_key) AS total_customers,
    SUM(quantity) AS total_quantity
FROM [gold.fact_sales]
WHERE order_date IS NOT NULL
GROUP BY DATETRUNC(MONTH, order_date)
ORDER BY 1
```
- Purpose: To identify overall sales trends, customer engagement, and product movement on a monthly basis.

## Total Sales and Running Totals (Monthly)
This query calculates the total sales and average price per month, along with their respective running totals.

```sql
SELECT
    order_date,
    total_sales,
    SUM(total_sales) OVER (ORDER BY order_date) AS running_total_sales,
    avg_price,
    AVG(avg_price) OVER (ORDER BY order_date) AS running_avg_price
FROM
(
    SELECT
        DATETRUNC(MONTH, order_date) AS order_date,
        SUM(sales_amount) AS total_sales,
        AVG(price) AS avg_price
    FROM [gold.fact_sales]
    WHERE order_date IS NOT NULL
    GROUP BY DATETRUNC(MONTH, order_date)
) t
```
- Purpose: To track cumulative sales and average price performance over time, providing a clear picture of growth or decline.

## Yearly Product Performance Analysis
This query analyses the yearly performance of products by comparing their sales to both the average sales performance of the product and the previous year's sales.

```sql
WITH yearly_product_sales AS (
    SELECT
        YEAR(f.order_date) AS order_year,
        p.product_name,
        SUM(f.sales_amount) AS current_sales
    FROM [gold.fact_sales] f
    LEFT JOIN [gold.dim_products] p
        ON f.product_key = p.product_key
    WHERE f.order_date IS NOT NULL
    GROUP BY
        YEAR(f.order_date),
        p.product_name
)
SELECT
    order_year,
    product_name,
    current_sales,
    AVG(current_sales) OVER (PARTITION BY product_name) AS avg_sales,
    current_sales - AVG(current_sales) OVER (PARTITION BY product_name) AS diff_avg,
    CASE WHEN current_sales - AVG(current_sales) OVER (PARTITION BY product_name) > 0 THEN 'Above AVG'
         WHEN current_sales - AVG(current_sales) OVER (PARTITION BY product_name) < 0 THEN 'Below AVG'
         ELSE 'AVG'
    END avg_change,
    LAG(current_sales) OVER (PARTITION BY product_name ORDER BY order_year) py_sales,
    current_sales - LAG(current_sales) OVER (PARTITION BY product_name ORDER BY order_year) diff_py,
    CASE WHEN current_sales - LAG(current_sales) OVER (PARTITION BY product_name ORDER BY order_year) > 0 THEN 'Increase'
         WHEN current_sales - LAG(current_sales) OVER (PARTITION BY product_name ORDER BY order_year) < 0 THEN 'Decrease'
         ELSE 'No Change'
    END avg_change
FROM yearly_product_sales
ORDER BY product_name, order_year
```
- Purpose: To gain insights into individual product performance trends over multiple years, identifying products that are consistently performing above/below average or showing year-over-year growth/decline.

## Category Contribution to Overall Sales
This query calculates the total sales for each product category and determines its percentage contribution to the overall sales.

```sql
WITH category_sales AS (
    SELECT
        category,
        SUM(sales_amount) AS total_sales
    FROM [gold.fact_sales] f
    LEFT JOIN [gold.dim_products] p
        ON f.product_key = p.product_key
    GROUP  BY category
)
SELECT
    category,
    total_sales,
    SUM(total_sales) OVER () AS overall_sales,
    /*CAST USED TO CHANGE TOTAL_SALES DATATYPE TO FLOAT, ROUND USED TO CHANGE TO 1 DECIMAL FIGURES*/
    CONCAT(ROUND((CAST (total_sales AS FLOAT)/SUM(total_sales) OVER ()) * 100, 1), ' %') AS percentage_of_total
FROM category_sales
```
- Purpose: To understand which product categories are driving the most revenue and their relative importance to the business.

## Product Segmentation by Cost Ranges
This query segments products into different cost ranges and counts the number of products within each segment.

```sql
WITH product_segment AS (
    SELECT
        product_key,
        product_name,
        cost,
        CASE WHEN cost < 100 THEN 'Below 100'
             WHEN cost BETWEEN 100 AND 500 THEN '100-500'
             WHEN cost BETWEEN 500 AND 1000 THEN '500-1000'
             ELSE 'Over 1000'
        END cost_range
    FROM [gold.dim_products]
)
SELECT
    cost_range,
    COUNT(product_key) AS total_product
FROM
    product_segment
GROUP BY cost_range
ORDER BY total_product desc
```
- Purpose: To classify products based on their cost, which can be useful for inventory management, pricing strategies, and understanding product portfolio distribution.

##Customer Segmentation by Spending Behavior
This query segments customers into 'VIP', 'Regular', and 'New Customer' categories based on their total spending and purchase history (lifespan).

```sql
WITH customer_spending AS (
SELECT
c.customer_key,
SUM(sales_amount) AS total_spending,
MIN(order_date) AS first_order,
MAX(order_date) AS last_order,
DATEDIFF(MONTH, MIN(order_date),MAX(order_date)) AS lifespan
FROM [gold.fact_sales] f
LEFT JOIN [gold.dim_customers] c
ON f.customer_key = c.customer_key
GROUP BY c.customer_key
)
SELECT
customer_segment,
COUNT(customer_key) AS total_customer
FROM(
	SELECT
	customer_key,
	total_spending,
	lifespan,
	CASE WHEN lifespan >= 12 AND total_spending > 5000 THEN 'VIP'
		 WHEN lifespan >= 12 AND total_spending <= 5000 THEN 'Regular'
		 ELSE 'New Customer'
	END customer_segment
	FROM customer_spending) t
GROUP BY customer_segment
ORDER BY 2
```
- Purpose: To categorize customers for targeted marketing, loyalty programs, and personalized outreach.
Assigns a (customer_segment) based on lifespan and total_spending:
     * VIP: Lifespan ≥12 months AND total spending >£5,000.
     * Regular: Lifespan ≥12 months AND total spending ≤£5,000.
     * New Customer: Lifespan <12 months.

## Customer Report View (dbo.customer_report)
This section creates a SQL VIEW named dbo.customer_report that provides a comprehensive overview of customer data, including segmentation, aggregated metrics, and key performance indicators (KPIs).
```sql
CREATE VIEW dbo.customer_report AS
WITH base_query AS (
/*1.    Gather essentail fields such as names, ages and transaction details.*/
SELECT
f.order_number,
f.product_key,
f.order_date,
f.quantity,
f.sales_amount,
c.customer_key,
c.customer_number,
CONCAT(c.first_name, ' ', c.last_name) AS full_name,
DATEDIFF (YEAR, c.birthdate, GETDATE()) AS age
FROM [gold.fact_sales] f
LEFT JOIN [gold.dim_customers] c
ON f.customer_key = c.customer_key
WHERE order_number IS NOT NULL
)
, customer_aggregation AS (

/*2.    Segments customer into categories(VIP, Regular, New) and age groups.*/
SELECT
    customer_key,
    customer_number,
    full_name,
    age,
    COUNT(DISTINCT order_number) AS total_order,
    SUM(sales_amount) AS total_sales,
    SUM(quantity) AS total_quantity,
    COUNT(DISTINCT product_key) AS total_product,
    MAX(order_date) AS last_order_date,
    DATEDIFF(MONTH, MIN(order_date),MAX(order_date)) AS lifespan
FROM base_query
GROUP BY
    customer_key,
    customer_number,
    full_name,
    age
)
/* FULL REPORT*/
SELECT
customer_key,
customer_number,
full_name,
age,
CASE WHEN age < 20 THEN 'Under 20'
     WHEN age BETWEEN 20 AND 29 THEN '20-29'
     WHEN age BETWEEN 30 AND 39 THEN '30-39'
     WHEN age BETWEEN 40 AND 49 THEN '40-49'
     ELSE '50 and above'
END AS age_group,

CASE WHEN lifespan >= 12 AND total_sales > 5000 THEN 'VIP'
    WHEN lifespan >= 12 AND total_sales <= 5000 THEN 'Regular'
    ELSE 'New Customer'
END customer_segment,
last_order_date,
DATEDIFF(MONTH, last_order_date, GETDATE()) AS recency,
total_order,
total_sales,
total_quantity,
total_product,
lifespan,
/* Compute avg order value*/
CASE WHEN total_sales = 0 THEN 0
     ELSE total_sales/total_order
END AS avg_order_value,
/* Compute avg monthly spent*/
CASE WHEN lifespan = 0 THEN total_sales
     ELSE total_sales / lifespan
END AS avg_monthly_spent
FROM customer_aggregation

```
- Purpose: To provide a single, easy-to-query view for detailed customer analysis, including demographic information, spending habits, and loyalty metrics, which will be used for PowerBI dashboard reports.

## Product Report View (dbo.product_report)
This section creates a SQL VIEW named dbo.product_report that offers a comprehensive overview of product data, including segmentation by revenue, aggregated metrics, and key performance indicators (KPIs).

```sql
CREATE VIEW dbo.product_report AS
WITH base_query AS (
/*1) BASE QUERY: RETRIEVES CORE COLUMN FROM fact_sales AND dim_products table */

SELECT
f.order_number,
f.order_date,
f.customer_key,
f.sales_amount,
p.product_key,
f.quantity,
p.product_name,
p.category,
p.subcategory,
p.cost
FROM [gold.fact_sales] f
LEFT JOIN [gold.dim_products] p
ON f.product_key = p.product_key
WHERE order_date IS NOT NULL
),

product_aggregate AS (

/* 2)  This section summarize key metrics at the product level*/
SELECT
    product_key,
    product_name,
    category,
    subcategory,
    cost,
    SUM(sales_amount) AS total_sales,
    SUM(quantity) AS total_quantity,
    COUNT(DISTINCT order_number) AS total_orders,
    COUNT(DISTINCT customer_key) AS total_customers,
    DATEDIFF(MONTH, MIN(order_date), MAX(order_date)) AS lifespan,
    MAX(order_date) AS last_sale_date,
    ROUND(AVG(CAST(sales_amount AS FLOAT) /NULLIF(quantity,0)),1) AS avg_selling_price

FROM base_query

GROUP BY
    product_key,
    product_name,
    category,
    subcategory,
    cost
)


--3) Combine all product results into one output
SELECT
    product_key,
    product_name,
    category,
    subcategory,
    cost,
    last_sale_date,
    DATEDIFF(MONTH, last_sale_date, GETDATE()) AS recency,
    CASE
        WHEN total_sales > 50000 THEN 'High-Performer'
        WHEN total_sales >= 10000 THEN 'Mid-Range'
        ELSE 'Low-Performer'
    END AS product_segment,
    lifespan,
    total_orders,
    total_sales,
    total_quantity,
    total_customers,
    avg_selling_price,

    --Average Order Revenue
    CASE
        WHEN total_orders = 0 THEN 0
        ELSE total_sales/total_orders
    END AS avg_order_revenue,

    --Average Monthly Revenue
    CASE
        WHEN lifespan = 0 THEN 0
        ELSE total_sales/lifespan
    END AS avg_monthly_revenue

FROM product_aggregate
```
- Purpose: To provide a single, easy-to-query view for detailed product analysis, including performance segmentation, sales metrics, and revenue KPIs.

# 5. How to Use
     1.  Database Connection: Ensure you have access to a SQL Server database (or compatible SQL environment) with the gold.fact_sales, gold.dim_products, and gold.dim_customers tables populated with your data.

     2.  Execute Queries: You can run individual queries or the entire script in your SQL client.

     3.  Create Views: To utilize the customer_report and product_report, execute their respective CREATE VIEW statements. Once created, you can query them like regular tables:

```sql
SELECT * FROM dbo.customer_report;
SELECT * FROM dbo.product_report;
```
    4.  Adaptation: Modify table names, schema names, or column names as needed to match your specific database schema. Adjust the segmentation thresholds (e.g., for VIP customers or product performance) to align with your business definitions.

# 6. Technologies Used
- MsSQL: The primary language used for data manipulation and analysis.

- Microsoft SQL Server (or compatible RDBMS): The intended database environment for this script.
