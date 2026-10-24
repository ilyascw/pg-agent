---
description: результаты спринтов Ф1 (2021–2024): место, очки
---
# f1.sprint_results — спринты

Датасет Формулы-1 (Ergast) — все чемпионаты мира 1950–2024: 1 125 гонок. Ключи целочисленные (`race_id`, `driver_id`, `constructor_id`), год и этап — в f1.races.

Одна строка — пилот в спринте (короткая гонка в субботу), 2021–2024, 18 спринтов.
Колонки как в f1.results, но без `rank` и `fastest_lap_speed`.

## Колонки
| Колонка | Смысл |
| --- | --- |
| race_id | Гран-при, к которому относится спринт → f1.races |
| driver_id / constructor_id | → drivers / constructors |
| grid, position, position_text, position_order | как в f1.results |
| points | очки за спринт |
| laps, time, milliseconds, fastest_lap, fastest_lap_time | как в f1.results |
| status_id | → f1.status |

## Подвохи
- Очки пилота за уик-энд = results.points + sprint_results.points.
- Победы в спринтах обычно не считают победами в Гран-при — разделяй.

## Пример
```sql
select d.surname, sum(s.points) as sprint_points, count(*) filter (where s.position = 1) as sprint_wins
from f1.sprint_results as s
join f1.drivers as d using (driver_id)
group by 1 order by 2 desc limit 10;
```
