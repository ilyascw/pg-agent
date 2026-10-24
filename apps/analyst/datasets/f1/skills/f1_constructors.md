---
description: команды-конструкторы Ф1: название, национальность
---
# f1.constructors — команды

Датасет Формулы-1 (Ergast) — все чемпионаты мира 1950–2024: 1 125 гонок. Ключи целочисленные (`race_id`, `driver_id`, `constructor_id`), год и этап — в f1.races.

Одна строка — команда (212): Ferrari, McLaren, Red Bull, Mercedes…

## Колонки
| Колонка | Смысл |
| --- | --- |
| constructor_id | ключ |
| constructor_ref | slug: ferrari, red_bull |
| name | название |
| nationality | страна команды |

## Подвохи
- Переименования — разные записи: Toro Rosso / AlphaTauri / RB, Sauber / Alfa Romeo и т. д.
  Если спрашивают про «одну команду» за долгий период — уточни или объедини явно.
- Ищи через `name ilike '%ferrari%'`.

## Пример
```sql
select c.name, count(*) filter (where r.position = 1) as wins
from f1.results as r
join f1.constructors as c using (constructor_id)
group by 1 order by 2 desc limit 10;
```
