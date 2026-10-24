begin;

select plan(16);

select is(personal.calculate('{"expression": "(2026-1990)*12"}'), '432', 'integer arithmetic');
select is(personal.calculate('{"expression": "1/4"}'), '0.25', 'division is not integer division');
select is(
    personal.calculate('{"expression": "100000 * 1.12 ** 5"}'),
    '176234.16832',
    'power with ** is exact'
);
select is(
    personal.calculate('{"expression": "select 1"}'),
    'Ошибка вычисления: разрешены только числа, скобки и операции + - * / **',
    'anything but arithmetic is rejected before execution'
);
select matches(
    personal.calculate('{"expression": "1/0"}'),
    '^Ошибка вычисления: division by zero',
    'arithmetic errors are reported, not raised'
);
select matches(personal.calculate('{"expression": "2 ** 1000000000"}'), '^Ошибка', 'overflow');
select matches(personal.calculate('{"expression": "(1"}'), '^Ошибка', 'syntax error');

select is(
    personal.add_task('{"title": "купить билеты", "due": "2026-10-26"}'),
    format(
        'Задача #%s добавлена: купить билеты (до 2026-10-26)',
        currval(pg_get_serial_sequence('personal.task', 'id'))
    ),
    'add task with due date'
);
select personal.add_task('{"title": "позвонить"}');
select personal.complete_task(
    jsonb_build_object('task_id', (select min(id) from personal.task))
);
select is(
    personal.list_tasks('{}'),
    format('#%s [ ] позвонить', (select max(id) from personal.task)),
    'done tasks are hidden'
);
select is(
    personal.complete_task('{"task_id": -1}'),
    'Задача #-1 не найдена.',
    'unknown task'
);

select personal.save_note('{"text": "Семчик — ореховый магнат", "tags": "люди, , бизнес"}');
select is((select tags from personal.note), array['люди', 'бизнес'], 'empty tags are dropped');
select matches(
    personal.search_notes('{"query": "СЕМЧИК"}'),
    'Семчик — ореховый магнат$',
    'case-insensitive search'
);
select matches(personal.search_notes('{"query": "бизн"}'), 'Семчик', 'search by tag');
select is(personal.search_notes('{"query": "кузя"}'), 'Ничего не нашлось.', 'nothing found');

select is(
    personal.save_skill('{"name": "Meeting Notes", "content": "short"}'),
    'Слишком короткая методичка. Скилл должен объяснять, когда применяться, '
    || 'в каком порядке работать, что проверить и как оформить ответ.',
    'short skills are rejected'
);
select is(
    personal.save_skill(jsonb_build_object('name', 'Meeting Notes', 'content', repeat('шаг ', 60))),
    'Скилл «meeting_notes» создан. Загружай его через load_skill("meeting_notes").',
    'skill names are normalised'
);

select * from finish();

rollback;
