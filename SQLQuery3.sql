--CALCULATE TOTAL_SALES TREND OVER THE YEAR IN MONTHS
SELECT 
DATETRUNC(MONTH, order_date) AS order_year, 
SUM(sales_amount) AS total_sales,
COUNT(DISTINCT customer_key) AS total_customers,
SUM(quantity) AS total_quantity
FROM [gold.fact_sales]
WHERE order_date IS NOT NULL
GROUP BY DATETRUNC(MONTH, order_date)
ORDER BY 1



-- CALCULATE THE TOTAL SALES PER MONTH AND RUNNING TOTAL
SELECT
order_date,
total_sales,
SUM(total_sales) OVER (ORDER BY order_date) AS running_total_sales, /*running total section*/
avg_price,
AVG(avg_price) OVER (ORDER BY order_date) AS running_avg_price	/*running AVG section*/
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


/* Analyse the yearly perfomance of products by comparing their sales to both the average sales performance of the product and the previous year */

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


--CALCULATE BASED ON CATEGORIES CONTRIBUTION TO OVERALL SALES
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


--SEGMENT PRODUCT INTO COST RANGES AND COUNT PRODUCTS IN EACH SEGMENT
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





/*GROUP CUSTOMER INTO 3 SEGMENT BASED ON THEIR SPENDING BEHAVIOUR:
	-VIP: CUSTOMER THAT SPENT OVER £5,000 AND AT LEAST 12 MONTHS OF HISTORY
	-REGULAR: CUSTOMER THAT SPENT BELOW £5,000 AND AT LEAST 12 MONTHS OF HISTORY
	-NEW: CUSTOMERS WITH LESS THAN 12 MONTHS OF HISTORY
AND FIND THE TOTAL NUMBER OF CUSTOMERS BY THAT GROUP
*/

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



/*   CUSTOMER REPORT

HIGHLIGHTS:
	1.	Gather essentail fields such as names, ages and transaction details.
	2.	Segments customer into categories(VIP, Regular, New) and age groups.
	3.	Aggregates customer level metrics:
		- total orders
		- total sales
		- total quantity purchased
		- total products
		- lifespan(in months)
	4.	Calculate valuable KPIs:
		- recency (MOnths since last order)
		- average order value
		- average monthly spend
*/

CREATE VIEW dbo.customer_report AS   /* CREATE VIEW FOR REPORT INSIDE SCHEMA dbo*/
WITH base_query AS (
/*1.	Gather essentail fields such as names, ages and transaction details.*/
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

/*2.	Segments customer into categories(VIP, Regular, New) and age groups.*/
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


SELECT
*
FROM [dbo].[customer_report]


/*   PRODUCT REPORT

HIGHLIGHTS:
	1.	Gather essentail fields such as Product names, category, subcategory,ages and transaction details.
	2.	Segments product by revenue into High-performers, Mid-performer, Low-performer.
	3.	Aggregates product level metrics:
		- total orders
		- total sales
		- total quantity purchased
		- total customers (distinct)
		- lifespan(in months)
	4.	Calculate valuable KPIs:
		- recency (MOnths since last sale)
		- average order revenue
		- average monthly spend
*/

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


SELECT
*
FROM product_report