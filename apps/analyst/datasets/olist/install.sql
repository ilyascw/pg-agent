-- Olist dataset: tables, data from data/olist (make data downloads it), indexes, read
-- access for run_sql and one skill per table. Needs the analyst app.
\set ON_ERROR_STOP on

begin;

create schema olist;

comment on schema olist is 'Olist: бразильский маркетплейс, ~100 тыс. заказов 2016–2018.';

create table olist.category_translation (
    category text primary key,
    category_english text not null
);

create table olist.customers (
    customer_id text primary key,
    customer_unique_id text not null,
    zip_code_prefix text not null,
    city text not null,
    state char(2) not null
);

create table olist.sellers (
    seller_id text primary key,
    zip_code_prefix text not null,
    city text not null,
    state char(2) not null
);

create table olist.products (
    product_id text primary key,
    category text,
    name_length int,
    description_length int,
    photos_qty int,
    weight_g int,
    length_cm int,
    height_cm int,
    width_cm int
);

create table olist.orders (
    order_id text primary key,
    customer_id text not null references olist.customers,
    status text not null,
    purchased_at timestamp not null,
    approved_at timestamp,
    delivered_carrier_at timestamp,
    delivered_customer_at timestamp,
    estimated_delivery_at timestamp not null
);

create table olist.order_items (
    order_id text not null references olist.orders,
    item_seq int not null,
    product_id text not null references olist.products,
    seller_id text not null references olist.sellers,
    shipping_limit_at timestamp not null,
    price numeric(10, 2) not null,
    freight_value numeric(10, 2) not null,
    primary key (order_id, item_seq)
);

create table olist.order_payments (
    order_id text not null references olist.orders,
    payment_seq int not null,
    payment_type text not null,
    installments int not null,
    value numeric(10, 2) not null,
    primary key (order_id, payment_seq)
);

create table olist.order_reviews (
    review_id text not null,
    order_id text not null references olist.orders,
    score int not null,
    comment_title text,
    comment_message text,
    created_at timestamp not null,
    answered_at timestamp not null,
    primary key (review_id, order_id)
);

create table olist.geolocation (
    zip_code_prefix text not null,
    lat double precision not null,
    lng double precision not null,
    city text not null,
    state char(2) not null
);

copy olist.category_translation
from '/work/data/olist/product_category_name_translation.csv' with (format csv, header true);
copy olist.customers
from '/work/data/olist/olist_customers_dataset.csv' with (format csv, header true);
copy olist.sellers
from '/work/data/olist/olist_sellers_dataset.csv' with (format csv, header true);
copy olist.products
from '/work/data/olist/olist_products_dataset.csv' with (format csv, header true);
copy olist.orders
from '/work/data/olist/olist_orders_dataset.csv' with (format csv, header true);
copy olist.order_items
from '/work/data/olist/olist_order_items_dataset.csv' with (format csv, header true);
copy olist.order_payments
from '/work/data/olist/olist_order_payments_dataset.csv' with (format csv, header true);
copy olist.order_reviews
from '/work/data/olist/olist_order_reviews_dataset.csv' with (format csv, header true);
copy olist.geolocation
from '/work/data/olist/olist_geolocation_dataset.csv' with (format csv, header true);

create index on olist.orders (customer_id);
create index on olist.order_items (product_id);
create index on olist.order_items (seller_id);
create index on olist.order_reviews (order_id);
create index on olist.geolocation (zip_code_prefix);

grant usage on schema olist to analyst_reader;
grant select on all tables in schema olist to analyst_reader;

select skills.import('analyst', '/work/apps/analyst/datasets/olist/skills');

commit;

analyze olist.category_translation, olist.customers, olist.sellers, olist.products, olist.orders,
olist.order_items, olist.order_payments, olist.order_reviews, olist.geolocation;
