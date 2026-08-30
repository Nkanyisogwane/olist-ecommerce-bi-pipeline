# Olist E-Commerce BI Pipeline

**An end-to-end business intelligence pipeline** — from raw CSVs to an
interactive Power BI dashboard — built on the Brazilian E-Commerce Public
Dataset by Olist.

`Python (pandas)` → `SQL Server (star schema)` → `Power BI (DAX, field
parameters, bookmarks)`

---

## 📊 Overview

Olist is a Brazilian e-commerce marketplace connecting small businesses
to major sales channels. This project builds a complete analytics
pipeline on ~100K of their real orders (2016–2018), covering:

- **Data cleaning** in Python — validating, flagging anomalies, and
  exporting clean data without discarding information
- **Relational modeling** in SQL Server — a proper star schema with
  fact and dimension views, plus analytical queries
- **Business intelligence** in Power BI — a 4-page interactive
  dashboard with time intelligence, dynamic field parameters, and
  guided navigation

This was a deliberate step up from two earlier, smaller portfolio
projects — the goal here was to demonstrate the *full* pipeline a data
analyst would actually own end-to-end, not just the visualization layer.

---

## 🖼️ The Dashboard

### Executive Summary
High-level KPIs with year-over-year context, category and state
breakdowns, and delivery-speed distribution — the "one page" view.

![Executive Summary](screenshots/01_executive_summary.png)

### Sales Performance
Category and seller performance with a **dynamic field parameter**
letting the viewer toggle the bar chart between Revenue, Orders, AOV,
and Freight — plus a decomposition tree for revenue drill-down and
payment method breakdown.

![Sales Performance](screenshots/02_sales_performance.png)

### Delivery & Logistics
Regional delivery performance, delivery time by day of week, and a
direct comparison of estimated vs. actual delivery time.

![Delivery & Logistics](screenshots/03_delivery_logistics.png)

### Customer Satisfaction
Review score trends, the delivery-speed-to-satisfaction relationship,
and repeat customer analysis.

![Customer Satisfaction](screenshots/04_customer_satisfaction.png)

---

## 🔑 Key Insights

- **Delivery speed strongly predicts satisfaction.** Average review
  score drops from 4.4 (0–7 day delivery) to 2.1 (30+ days), and to
  1.7 for orders that were never marked delivered — the clearest
  signal in the entire dataset.
- **Olist under-promises on delivery time.** Estimated delivery days
  are consistently higher than actual delivery days across every
  month observed — a sign of deliberately conservative delivery
  estimates rather than a business problem.
- **Weekend order placement adds delay.** Orders placed Friday and
  Saturday take noticeably longer to deliver (~13 days) than the rest
  of the week (~11.2–11.9 days), likely reflecting weekend processing
  gaps.
- **Repeat customer rate is genuinely low (~3.1%), and that's
  expected** for a multi-seller marketplace like Olist — most
  customers interact with a different seller each purchase, unlike a
  single-brand retailer.
- **Regional outliers need volume context.** States like RR show the
  highest delay rates, but also the lowest order volume — worth
  reading as a noisy small sample, not a systemic regional failure.

---

## 🧹 Data Cleaning (Python)

- 8 of 9 source tables cleaned (geolocation excluded — too large and
  not required for this project's scope)
- **Flag, don't delete:** anomalous rows (implausible timestamps,
  extreme delivery delays, shared review IDs) were flagged with `BIT`
  columns rather than removed, preserving full traceability
- **Tiered cleaning depth:** the central `orders` table received deep
  validation; peripheral tables (sellers, products, category
  translations) received a lighter, consistent pass — applying the
  same rigor everywhere would have produced unmanageable code volume
  for little added analytical value

**Key data quality findings:**
| Finding | Detail |
|---|---|
| Missing delivery timestamps | 8 orders marked "delivered" with no delivery date (flagged) |
| Suspicious date gaps | 14 orders with >7 day approval/carrier gaps, clustered near a Sept 2017 batch artifact (flagged) |
| Extreme delivery delays | 288 orders >60 days (flagged); median delivery time is 10 days |
| Shared review IDs | 814 review IDs span multiple orders — appears to be Olist's feedback bundling system, not an error (flagged) |
| Missing product category | 610 products (flagged) |

---

## 🗄️ SQL Server — Star Schema

Two fact tables at different grains, built as SQL views over the
cleaned tables:

- **`fact_order_items`** — line-item grain, for revenue/product/seller
  analysis
- **`fact_orders`** — order grain, with payments and reviews
  pre-aggregated (an order can have multiple payment rows via
  installments, and a small number share review IDs)

Four dimension views: `dim_customers`, `dim_sellers`, `dim_products`
(joined to category translations), and a generated `dim_date` table.

Six analytical queries validate the model before Power BI connects to
it: revenue by category, top sellers, delivery delay by state, monthly
revenue trend, payment type breakdown, and review score vs. delivery
delay.

---

## 📈 Power BI — Data Model & Features

- **Import mode**, 7-table model (star schema views + payments table),
  relationships verified to avoid ambiguous fact-to-fact filter paths
- **Dedicated `_Measures` table** holding all DAX — core measures,
  full time intelligence (YTD, PY, YoY%), and conditional-formatting
  color measures
- **Field parameters** — one lets users swap the Sales Performance
  chart between four metrics; a second lets users toggle chart
  granularity between Month and Quarter
- **Bookmark-driven navigation** — custom nav bar and per-page Reset
  buttons, with default page tabs hidden
- **Conditional formatting** — teal-green/coral-red indicators on
  every KPI delta, correctly reversed for metrics where a "positive"
  change is actually a bad outcome (e.g., delivery delay rate)
- **Decomposition tree** for interactive revenue drill-down by
  category → seller state → customer state

See [`power_bi/dax_measures_reference.md`](power_bi/dax_measures_reference.md)
for the full DAX measure library.

---

## ⚠️ Data Coverage Note

This dataset effectively spans **Sept 2016 – Aug 2018**. 2016 is very
sparse (a handful of orders from September onward), and the final
couple of months of the dataset thin out as well. Trend charts are
filtered to the reliable coverage window at the **visual level**
(not report level, which would incorrectly distort year-over-year
comparisons) — this is called out directly on the dashboard.

---

## 🧗 Challenges & What I'd Do Differently

- **ODBC driver mismatch.** OLE DB Driver 19 and the SSMS Import
  Wizard both failed on this machine (type mismatches, CSV quoting
  issues with Portuguese free-text fields). ODBC Driver 17 with
  `sqlalchemy` + `pyodbc` turned out to be the reliable path for
  Python → SQL Server imports.
- **Scope discipline was the real lesson.** Not the DAX, not the SQL —
  knowing where "thorough" quietly becomes "over-engineered." Cutting
  Azure Maps geocoding and deferring statistical analysis
  (correlation testing, A/B testing, cohort analysis) to a future
  standalone project kept this one's narrative focused.
- **A subtle YoY bug taught me a real DAX lesson.** Applying a
  report-level date filter to trim thin trailing months also silently
  clipped `SAMEPERIODLASTYEAR`'s comparison window, inflating YoY%
  into misleading triple digits. The fix was scoping that filter to
  individual visuals instead of the whole report — a good reminder
  that filter *scope* in Power BI matters as much as the filter logic
  itself.

---

## 🔮 What's Next

A **standalone statistical analysis project** (correlation testing,
A/B testing, cohort analysis) is planned as its own separate
repository — intentionally kept out of this project to preserve its
focused BI-pipeline narrative. It'll reuse this project's cleaned data
and SQL views as a starting point.

---

## 🛠️ Tech Stack

`Python 3.14` · `pandas` · `SQL Server` · `T-SQL` · `Power BI Desktop`
· `DAX` · `pyodbc` / `sqlalchemy`

---

## 📁 Repository Structure

```
olist-ecommerce-bi-pipeline/
├── README.md
├── python/
│   ├── data_cleaning.py
│   └── requirements.txt
├── sql/
│   ├── 01_create_tables.sql
│   ├── 02_star_schema_views.sql
│   └── 03_analytical_queries.sql
├── power_bi/
│   ├── Olist_Dashboard.pbix
│   └── dax_measures_reference.md
├── data/
│   ├── raw/        (see README inside — not committed, linked to source)
│   └── clean/
└── screenshots/
```

---

## ▶️ Reproducing This Project

1. Download the raw dataset — see `data/raw/README.md` for the Kaggle link
2. Run `python/data_cleaning.py` to generate the cleaned CSVs
3. Create a SQL Server database and run the scripts in `sql/` in order
   (table creation → star schema views → analytical queries)
4. Open `power_bi/Olist_Dashboard.pbix`, update the SQL Server
   connection to point at your own instance, and refresh

---

## 📬 Data Source

[Brazilian E-Commerce Public Dataset by Olist](https://www.kaggle.com/datasets/olistbr/brazilian-ecommerce) — Kaggle

---

## 👤 Author

**Nkanyiso Gwane**
[LinkedIn](#) · [GitHub](#)
