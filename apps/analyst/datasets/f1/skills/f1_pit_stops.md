---
description: пит-стопы в гонках Ф1 (с 2011): круг, длительность
---
# f1.pit_stops — пит-стопы

Датасет Формулы-1 (Ergast) — все чемпионаты мира 1950–2024: 1 125 гонок. Ключи целочисленные (`race_id`, `driver_id`, `constructor_id`), год и этап — в f1.races.

Одна строка — один пит-стоп пилота в гонке (с 2011). Ключ `(race_id, driver_id, stop)`.

## Колонки
| Колонка | Смысл |
| --- | --- |
| race_id / driver_id | → races / drivers |
| stop | номер остановки у пилота в этой гонке |
| lap | на каком круге |
| time | местное время суток остановки |
| duration | длительность текстом: «26.898» или «16:44.718» |
| milliseconds | длительность в мс — для расчётов бери его |

## Подвохи
- Длительность — время проезда пит-лейна целиком (~20–30 с), а не работы механиков.
- Остановки при красном флаге длятся минутами (517 строк с минутами): для типичного
  пит-стопа фильтруй `milliseconds < 60000`.
- Команду пилота бери из f1.results той же гонки (`race_id`, `driver_id`).

## Пример
```sql
select c.name, round(avg(p.milliseconds) / 1000.0, 2) as avg_pit_s, count(*) as stops
from f1.pit_stops as p
join f1.races as r using (race_id)
join f1.results as res using (race_id, driver_id)
join f1.constructors as c on c.constructor_id = res.constructor_id
where r.year = 2024 and p.milliseconds < 60000
group by 1 order by 2;
```
