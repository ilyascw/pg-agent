-- Which session each Telegram chat talks in. Owned by the Telegram connector and safe
-- to apply again: make telegram applies it before starting the bot.

create schema if not exists telegram;

create table if not exists telegram.chat (
    chat_id bigint not null,
    agent text not null references runtime.agent on delete cascade,
    stream_id uuid not null references core.stream on delete cascade,
    primary key (chat_id, agent)
);
