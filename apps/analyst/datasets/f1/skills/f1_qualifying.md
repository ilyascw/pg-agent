---
description: квалификация Ф1 (с 1994): позиция и время в Q1, Q2, Q3
---
# f1.qualifying — квалификация

Датасет Формулы-1 (Ergast) — все чемпионаты мира 1950–2024: 1 125 гонок. Ключи целочисленные (`race_id`, `driver_id`, `constructor_id`), год и этап — в f1.races.

Одна строка — пилот в квалификации одной гонки. Данные с 1994.

## Колонки
| Колонка | Смысл |
| --- | --- |
| race_id / driver_id / constructor_id | → races / drivers / constructors |
| number | номер машины |
| position | итог квалификации |
| q1, q2, q3 | лучшее время в сегменте, **текст** «1:26.572»; q2/q3 пусты, если пилот выбыл раньше или формата не было (до 2006 только q1) |

## Подвохи
- Поул: `position = 1`.
- Стартовая позиция может отличаться из-за штрафов — она в f1.results.grid.
- Время в секунды: `split_part(q1, ':', 1)::int * 60 + split_part(q1, ':', 2)::numeric`
  (только если `q1 like '%:%'`).

## Пример
```sql
select d.surname, count(*) as poles
from f1.qualifying as q
join f1.drivers as d using (driver_id)
where q.position = 1
group by 1 order by 2 desc limit 10;
```
