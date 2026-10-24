-- Formula 1 dataset 1950–2024 (Ergast): tables, data from data/f1 (make data downloads
-- it), read access for run_sql and one skill per table. Needs the analyst app.
\set ON_ERROR_STOP on

begin;

create schema f1;

comment on schema f1 is 'Формула-1 1950–2024: гонки, пилоты, команды, результаты, круги.';

create table f1.seasons (
    year int primary key,
    url text not null
);

create table f1.status (
    status_id int primary key,
    status text not null
);

create table f1.circuits (
    circuit_id int primary key,
    circuit_ref text not null,
    name text not null,
    location text not null,
    country text not null,
    lat double precision not null,
    lng double precision not null,
    alt int,
    url text not null
);

create table f1.drivers (
    driver_id int primary key,
    driver_ref text not null,
    number int,
    code text,
    forename text not null,
    surname text not null,
    dob date,
    nationality text not null,
    url text not null
);

create table f1.constructors (
    constructor_id int primary key,
    constructor_ref text not null,
    name text not null,
    nationality text not null,
    url text not null
);

create table f1.races (
    race_id int primary key,
    year int not null references f1.seasons,
    round int not null,
    circuit_id int not null references f1.circuits,
    name text not null,
    date date not null,
    time time,
    url text,
    fp1_date date,
    fp1_time time,
    fp2_date date,
    fp2_time time,
    fp3_date date,
    fp3_time time,
    quali_date date,
    quali_time time,
    sprint_date date,
    sprint_time time
);

create table f1.results (
    result_id int primary key,
    race_id int not null references f1.races,
    driver_id int not null references f1.drivers,
    constructor_id int not null references f1.constructors,
    number int,
    grid int not null,
    position int,
    position_text text not null,
    position_order int not null,
    points numeric not null,
    laps int not null,
    time text,
    milliseconds bigint,
    fastest_lap int,
    rank int,
    fastest_lap_time text,
    fastest_lap_speed numeric,
    status_id int not null references f1.status
);

create table f1.sprint_results (
    result_id int primary key,
    race_id int not null references f1.races,
    driver_id int not null references f1.drivers,
    constructor_id int not null references f1.constructors,
    number int not null,
    grid int not null,
    position int,
    position_text text not null,
    position_order int not null,
    points numeric not null,
    laps int not null,
    time text,
    milliseconds bigint,
    fastest_lap int,
    fastest_lap_time text,
    status_id int not null references f1.status
);

create table f1.qualifying (
    qualify_id int primary key,
    race_id int not null references f1.races,
    driver_id int not null references f1.drivers,
    constructor_id int not null references f1.constructors,
    number int not null,
    position int not null,
    q1 text,
    q2 text,
    q3 text
);

create table f1.lap_times (
    race_id int not null references f1.races,
    driver_id int not null references f1.drivers,
    lap int not null,
    position int not null,
    time text not null,
    milliseconds int not null,
    primary key (race_id, driver_id, lap)
);

create table f1.pit_stops (
    race_id int not null references f1.races,
    driver_id int not null references f1.drivers,
    stop int not null,
    lap int not null,
    time time not null,
    duration text not null,
    milliseconds int not null,
    primary key (race_id, driver_id, stop)
);

create table f1.driver_standings (
    driver_standings_id int primary key,
    race_id int not null references f1.races,
    driver_id int not null references f1.drivers,
    points numeric not null,
    position int not null,
    position_text text not null,
    wins int not null
);

create table f1.constructor_standings (
    constructor_standings_id int primary key,
    race_id int not null references f1.races,
    constructor_id int not null references f1.constructors,
    points numeric not null,
    position int not null,
    position_text text not null,
    wins int not null
);

create table f1.constructor_results (
    constructor_results_id int primary key,
    race_id int not null references f1.races,
    constructor_id int not null references f1.constructors,
    points numeric not null,
    status text
);

copy f1.seasons from '/work/data/f1/seasons.csv' with (format csv, header true, null '\N');
copy f1.status from '/work/data/f1/status.csv' with (format csv, header true, null '\N');
copy f1.circuits from '/work/data/f1/circuits.csv' with (format csv, header true, null '\N');
copy f1.drivers from '/work/data/f1/drivers.csv' with (format csv, header true, null '\N');
copy f1.constructors
from '/work/data/f1/constructors.csv' with (format csv, header true, null '\N');
copy f1.races from '/work/data/f1/races.csv' with (format csv, header true, null '\N');
copy f1.results from '/work/data/f1/results.csv' with (format csv, header true, null '\N');
copy f1.sprint_results
from '/work/data/f1/sprint_results.csv' with (format csv, header true, null '\N');
copy f1.qualifying from '/work/data/f1/qualifying.csv' with (format csv, header true, null '\N');
copy f1.lap_times from '/work/data/f1/lap_times.csv' with (format csv, header true, null '\N');
copy f1.pit_stops from '/work/data/f1/pit_stops.csv' with (format csv, header true, null '\N');
copy f1.driver_standings
from '/work/data/f1/driver_standings.csv' with (format csv, header true, null '\N');
copy f1.constructor_standings
from '/work/data/f1/constructor_standings.csv' with (format csv, header true, null '\N');
copy f1.constructor_results
from '/work/data/f1/constructor_results.csv' with (format csv, header true, null '\N');

create index on f1.races (year);
create index on f1.results (race_id);
create index on f1.results (driver_id);
create index on f1.results (constructor_id);
create index on f1.sprint_results (race_id);
create index on f1.qualifying (race_id);
create index on f1.lap_times (driver_id);
create index on f1.driver_standings (race_id);
create index on f1.constructor_standings (race_id);
create index on f1.constructor_results (race_id);

grant usage on schema f1 to analyst_reader;
grant select on all tables in schema f1 to analyst_reader;

select skills.import('analyst', '/work/apps/analyst/datasets/f1/skills');

commit;

analyze f1.seasons, f1.status, f1.circuits, f1.drivers, f1.constructors, f1.races, f1.results,
f1.sprint_results, f1.qualifying, f1.lap_times, f1.pit_stops, f1.driver_standings,
f1.constructor_standings, f1.constructor_results;
