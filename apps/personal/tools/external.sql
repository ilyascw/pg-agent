-- Weather and exchange rates from public HTTP APIs.

create function personal.http_json(p_url text) returns jsonb
language plpgsql
as $$
declare
    v_response public.http_response;
begin
    -- curl options are per session, so set both: the connect timeout defaults to 1 second.
    -- Some public APIs drop a connection now and then and answer the next one at once,
    -- so a short connect timeout with retries beats one long wait.
    perform public.http_set_curlopt('CURLOPT_CONNECTTIMEOUT', '3');
    perform public.http_set_curlopt('CURLOPT_TIMEOUT', '30');
    for v_attempt in 1..3 loop
        begin
            v_response := public.http_get(p_url);
            exit;
        exception when others then
            if v_attempt = 3 then
                raise;
            end if;
        end;
    end loop;
    if v_response.status <> 200 then
        raise exception 'HTTP % from %', v_response.status, p_url;
    end if;
    return v_response.content::jsonb;
end
$$;

create function personal.get_weather(
    p_arguments jsonb, p_options jsonb default '{}'
) returns text
language plpgsql
as $$
declare
    v_city text := p_arguments ->> 'city';
    v_now jsonb := personal.http_json(
        'https://wttr.in/' || public.urlencode(v_city) || '?format=j1&lang=ru'
    ) -> 'current_condition' -> 0;
begin
    return format(
        '%s: %s°C (ощущается %s°C), %s, ветер %s км/ч, влажность %s%%',
        v_city,
        v_now ->> 'temp_C',
        v_now ->> 'FeelsLikeC',
        coalesce(v_now -> 'lang_ru' -> 0 ->> 'value', v_now -> 'weatherDesc' -> 0 ->> 'value'),
        v_now ->> 'windspeedKmph',
        v_now ->> 'humidity'
    );
end
$$;

create function personal.get_currency_rate(
    p_arguments jsonb, p_options jsonb default '{}'
) returns text
language plpgsql
as $$
declare
    v_code text := upper(coalesce(p_arguments ->> 'code', 'USD'));
    v_data jsonb := personal.http_json('https://www.cbr-xml-daily.ru/daily_json.js');
    v_rate jsonb := v_data -> 'Valute' -> v_code;
begin
    if v_rate is null then
        return format(
            'Валюта %s не найдена. Доступны: %s',
            v_code,
            (select string_agg(k.code, ', ' order by k.code) from jsonb_object_keys(v_data -> 'Valute') as k (code))
        );
    end if;
    return format(
        '%s (%s): %s ₽ за %s (вчера %s ₽), дата %s',
        v_rate ->> 'Name',
        v_rate ->> 'CharCode',
        round((v_rate ->> 'Value')::numeric, 4),
        v_rate ->> 'Nominal',
        round((v_rate ->> 'Previous')::numeric, 4),
        left(v_data ->> 'Date', 10)
    );
end
$$;
