---
description: справочник статусов финиша Ф1: Finished, +1 Lap, причины схода
---
# f1.status — статусы финиша

Датасет Формулы-1 (Ergast) — все чемпионаты мира 1950–2024: 1 125 гонок. Ключи целочисленные (`race_id`, `driver_id`, `constructor_id`), год и этап — в f1.races.

Справочник (139 строк) для `results.status_id` и `sprint_results.status_id`.

## Колонки
| Колонка | Смысл |
| --- | --- |
| status_id | ключ |
| status | Finished, «+1 Lap», «+2 Laps»… — финишировал с отставанием в круги; Engine, Gearbox, Accident, Collision… — причина схода; Disqualified; Did not qualify |

## Подвохи
- Финишировал: `status = 'Finished' or status like '+%Lap%'`.
- Технический сход vs авария — группируй статусы явно, общего признака нет.

## Пример
```sql
select s.status, count(*) as results
from f1.results as r
join f1.status as s using (status_id)
join f1.races as ra using (race_id)
where ra.year >= 2014 and r.position is null
group by 1 order by 2 desc limit 10;
```
