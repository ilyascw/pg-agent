---
description: отзывы покупателей Olist: оценка 1–5 и текст на португальском
---
# olist.order_reviews — отзывы

Датасет Olist — бразильский маркетплейс, ~99 тыс. заказов с сентября 2016 по октябрь 2018 (полные месяцы — с января 2017 по август 2018). Деньги в бразильских реалах (BRL), время местное, без часового пояса.

Одна строка — отзыв на заказ. Покупатель получает опрос после доставки или после
обещанной даты. Ключ `(review_id, order_id)`.

## Колонки
| Колонка | Смысл |
| --- | --- |
| review_id | id отзыва; не уникален сам по себе |
| order_id | → olist.orders |
| score | оценка 1–5; 5 — 58%, 1 — 12% |
| comment_title | заголовок, есть у ~12% |
| comment_message | текст, есть у ~41%; **на португальском** |
| created_at | когда отправлен опрос |
| answered_at | когда покупатель ответил |

## Подвохи
- У 547 заказов больше одного отзыва, у 768 — ни одного. Средняя оценка по заказам:
  сначала `avg(score)` по `order_id`, потом среднее.
- Тексты на португальском, имена магазинов заменены на дома из «Игры престолов»
  (lannister, stark…). Ищи по словам через `ilike`, например `'%atras%'` — задержка,
  `'%não recebi%'` — не получил.
- Связь оценки с опозданием: соединяй с olist.orders и сравнивай
  `delivered_customer_at` с `estimated_delivery_at`.

## Пример
```sql
select (o.delivered_customer_at > o.estimated_delivery_at) as late,
       round(avg(r.score), 2) as avg_score, count(*) as reviews
from olist.order_reviews as r
join olist.orders as o using (order_id)
where o.status = 'delivered' and o.delivered_customer_at is not null
group by 1;
```
