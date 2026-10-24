---
description: личный зачёт Ф1 после каждой гонки: очки, место, победы — итог чемпионата
---
# f1.driver_standings — личный зачёт

Датасет Формулы-1 (Ergast) — все чемпионаты мира 1950–2024: 1 125 гонок. Ключи целочисленные (`race_id`, `driver_id`, `constructor_id`), год и этап — в f1.races.

Одна строка — положение пилота в чемпионате **после** конкретной гонки (нарастающим
итогом). Это правильный источник для чемпионов и очков за сезон.

## Колонки
| Колонка | Смысл |
| --- | --- |
| race_id | после какой гонки → f1.races |
| driver_id | → f1.drivers |
| points | очки в чемпионате на этот момент, с учётом спринтов и правил зачёта эпохи |
| position | место в чемпионате |
| wins | побед на этот момент |

## Подвохи
- **Итог сезона = строки последней гонки сезона**, не сумма по гонкам.
- Чемпион года: position = 1 на последнем этапе.

## Пример
```sql
with last_race as (
    select distinct on (year) race_id, year
    from f1.races
    where race_id in (select race_id from f1.driver_standings)
    order by year, round desc
)
select l.year, d.forename || ' ' || d.surname as champion, s.points, s.wins
from last_race as l
join f1.driver_standings as s using (race_id)
join f1.drivers as d using (driver_id)
where s.position = 1
order by l.year desc limit 10;
```
