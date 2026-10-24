begin;

select plan(9);

insert into skills.skill (library, name, description, content) values
('lib', 'beta', 'второй', 'B'),
('lib', 'alpha', 'первый', 'A'),
('other', 'gamma', 'чужой', 'G');

select is(
    skills.catalog('{"system": "base", "events": []}', '{"library": "lib", "title": "Скиллы:"}'),
    $${"system": "base\n\nСкиллы:\n- alpha — первый\n- beta — второй", "events": []}$$::jsonb,
    'catalog lists only its library, sorted, under the title'
);

select is(
    skills.catalog('{"system": "base"}', '{"library": "empty"}'),
    '{"system": "base"}',
    'empty library leaves the prompt as it is'
);

select is(skills.load('{"name": " Alpha "}', '{"library": "lib"}'), 'A', 'load by name');

select matches(
    skills.load('{"name": "gamma"}', '{"library": "lib"}'),
    'не найден.*alpha',
    'other libraries are invisible; the miss lists what exists'
);

select is(
    skills.save('{"name": "x", "content": "short"}', '{"library": "lib"}'),
    'Слишком короткая методичка. Скилл должен объяснять, когда применяться, '
    || 'в каком порядке работать, что проверить и как оформить ответ.',
    'short skills are rejected'
);

select is(
    skills.save(
        jsonb_build_object(
            'name', 'Meeting Notes', 'content', e'# Протокол встречи\n' || repeat('шаг ', 60)
        ),
        '{"library": "lib"}'
    ),
    'Скилл «meeting_notes» создан. Загружай его через load_skill("meeting_notes").',
    'names are normalised'
);

select is(
    (
        select description from skills.skill
        where library = 'lib' and name = 'meeting_notes'
    ),
    'Протокол встречи',
    'description defaults to the first line'
);

select is(
    skills.import('fixtures', '/work/plugins/skills/tests/fixtures'),
    1,
    'import loads .md files only'
);

select is(
    (
        select description || ' / ' || content from skills.skill
        where library = 'fixtures'
    ),
    e'заказы магазина / # orders\n\nОдна строка — один заказ.',
    'front matter becomes the description, the rest is the content'
);

select * from finish();

rollback;
