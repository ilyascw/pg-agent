---
description: заказы Olist: статус, даты покупки, отгрузки, доставки и обещанная дата
---
# olist.orders — заказы

Датасет Olist — бразильский маркетплейс, ~99 тыс. заказов с сентября 2016 по октябрь 2018 (полные месяцы — с января 2017 по август 2018). Деньги в бразильских реалах (BRL), время местное, без часового пояса.

Одна строка — один заказ. Центральная таблица: к ней по `order_id` цепляются товары,
платежи и отзывы, а по `customer_id` — покупатель.

## Колонки
| Колонка | Смысл |
| --- | --- |
| order_id | ключ заказа |
| customer_id | → olist.customers; у каждого заказа свой customer_id, даже у одного человека |
| status | delivered (96 478), shipped, canceled, unavailable, invoiced, processing, created, approved |
| purchased_at | момент покупки — основная дата для помесячной динамики |
| approved_at | оплата подтверждена |
| delivered_carrier_at | передан в доставку |
| delivered_customer_at | получен покупателем; заполнен почти только у delivered |
| estimated_delivery_at | обещанная дата доставки |

## Подвохи
- Сроки доставки считай только по `status = 'delivered'` и `delivered_customer_at is not null`.
- Опоздание: `delivered_customer_at > estimated_delivery_at` (≈8% доставленных).
- Сентябрь–декабрь 2016 и сентябрь–октябрь 2018 почти пустые: для трендов бери 2017-01 … 2018-08.
- Повторные покупки одного человека ищи через `customers.customer_unique_id`, а не `customer_id`.

## Пример
```sql
select date_trunc('month', purchased_at)::date as month, count(*) as orders
from olist.orders
where purchased_at >= '2017-01-01' and purchased_at < '2018-09-01'
group by 1 order by 1;
```
