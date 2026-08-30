# DAX Measures & Calculated Columns Reference
### Olist E-Commerce BI Pipeline — Power BI Data Model

All measures live in a dedicated `_Measures` table (best practice — keeps
business logic separate from raw fact/dimension tables). Calculated
columns are noted individually with the table they belong to, since
those must be added directly on that table (they need row context).

---

## Core Measures — Revenue & Orders

```dax
Total Revenue = SUM(fact_order_items[item_total])

Total Orders = DISTINCTCOUNT(fact_orders[order_id])

Average Order Value = DIVIDE([Total Revenue], [Total Orders])

Total Freight Value = SUM(fact_order_items[freight_value])
```

## Core Measures — Delivery

```dax
Delivered Orders =
CALCULATE([Total Orders], fact_orders[order_status] = "delivered")

Extreme Delay Orders =
CALCULATE([Total Orders], fact_orders[extreme_delivery_delay_flag] = TRUE)

Delivery Delay Rate = DIVIDE([Extreme Delay Orders], [Delivered Orders])

Avg Delivery Days = AVERAGE(fact_orders[delivery_time_days])
```

## Core Measures — Satisfaction & Repeat Customers

```dax
Avg Review Score = AVERAGE(fact_orders[avg_review_score])

Total Unique Customers =
COUNTROWS(SUMMARIZE(fact_orders, dim_customers[customer_unique_id]))

Repeat Customers =
VAR CustomerOrderCounts =
    SUMMARIZE(
        fact_orders,
        dim_customers[customer_unique_id],
        "NumOrders", COUNTROWS(fact_orders)
    )
RETURN
    COUNTROWS(FILTER(CustomerOrderCounts, [NumOrders] > 1))

Repeat Customer Rate = DIVIDE([Repeat Customers], [Total Unique Customers])
```
> **Note:** Repeat Customer Rate deliberately uses `customer_unique_id`,
> not `customer_id` — in the Olist dataset, `customer_id` is generated
> fresh per order, while `customer_unique_id` identifies the actual
> person across orders.

```dax
One-Time Customers = [Total Unique Customers] - [Repeat Customers]

Repeat Customer Rate (All-Time) =
CALCULATE([Repeat Customer Rate], ALL(dim_date))
```
> **Note:** This measure deliberately ignores the Year slicer. "Repeat
> customer" is a cross-time concept — a customer who ordered in 2017
> and again in 2018 IS a repeat customer, but gets miscounted as
> one-time under a single-year filter.

---

## Time Intelligence

```dax
Revenue YTD = TOTALYTD([Total Revenue], dim_date[date_key])

Revenue PY =
CALCULATE([Total Revenue], SAMEPERIODLASTYEAR(dim_date[date_key]))

Revenue YTD PY =
CALCULATE([Revenue YTD], SAMEPERIODLASTYEAR(dim_date[date_key]))

Revenue YoY % = DIVIDE([Total Revenue] - [Revenue PY], [Revenue PY])

Revenue YTD YoY % =
DIVIDE([Revenue YTD] - [Revenue YTD PY], [Revenue YTD PY])

Orders YTD = TOTALYTD([Total Orders], dim_date[date_key])

Orders PY =
CALCULATE([Total Orders], SAMEPERIODLASTYEAR(dim_date[date_key]))

Orders YoY % = DIVIDE([Total Orders] - [Orders PY], [Orders PY])
```
> **Note:** 2016 has very few orders (Sept–Dec only), so any YoY
> comparison involving 2016 as the baseline produces extreme,
> misleading percentages. The dashboard defaults to 2018 for this
> reason — 2018 vs. 2017 is the only clean, representative comparison.

---

## KPI Card Comparisons (Card + "Last Year" + Delta pattern)

```dax
Average Order Value PY = DIVIDE([Revenue PY], [Orders PY])

Average Order Value YoY % =
DIVIDE(
    [Average Order Value] - [Average Order Value PY],
    [Average Order Value PY]
)

Avg Review Score PY =
CALCULATE([Avg Review Score], SAMEPERIODLASTYEAR(dim_date[date_key]))

Review Score Point Diff = [Avg Review Score] - [Avg Review Score PY]

Delivery Delay Rate PY =
CALCULATE([Delivery Delay Rate], SAMEPERIODLASTYEAR(dim_date[date_key]))

Delivery Delay Rate Point Diff =
[Delivery Delay Rate] - [Delivery Delay Rate PY]
```
> **Note:** Review Score and Delivery Delay Rate use a **point
> difference**, not a percentage — a % change on a 1–5 scale or on a
> rate-of-a-rate is misleading, so these are formatted as a plain
> difference instead (e.g., "+0.15 vs LY", "-2.1 pts vs LY").

---

## Conditional Formatting Color Measures

```dax
Revenue YoY Color = IF([Revenue YoY %] >= 0, "#00D9A3", "#FF5C5C")

Orders YoY Color = IF([Orders YoY %] >= 0, "#00D9A3", "#FF5C5C")

AOV YoY Color = IF([Average Order Value YoY %] >= 0, "#00D9A3", "#FF5C5C")

Review Score Diff Color =
IF([Review Score Point Diff] >= 0, "#00D9A3", "#FF5C5C")

Delivery Delay Rate Color =
IF([Delivery Delay Rate Point Diff] <= 0, "#00D9A3", "#FF5C5C")
```
> **Note:** Delivery Delay Rate uses **reversed logic** — a positive
> change means *more* delays (bad), so green/red flip compared to
> every other card, where positive = good.

---

## Sales Performance Page

```dax
Total Sellers = DISTINCTCOUNT(fact_order_items[seller_id])

Total Orders (by Category) = DISTINCTCOUNT(fact_order_items[order_id])
```
> **Note:** `Total Orders` (built on `fact_orders`) can't be filtered
> by product category, since `fact_orders` has no relationship to
> `dim_products` — only `fact_order_items` does. This category-aware
> version is swapped into the `Metric Selector` field parameter in
> place of the base `Total Orders` measure.

**Field Parameter — "Metric Selector":** Total Revenue, Total Orders
(by Category), Average Order Value, Total Freight Value

**Field Parameter — "Time Granularity":** Month Abbr, Quarter Label

---

## Delivery & Logistics Page

**Calculated column** on `dim_customers`:
```dax
State Location = dim_customers[customer_state] & ", Brazil"
```
> Fixes Map visual geocoding — bare 2-letter state codes often fail
> to resolve without country context.

**Calculated column** on `fact_orders`:
```dax
Estimated Delivery Days =
DATEDIFF(
    fact_orders[order_purchase_timestamp],
    fact_orders[order_estimated_delivery_date],
    DAY
)
```

**Measure:**
```dax
Avg Estimated Delivery Days = AVERAGE(fact_orders[Estimated Delivery Days])
```

**Calculated column** on `dim_date` (for weekday chart sort order):
```dax
Weekday Number = WEEKDAY(dim_date[date_key], 2)
```

---

## Calculated Columns — Chart Support

**On `fact_orders`:**
```dax
Review Score Whole = ROUND(fact_orders[avg_review_score], 0)

Delivery Bucket =
SWITCH(
    TRUE(),
    ISBLANK(fact_orders[delivery_time_days]), "Unknown / Not Delivered",
    fact_orders[delivery_time_days] <= 7,  "0-7 days",
    fact_orders[delivery_time_days] <= 14, "8-14 days",
    fact_orders[delivery_time_days] <= 30, "15-30 days",
    "30+ days"
)

Delivery Bucket Sort =
SWITCH(
    TRUE(),
    ISBLANK(fact_orders[delivery_time_days]), 5,
    fact_orders[delivery_time_days] <= 7,  1,
    fact_orders[delivery_time_days] <= 14, 2,
    fact_orders[delivery_time_days] <= 30, 3,
    4
)
```
*(Delivery Bucket sorted by Delivery Bucket Sort, via Column tools >
Sort by column)*

**On `dim_date`:**
```dax
Month Abbr = LEFT(dim_date[month_name], 3)
Quarter Label = "Q" & dim_date[quarter]
```
*(Month Abbr sorted by the numeric `month` column; Quarter Label
sorted by the numeric `quarter` column)*

---

## Model Notes

- **Star schema:** `dim_customers`, `dim_sellers`, `dim_products`,
  `dim_date` (marked as Date Table) all relate 1-to-many into
  `fact_order_items` (line-item grain) and `fact_orders` (order
  grain, with payments/reviews pre-aggregated).
- **No direct fact-to-fact relationship** between `fact_orders` and
  `fact_order_items` — both connect only through shared dimensions,
  avoiding ambiguous filter paths.
- **`order_payments_clean`** relates into `fact_orders` on `order_id`
  as many-to-one, since one order can have multiple payment
  (installment) rows.
- **Data coverage:** Sept 2016 – Aug 2018. 2016 is sparse
  (Sept–Dec only); trailing months near the dataset's true end were
  trimmed from trend charts via **visual-level** filters (not
  report-level, which would incorrectly clip YoY prior-year
  comparisons too).
