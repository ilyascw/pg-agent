---
description: покупатели Olist: город, штат, индекс; customer_unique_id для повторных покупок
---
# olist.customers — покупатели

Датасет Olist — бразильский маркетплейс, ~99 тыс. заказов с сентября 2016 по октябрь 2018 (полные месяцы — с января 2017 по август 2018). Деньги в бразильских реалах (BRL), время местное, без часового пояса.

Одна строка — покупатель **в рамках одного заказа**: `customer_id` выдаётся на каждый
заказ. Настоящий человек — `customer_unique_id` (96 096 людей на 99 441 запись).

## Колонки
| Колонка | Смысл |
| --- | --- |
| customer_id | ключ; = orders.customer_id, 1 к 1 с заказом |
| customer_unique_id | постоянный id человека |
| zip_code_prefix | первые 5 цифр индекса (текст, с ведущими нулями) → olist.geolocation |
| city | город, строчными, без диакритики: sao paulo |
| state | штат, 2 буквы: SP (42%), RJ, MG, RS, PR… |

## Подвохи
- Количество покупателей = `count(distinct customer_unique_id)`.
- Повторно покупали только ~3 тыс. человек — у Olist почти все клиенты разовые.
- Регион покупателя — это регион доставки заказа.

## Пример
```sql
select c.state, count(distinct c.customer_unique_id) as customers, count(*) as orders
from olist.orders as o
join olist.customers as c using (customer_id)
group by 1 order by 3 desc limit 10;
```
