---
description: очки команды Ф1 за каждую гонку (с 1958)
---
# f1.constructor_results — очки команд за гонку

Датасет Формулы-1 (Ergast) — все чемпионаты мира 1950–2024: 1 125 гонок. Ключи целочисленные (`race_id`, `driver_id`, `constructor_id`), год и этап — в f1.races.

Одна строка — сколько очков команда набрала в одной гонке (с 1958).

## Колонки
| Колонка | Смысл |
| --- | --- |
| race_id | → f1.races |
| constructor_id | → f1.constructors |
| points | очки команды за гонку |
| status | почти всегда пусто; D — дисквалификация (17 строк) |

## Подвохи
- Для итогов сезона используй f1.constructor_standings — правила зачёта менялись.
- Удобно для «очки команды по гонкам сезона» без суммирования пилотов.

## Пример
```sql
select r.round, r.name, cr.points
from f1.constructor_results as cr
join f1.races as r using (race_id)
join f1.constructors as c using (constructor_id)
where r.year = 2024 and c.name = 'McLaren'
order by r.round;
```
