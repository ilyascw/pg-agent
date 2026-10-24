---
description: трассы Ф1: название, город, страна, координаты
---
# f1.circuits — трассы

Датасет Формулы-1 (Ergast) — все чемпионаты мира 1950–2024: 1 125 гонок. Ключи целочисленные (`race_id`, `driver_id`, `constructor_id`), год и этап — в f1.races.

Одна строка — трасса (77).

## Колонки
| Колонка | Смысл |
| --- | --- |
| circuit_id | ключ → races.circuit_id |
| circuit_ref | slug: monza, monaco |
| name | Autodromo Nazionale di Monza |
| location, country | город и страна |
| lat, lng, alt | координаты и высота, м |

## Подвохи
- Один Гран-при мог проходить на разных трассах в разные годы — для истории трассы
  фильтруй по `circuit_id`, а не по названию гонки.

## Пример
```sql
select c.name, c.country, count(*) as races, min(r.year) as first, max(r.year) as last
from f1.races as r
join f1.circuits as c using (circuit_id)
group by 1, 2 order by 3 desc limit 10;
```
