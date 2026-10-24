---
description: перевод категорий товаров Olist с португальского на английский
---
# olist.category_translation — перевод категорий

Датасет Olist — бразильский маркетплейс, ~99 тыс. заказов с сентября 2016 по октябрь 2018 (полные месяцы — с января 2017 по август 2018). Деньги в бразильских реалах (BRL), время местное, без часового пояса.

71 строка: португальское название категории → английское.

## Колонки
| Колонка | Смысл |
| --- | --- |
| category | как в olist.products.category: beleza_saude |
| category_english | health_beauty |

## Подвохи
- Соединяй через **left join**: у категорий `pc_gamer` и
  `portateis_cozinha_e_preparadores_de_alimentos` перевода нет.
- В ответе пользователю переводи категории на русский сам, по смыслу английского названия.

## Пример
```sql
select p.category, t.category_english
from (select distinct category from olist.products) as p
left join olist.category_translation as t using (category)
order by 1;
```
