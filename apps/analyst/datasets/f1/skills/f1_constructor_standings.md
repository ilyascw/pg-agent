---
description: кубок конструкторов Ф1 после каждой гонки (с 1958): очки, место, победы
---
# f1.constructor_standings — кубок конструкторов

Датасет Формулы-1 (Ergast) — все чемпионаты мира 1950–2024: 1 125 гонок. Ключи целочисленные (`race_id`, `driver_id`, `constructor_id`), год и этап — в f1.races.

Одна строка — положение команды в кубке конструкторов **после** конкретной гонки,
нарастающим итогом. Кубок разыгрывается с 1958.

## Колонки
| Колонка | Смысл |
| --- | --- |
| race_id | после какой гонки → f1.races |
| constructor_id | → f1.constructors |
| points | очки на этот момент |
| position | место |
| wins | победы на этот момент |

## Подвохи
- Итог сезона — строки последней гонки сезона (как в f1.driver_standings).
- До 1958 кубка нет — данных тоже.

## Пример
```sql
with last_race as (
    select distinct on (year) race_id, year from f1.races
    where race_id in (select race_id from f1.constructor_standings)
    order by year, round desc
)
select l.year, c.name, s.points
from last_race as l
join f1.constructor_standings as s using (race_id)
join f1.constructors as c using (constructor_id)
where s.position = 1 order by l.year desc limit 10;
```
