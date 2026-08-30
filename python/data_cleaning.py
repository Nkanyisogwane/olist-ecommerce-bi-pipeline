import pandas as pd
import numpy as np

# Load raw data - one df per table
raw_customers = pd.read_csv('olist_customers_dataset.csv')
raw_geolocation = pd.read_csv('olist_geolocation_dataset.csv')
raw_order_items = pd.read_csv('olist_order_items_dataset.csv')
raw_order_payments = pd.read_csv('olist_order_payments_dataset.csv')
raw_order_reviews = pd.read_csv('olist_order_reviews_dataset.csv')
raw_orders = pd.read_csv('olist_orders_dataset.csv')
raw_products = pd.read_csv('olist_products_dataset.csv')
raw_sellers = pd.read_csv('olist_sellers_dataset.csv')
raw_category_translation = pd.read_csv('product_category_name_translation.csv')

# Work on copies, never touch raw_ dfs directly
customers = raw_customers.copy()
geolocation = raw_geolocation.copy()
order_items = raw_order_items.copy()
order_payments = raw_order_payments.copy()
order_reviews = raw_order_reviews.copy()
orders = raw_orders.copy()
products = raw_products.copy()
sellers = raw_sellers.copy()
category_translation = raw_category_translation.copy()


for name, df in {
    'customer': customers,
    'geoloation': geolocation,
    'order_items': order_items,
    'order_payments': order_payments,
    'order_reviews': order_reviews,
    'orders': orders,
    'products': products,
    'sellers': sellers,
    'category_translation': category_translation
}.items(): print(f"{name}: {df.shape}")

#Step 2: profile data

print(orders.shape)
print(orders.head())
print(orders.info())
print(orders.describe(include='all'))
print(orders.columns)


# Step 3: Structural Cleaning — fix data types
# Convert date columns from str to datetime

date_columns = [
    'order_purchase_timestamp',
    'order_approved_at',
    'order_delivered_carrier_date',
    'order_delivered_customer_date',
    'order_estimated_delivery_date'
]

for col in date_columns:
    orders[col] = pd.to_datetime(orders[col], errors='coerce')

# Verify the conversion worked
print(orders.dtypes)
print(orders[date_columns].describe())


# Step 4: Missing Values
print(orders.isnull().sum())

# Cross-check: are the missing delivery dates explained by order_status?
print(orders[orders['order_delivered_customer_date'].isnull()]['order_status'].value_counts())



weird_delivered = orders[
    (orders['order_status'] == 'delivered') &
    (orders['order_delivered_customer_date'].isnull())
]
print(weird_delivered[['order_id', 'order_status', 'order_purchase_timestamp', 
                          'order_approved_at', 'order_delivered_carrier_date', 
                          'order_delivered_customer_date']])


# Show full width, no truncation
pd.set_option('display.max_columns', None)
pd.set_option('display.width', None)

weird_delivered = orders[
    (orders['order_status'] == 'delivered') &
    (orders['order_delivered_customer_date'].isnull())
]
print(weird_delivered[['order_id', 'order_purchase_timestamp', 
                          'order_approved_at', 'order_delivered_carrier_date', 
                          'order_delivered_customer_date']])


# Flag orders marked 'delivered' but missing the actual delivery timestamp
orders['delivery_date_missing_flag'] = (
    (orders['order_status'] == 'delivered') &
    (orders['order_delivered_customer_date'].isnull())
)

# Verify it worked
print(orders['delivery_date_missing_flag'].value_counts())

#step 5: duplicates
print("Full row duplicates:", orders.duplicated().sum())
print("Duplicate order_id:", orders.duplicated(subset=['order_id']).sum() )


# Check for whitespace or casing issues in order_status
print(orders['order_status'].unique())
print(orders['order_status'].apply(lambda x: x != x.strip().lower()).sum())

# Check for logically impossible date sequences
impossible_1 = orders[orders['order_delivered_customer_date'] < orders['order_purchase_timestamp']]
impossible_2 = orders[orders['order_delivered_carrier_date'] < orders['order_approved_at']]

print("Delivered before purchased:", len(impossible_1))
print("Shipped before approved:", len(impossible_2))


# How large is the gap for these "impossible" cases?
mismatch = orders[orders['order_delivered_carrier_date'] < orders['order_approved_at']].copy()
mismatch['gap'] = mismatch['order_approved_at'] - mismatch['order_delivered_carrier_date']

print(mismatch['gap'].describe())
print(mismatch[['order_id', 'order_approved_at', 'order_delivered_carrier_date', 'gap']].head(10))


 # Separate plausible small gaps from suspicious large gaps
suspicious = mismatch[mismatch['gap'] > pd.Timedelta(days=7)]
minor = mismatch[mismatch['gap'] <= pd.Timedelta(days=7)]

print("Suspicious (gap > 7 days):", len(suspicious))
print("Minor (gap <= 7 days):", len(minor))
print(suspicious[['order_id', 'order_approved_at', 'order_delivered_carrier_date', 'gap']].sort_values('gap', ascending=False).head(15))


#flag orders with suspicious approval/carrier date gap (likely batch artifact)
orders['approval_date_suspicious_flag'] = orders['order_id'].isin(suspicious['order_id'])

print(orders['approval_date_suspicious_flag'].value_counts())

#step 7: outlier review - dellivery time in days
orders['delivery_time_days'] = (orders['order_delivered_customer_date'] - orders['order_purchase_timestamp']).dt.days

print(orders['delivery_time_days'].describe())


# IQR-based outlier detection for delivery_time_days
Q1 = orders['delivery_time_days'].quantile(0.25)
Q3 = orders['delivery_time_days'].quantile(0.75)
IQR = Q3 - Q1
upper_bound = Q3 + 1.5 * IQR

outliers = orders[orders['delivery_time_days'] > upper_bound]
print(f"Upper bound: {upper_bound}")
print(f"Number of outliers: {len(outliers)}")
print(orders['delivery_time_days'].sort_values(ascending=False).head(15))

#flag extreme delivery delays for  investigation (stricter than IQR)
orders['extreme_delivery_delay_flag'] = orders['delivery_time_days'] > 60

print(orders['extreme_delivery_delay_flag'].value_counts())


#step 8 validation pass
print(orders.info())
print(orders.isnull().sum())
print("Duplicates:", orders.duplicated().sum())
print("Row count check:", orders.shape[0], "- should still be 99441")

#Confirm new columns
print(orders[['delivery_date_missing_flag', 'approval_date_suspicious_flag',
               'delivery_time_days', 'extreme_delivery_delay_flag']].head())


print(order_items.shape)
print(order_items.head())
print(order_items.info())
print(order_items.describe(include='all'))
print(order_items.columns)               


#step 3: structural cleaning
order_items['shipping_limit_date'] = pd.to_datetime(order_items['shipping_limit_date'], errors='coerce')
print(order_items.dtypes)

#Light clean checks for order_items
print("Nulls\n", order_items.isnull().sum())
print("Full duplicates:", order_items.duplicated().sum())
print("Negative price or freight:",  (order_items[['price', 'freight_value']] <0).sum())


#Profile order_payments
print(order_payments.shape)
print(order_payments.head())
print(order_payments.info())
print(order_payments.describe(include='all'))


print("Nulls:\n", order_payments.isnull().sum())
print("Full duplicates:", order_payments.duplicated().sum())
print("Payment types:", order_payments['payment_type'].unique())
print("Rows with 0 installments:", (order_payments['payment_installments'] == 0).sum())
print("Rows with 0 payment_value:", (order_payments['payment_value'] == 0).sum())


print(order_reviews.shape)
print(order_reviews.head())
print(order_reviews.info())
print(order_reviews.describe(include='all'))


# Step 3: Fix dtypes
order_reviews['review_creation_date'] = pd.to_datetime(order_reviews['review_creation_date'], errors='coerce')
order_reviews['review_answer_timestamp'] = pd.to_datetime(order_reviews['review_answer_timestamp'], errors='coerce')

# Light clean checks
print("Nulls in key columns:\n", order_reviews[['review_id', 'order_id', 'review_score']].isnull().sum())
print("Full duplicates:", order_reviews.duplicated().sum())
print("Duplicate review_id:", order_reviews.duplicated(subset=['review_id']).sum())
print("Duplicate order_id:", order_reviews.duplicated(subset=['order_id']).sum())


# Peek at a few duplicate review_ids to understand the pattern
dupe_ids = order_reviews[order_reviews.duplicated(subset=['review_id'], keep=False)]
print(dupe_ids.sort_values('review_id')[['review_id', 'order_id', 'review_score']].head(10))

# Flag rows where review_id is shared across multiple orders (known data pattern)
order_reviews['shared_review_id_flag'] = order_reviews.duplicated(subset=['review_id'], keep=False)

print(order_reviews['shared_review_id_flag'].value_counts())


print(customers.shape)
print(customers.head())
print(customers.info())
print(customers.describe(include='all'))


print("Nulls:\n", customers.isnull().sum())
print("Full duplicates:", customers.duplicated().sum())
print("customer_state values:", sorted(customers['customer_state'].unique()))
print("City casing check (should be 0 if consistent):", 
      (customers['customer_city'] != customers['customer_city'].str.strip().str.lower()).sum())


print(products.shape)
print(products.head())
print(products.info())
print(products.describe(include='all'))

#light clean check
print("Nulls:\n", products.isnull().sum())
print("Full duplicates:", products.duplicated().sum())
print("Rows with 0 weight:", (products['product_weight_g'] == 0).sum())
print("Rows with 0 dimensions:", 
      ((products['product_length_cm'] == 0) | 
       (products['product_height_cm'] == 0) | 
       (products['product_width_cm'] == 0)).sum())


# Flag products with impossible zero weight (likely data entry gap)
products['zero_weight_flag'] = products['product_weight_g'] == 0

# Flag products missing category info (610 rows)
products['missing_category_flag'] = products['product_category_name'].isnull()

print(products[['zero_weight_flag', 'missing_category_flag']].sum())


print(sellers.shape)
print(sellers.head())
print(sellers.info())
print(sellers.describe(include='all'))


print("Nulls:\n", sellers.isnull().sum())
print("Full duplicates:", sellers.duplicated().sum())
print("Seller states:", sorted(sellers['seller_state'].unique()))


print(category_translation.shape)
print(category_translation.head())
print(category_translation.info())
print("Nulls:", category_translation.isnull().sum())
print("Duplicates:", category_translation.duplicated().sum())


#exporting now

import os

# Step 9: Export cleaned data
# Create a dedicated folder for clean outputs, separate from raw CSVs
output_folder = "clean_data"
os.makedirs(output_folder, exist_ok=True)

# Export each cleaned table
customers.to_csv(f"{output_folder}/customers_clean.csv", index=False)
order_items.to_csv(f"{output_folder}/order_items_clean.csv", index=False)
order_payments.to_csv(f"{output_folder}/order_payments_clean.csv", index=False)
order_reviews.to_csv(f"{output_folder}/order_reviews_clean.csv", index=False)
orders.to_csv(f"{output_folder}/orders_clean.csv", index=False)
products.to_csv(f"{output_folder}/products_clean.csv", index=False)
sellers.to_csv(f"{output_folder}/sellers_clean.csv", index=False)
category_translation.to_csv(f"{output_folder}/category_translation_clean.csv", index=False)

print("All 8 tables exported successfully to:", output_folder)
print(os.listdir(output_folder))


#importing to sql server
import pandas as pd
from sqlalchemy import create_engine
import urllib

server = 'LAPTOP-Q405HSON\\SQLEXPRESS'
database = 'OListEcommerceDB'

# Using the generic "SQL Server" driver, which ships with Windows
params = urllib.parse.quote_plus(
    f"DRIVER={{ODBC Driver 17 for SQL Server}};SERVER={server};DATABASE={database};Trusted_Connection=yes;"
)
engine = create_engine(f"mssql+pyodbc:///?odbc_connect={params}")

tables = {
    'customers_clean': 'clean_data/customers_clean.csv',
    'sellers_clean': 'clean_data/sellers_clean.csv',
    'category_translation_clean': 'clean_data/category_translation_clean.csv',
    'products_clean': 'clean_data/products_clean.csv',
    'orders_clean': 'clean_data/orders_clean.csv',
    'order_items_clean': 'clean_data/order_items_clean.csv',
    'order_payments_clean': 'clean_data/order_payments_clean.csv',
    'order_reviews_clean': 'clean_data/order_reviews_clean.csv',
}

for table_name, file_path in tables.items():
    df = pd.read_csv(file_path)
    df.to_sql(table_name, con=engine, if_exists='append', index=False)
    print(f"Loaded {len(df)} rows into {table_name}")

print("All tables imported successfully.")
