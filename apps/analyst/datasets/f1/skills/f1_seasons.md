---
description: сезоны Ф1 1950–2024: год и ссылка на Википедию
---
# f1.seasons — сезоны

Датасет Формулы-1 (Ergast) — все чемпионаты мира 1950–2024: 1 125 гонок. Ключи целочисленные (`race_id`, `driver_id`, `constructor_id`), год и этап — в f1.races.

Одна строка — сезон (75): `year` и `url` на Википедию. Полезна мало: год уже есть в
f1.races. Нужна только как полный список лет.

## Колонки
| Колонка | Смысл |
| --- | --- |
| year | сезон, ключ → races.year |
| url | статья в английской Википедии |

## Пример
```sql
select s.year, count(r.race_id) as races
from f1.seasons as s
left join f1.races as r using (year)
group by 1 order by 1 desc limit 5;
```
