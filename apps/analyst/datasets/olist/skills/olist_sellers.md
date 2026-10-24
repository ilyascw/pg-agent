---
description: продавцы Olist: город, штат, индекс
---
# olist.sellers — продавцы

Датасет Olist — бразильский маркетплейс, ~99 тыс. заказов с сентября 2016 по октябрь 2018 (полные месяцы — с января 2017 по август 2018). Деньги в бразильских реалах (BRL), время местное, без часового пояса.

Одна строка — продавец (3 095) на маркетплейсе. Продажи продавца — через
olist.order_items по `seller_id`.

## Колонки
| Колонка | Смысл |
| --- | --- |
| seller_id | ключ → order_items.seller_id |
| zip_code_prefix | 5 цифр индекса → olist.geolocation |
| city | город строчными, без диакритики |
| state | штат, 2 буквы; большинство продавцов в SP |

## Подвохи
- В одном заказе могут быть товары разных продавцов: «заказы продавца» =
  `count(distinct order_id)` по его позициям.
- Оценки продавца — через order_items → order_reviews по `order_id`; если в заказе
  несколько продавцов, отзыв достаётся всем.

## Пример
```sql
select s.seller_id, s.state, count(distinct i.order_id) as orders, sum(i.price) as revenue
from olist.order_items as i
join olist.sellers as s using (seller_id)
group by 1, 2 order by 4 desc limit 10;
```
