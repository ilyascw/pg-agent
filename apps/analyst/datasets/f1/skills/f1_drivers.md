---
description: пилоты Ф1: имя, фамилия, код, номер, дата рождения, национальность
---
# f1.drivers — пилоты

Датасет Формулы-1 (Ergast) — все чемпионаты мира 1950–2024: 1 125 гонок. Ключи целочисленные (`race_id`, `driver_id`, `constructor_id`), год и этап — в f1.races.

Одна строка — пилот (861).

## Колонки
| Колонка | Смысл |
| --- | --- |
| driver_id | ключ |
| driver_ref | slug: hamilton, max_verstappen |
| number | постоянный номер; null у большинства старых пилотов |
| code | трёхбуквенный код: HAM, VER; null у старых |
| forename, surname | имя и фамилия латиницей, с диакритикой (Räikkönen) |
| dob | дата рождения |
| nationality | British, German… |

## Подвохи
- Ищи пилота по фамилии через `ilike`: `surname ilike '%verstappen%'`. Есть однофамильцы
  (Schumacher — Михаэль, Ральф, Мик): уточняй по имени.
- Возраст на гонке: `age(r.date, d.dob)`.
- Команда пилота — не здесь, а в f1.results.constructor_id конкретной гонки.

## Пример
```sql
select driver_id, forename, surname, code, dob, nationality
from f1.drivers
where surname ilike '%hamilton%';
```
