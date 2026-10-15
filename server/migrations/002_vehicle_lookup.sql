-- Прокси поиска машины по госномеру и рыночной оценки (решение 14.10.2026).
--
-- Платный токен поставщика живёт только на сервере. Телефон ходит сюда с
-- токеном установки — случайным, без согласия и без персональных данных:
-- он нужен, чтобы считать лимиты, а не чтобы знать человека.
-- Госномер и VIN сервер не хранит: в журнале только факт запроса и исход.

create table installs (
  id uuid primary key,
  token_hash text not null unique,
  created_at timestamptz not null default now(),
  last_seen_at timestamptz,
  revoked_at timestamptz
);

create table lookup_log (
  id bigserial primary key,
  at timestamptz not null default now(),
  install_id uuid,
  -- plate | price
  kind text not null,
  -- found | not_found | unavailable | limited
  outcome text not null
);
create index lookup_log_at on lookup_log(at);
create index lookup_log_install on lookup_log(install_id, at);
