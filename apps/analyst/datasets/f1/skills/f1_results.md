---
description: результаты гонок Ф1: место, очки, старт, круги, сход, быстрый круг
---
# f1.results — результаты гонок

Датасет Формулы-1 (Ergast) — все чемпионаты мира 1950–2024: 1 125 гонок. Ключи целочисленные (`race_id`, `driver_id`, `constructor_id`), год и этап — в f1.races.

Одна строка — один пилот в одной гонке (26 759). Главная таблица для побед, подиумов,
очков за гонку и сходов.

## Колонки
| Колонка | Смысл |
| --- | --- |
| race_id / driver_id / constructor_id | → races / drivers / constructors |
| grid | стартовая позиция; 0 — старт с пит-лейна |
| position | финишное место; **null, если не классифицирован** |
| position_text | место текстом или код: R — сход, D — дисквалификация, E — исключён, W — снялся, F — не прошёл квалификацию, N — не классифицирован |
| position_order | порядок в протоколе для всех, без null — сортируй по нему |
| points | очки за эту гонку (без спринта) |
| laps | пройдено кругов |
| time | у победителя — время гонки, у остальных — отставание «+5.478»; текст |
| milliseconds | полное время гонки в мс |
| fastest_lap, rank, fastest_lap_time, fastest_lap_speed | быстрый круг; есть с 2004 |
| status_id | → f1.status: Finished, +1 Lap, Engine, Accident… |

## Подвохи
- Победа: `position = 1`; подиум: `position <= 3`.
- **Очки за сезон не равны `sum(points)`**: в старых сезонах в зачёт шли не все гонки,
  а с 2021 есть спринты. Итог чемпионата бери из f1.driver_standings / f1.constructor_standings.
- Сход: `position is null`, причину смотри в f1.status.
- Пилот может проехать гонку за две команды (редко, 1950-е) — строк будет две.

## Пример
```sql
select d.forename || ' ' || d.surname as driver, count(*) as wins
from f1.results as r
join f1.drivers as d using (driver_id)
where r.position = 1
group by 1 order by 2 desc limit 10;
```
