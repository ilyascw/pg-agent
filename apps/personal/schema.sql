-- Personal assistant built on the core: its data and tool handlers live in schema
-- personal, the agent itself is registered in agent.sql.

create schema personal;

comment on schema personal is 'Personal assistant: tasks, notes and their tools.';

create table personal.task (
    id int generated always as identity primary key,
    title text not null,
    due date,
    done boolean not null default false,
    created_at timestamptz not null default now()
);

create table personal.note (
    id int generated always as identity primary key,
    text text not null,
    tags text[] not null default '{}',
    created_at timestamptz not null default now()
);
