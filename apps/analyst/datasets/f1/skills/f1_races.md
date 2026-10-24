---
description: гонки Ф1 1950–2024: год, этап, трасса, дата; ключ для всех результатов
---
# f1.races — гонки (Гран-при)

Датасет Формулы-1 (Ergast) — все чемпионаты мира 1950–2024: 1 125 гонок. Ключи целочисленные (`race_id`, `driver_id`, `constructor_id`), год и этап — в f1.races.

Одна строка — один Гран-при. Почти все остальные таблицы ссылаются сюда по `race_id`,
поэтому фильтр по сезону — всегда через эту таблицу.

## Колонки
| Колонка | Смысл |
| --- | --- |
| race_id | ключ |
| year | сезон → f1.seasons |
| round | номер этапа в сезоне; последний этап = `max(round)` за год |
| circuit_id | → f1.circuits |
| name | «Australian Grand Prix» |
| date, time | дата и время старта (UTC; time пуст до 2005) |
| fp1…fp3, quali, sprint _date/_time | расписание сессий; заполнено только с 2021 |

## Подвохи
- Спринты были в 2021–2024: `sprint_date is not null` (18 гонок), результаты — в f1.sprint_results.
- «Последняя гонка сезона»: `distinct on (year) … order by year, round desc`.

## Пример
```sql
select year, count(*) as races
from f1.races
group by 1 order by 1 desc limit 5;
```
