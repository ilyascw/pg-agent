---
description: координаты бразильских индексов для Olist: zip → широта, долгота, город
---
# olist.geolocation — координаты индексов

Датасет Olist — бразильский маркетплейс, ~99 тыс. заказов с сентября 2016 по октябрь 2018 (полные месяцы — с января 2017 по август 2018). Деньги в бразильских реалах (BRL), время местное, без часового пояса.

~1 млн строк: для каждого 5-значного префикса индекса **много** точек (19 015 префиксов).
Справочник для карт и расстояний.

## Колонки
| Колонка | Смысл |
| --- | --- |
| zip_code_prefix | 5 цифр индекса (текст) = customers/sellers.zip_code_prefix |
| lat, lng | широта и долгота |
| city, state | город и штат |

## Подвохи
- **Не соединяй напрямую** — строки размножатся. Сначала сведи к одной точке на индекс:
  `select zip_code_prefix, avg(lat) as lat, avg(lng) as lng from olist.geolocation group by 1`.
- У 278 покупателей индекса нет в справочнике — используй left join.
- Расстояние в км по прямой (гаверсинус):
  `6371 * 2 * asin(sqrt(sin(radians(lat2-lat1)/2)^2 + cos(radians(lat1))*cos(radians(lat2))*sin(radians(lng2-lng1)/2)^2))`.
- Таблица большая: не делай из неё декартово произведение.

## Пример
```sql
with geo as (
    select zip_code_prefix, avg(lat) as lat, avg(lng) as lng
    from olist.geolocation group by 1
)
select c.state, round(avg(g.lat)::numeric, 2) as lat, round(avg(g.lng)::numeric, 2) as lng
from olist.customers as c
join geo as g using (zip_code_prefix)
group by 1 order by 1;
```
