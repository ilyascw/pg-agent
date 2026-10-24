---
description: платежи по заказам Olist: способ оплаты, рассрочка, сумма
---
# olist.order_payments — платежи

Датасет Olist — бразильский маркетплейс, ~99 тыс. заказов с сентября 2016 по октябрь 2018 (полные месяцы — с января 2017 по август 2018). Деньги в бразильских реалах (BRL), время местное, без часового пояса.

Одна строка — один платёж. Заказ можно оплатить несколькими платежами (например, карта
+ ваучеры), `payment_seq` — их номер, до 29. Ключ `(order_id, payment_seq)`.

## Колонки
| Колонка | Смысл |
| --- | --- |
| order_id | → olist.orders |
| payment_seq | номер платежа в заказе |
| payment_type | credit_card (~77 тыс.), boleto (банковский счёт, ~20 тыс.), voucher, debit_card, not_defined (3) |
| installments | на сколько частей рассрочка; >1 только у credit_card, до 24 |
| value | сумма платежа, BRL |

## Подвохи
- Сумма платежей заказа ≈ `sum(price + freight_value)` из order_items, расходится у ~260 заказов.
- Не соединяй с order_items напрямую — суммы задвоятся. Сначала агрегируй по `order_id`.
- Доля способа оплаты по заказам ≠ доля по платежам: у заказа бывает несколько платежей.
- 9 платежей с `value = 0`.

## Пример
```sql
select payment_type, count(distinct order_id) as orders, sum(value) as amount,
       round(avg(installments) filter (where payment_type = 'credit_card'), 1) as avg_installments
from olist.order_payments
group by 1 order by 3 desc;
```
