-- Time and arithmetic.

-- Uses the session time zone, so each connector reports the user's local time.
create function personal.current_datetime(
    p_arguments jsonb, p_options jsonb default '{}'
) returns text
language sql stable
as $$
    select to_char(now(), 'YYYY-MM-DD HH24:MI TZ (FMDay)')
$$;

-- Evaluates numbers, + - * / ^ ** and parentheses as exact numeric arithmetic.
create function personal.calculate(
    p_arguments jsonb, p_options jsonb default '{}'
) returns text
language plpgsql stable
as $$
declare
    v_expression text := replace(p_arguments ->> 'expression', '**', '^');
    v_result numeric;
begin
    if length(v_expression) > 1000 then
        return 'Ошибка вычисления: слишком длинное выражение';
    end if;
    if v_expression !~ '^[0-9.+*/^() -]+$' then
        return 'Ошибка вычисления: разрешены только числа, скобки и операции + - * / **';
    end if;

    -- Literals become numeric so 1/3 is not integer division.
    execute format(
        'select (%s)::numeric',
        regexp_replace(v_expression, '([0-9]+(\.[0-9]+)?)', '\1::numeric', 'g')
    ) into v_result;
    return trim_scale(v_result)::text;
exception
    when data_exception or syntax_error then
        return 'Ошибка вычисления: ' || sqlerrm;
end
$$;
