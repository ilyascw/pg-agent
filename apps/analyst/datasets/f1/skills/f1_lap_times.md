---
description: время каждого круга каждого пилота в гонках Ф1 (с 1996), ~590 тыс. строк
---
# f1.lap_times — круги

Датасет Формулы-1 (Ergast) — все чемпионаты мира 1950–2024: 1 125 гонок. Ключи целочисленные (`race_id`, `driver_id`, `constructor_id`), год и этап — в f1.races.

Одна строка — один круг одного пилота в гонке (~589 тыс.), с 1996.
Ключ `(race_id, driver_id, lap)`.

## Колонки
| Колонка | Смысл |
| --- | --- |
| race_id / driver_id | → races / drivers |
| lap | номер круга |
| position | позиция пилота после этого круга |
| time | время круга текстом «1:38.109» |
| milliseconds | время круга в мс — для расчётов бери его |

## Подвохи
- Таблица большая: всегда фильтруй по гонке или сезону через f1.races.
- Круги с пит-стопом и под сейфти-каром медленные — для «темпа» бери медиану:
  `percentile_cont(0.5) within group (order by milliseconds)`.
- Минуты и секунды: `milliseconds / 1000.0`.

## Пример
```sql
select d.surname, min(l.milliseconds) / 1000.0 as best_lap_s,
       percentile_cont(0.5) within group (order by l.milliseconds) / 1000.0 as median_lap_s
from f1.lap_times as l
join f1.races as r using (race_id)
join f1.drivers as d using (driver_id)
where r.year = 2024 and r.name = 'Monaco Grand Prix'
group by 1 order by 3 limit 10;
```
