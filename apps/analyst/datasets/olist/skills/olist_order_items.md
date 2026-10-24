---
description: позиции заказов Olist: товар, продавец, цена и стоимость доставки — основа выручки
---
# olist.order_items — позиции заказа

Датасет Olist — бразильский маркетплейс, ~99 тыс. заказов с сентября 2016 по октябрь 2018 (полные месяцы — с января 2017 по август 2018). Деньги в бразильских реалах (BRL), время местное, без часового пояса.

Одна строка — одна единица товара в заказе. Если в заказе 3 одинаковых товара, будет
3 строки с `item_seq` = 1, 2, 3. Ключ `(order_id, item_seq)`.

## Колонки
| Колонка | Смысл |
| --- | --- |
| order_id | → olist.orders |
| item_seq | номер позиции в заказе, до 21 |
| product_id | → olist.products |
| seller_id | → olist.sellers; в одном заказе могут быть разные продавцы |
| shipping_limit_at | крайний срок передачи в доставку для продавца |
| price | цена единицы, BRL (0.85 … 6 735, в среднем ~121) |
| freight_value | стоимость доставки этой позиции, BRL |

## Подвохи
- **Выручку считай здесь:** `sum(price)` — товары, `sum(price + freight_value)` — с доставкой.
- **Никогда не соединяй с olist.order_payments напрямую** — у заказа бывает несколько
  платежей, строки размножатся и суммы задвоятся. Нужны обе — агрегируй каждую по
  `order_id` отдельно, потом соединяй.
- Количество товаров = `count(*)`, отдельной колонки quantity нет.
- У 775 заказов нет позиций (в основном canceled/unavailable).
- Выручку обычно считают по `orders.status = 'delivered'`.

## Пример
```sql
select t.category_english, sum(i.price) as revenue, count(*) as items
from olist.order_items as i
join olist.orders as o using (order_id)
join olist.products as p using (product_id)
left join olist.category_translation as t using (category)
where o.status = 'delivered'
group by 1 order by 2 desc limit 10;
```
