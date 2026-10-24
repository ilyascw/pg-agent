---
description: товары Olist: категория (на португальском), вес, габариты, фото
---
# olist.products — товары

Датасет Olist — бразильский маркетплейс, ~99 тыс. заказов с сентября 2016 по октябрь 2018 (полные месяцы — с января 2017 по август 2018). Деньги в бразильских реалах (BRL), время местное, без часового пояса.

Одна строка — товар (32 951). Названий товаров нет, только категория и физические
параметры.

## Колонки
| Колонка | Смысл |
| --- | --- |
| product_id | ключ → order_items.product_id |
| category | категория **на португальском**: cama_mesa_banho, beleza_saude…; null у 610 |
| name_length, description_length | длина названия и описания в символах |
| photos_qty | число фото в карточке |
| weight_g | вес, граммы |
| length_cm, height_cm, width_cm | габариты, см |

## Подвохи
- Английское название категории — через olist.category_translation по `category`
  (left join: у 2 категорий перевода нет, у 610 товаров категория пустая).
- Продажи товара — из olist.order_items, а не отсюда.
- Объём: `length_cm * height_cm * width_cm`.

## Пример
```sql
select coalesce(t.category_english, p.category, 'unknown') as category,
       count(*) as products, round(avg(p.weight_g)) as avg_weight_g
from olist.products as p
left join olist.category_translation as t using (category)
group by 1 order by 2 desc limit 10;
```
