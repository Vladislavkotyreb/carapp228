-- Схема синхронизации поездок Beepy.
--
-- Аккаунт анонимный: у него нет ни телефона, ни почты, ни имени. Телефон
-- знает аккаунт по токену устройства, сервер хранит только хеш токена.
-- Госномер, VIN и маршруты сюда не попадают: поездке для пробега нужны
-- время, метры и машина (docs/BACKEND.md, «Синхронизация поездок»).

create table accounts (
  id uuid primary key,
  created_at timestamptz not null default now(),
  -- Какую редакцию согласия на обработку персональных данных принял человек
  -- и когда. Без согласия аккаунт не заводится.
  consent_version text not null,
  consent_at timestamptz not null,
  last_sync_at timestamptz
);

create table devices (
  id uuid primary key,
  account_id uuid not null references accounts(id) on delete cascade,
  -- sha256 от токена в hex. Сам токен знает только телефон.
  token_hash text not null unique,
  model text not null default '',
  os text not null default '',
  app_version text not null default '',
  created_at timestamptz not null default now(),
  last_seen_at timestamptz,
  revoked_at timestamptz
);
create index devices_account on devices(account_id);

-- Номер изменения: курсор синхронизации. Телефон присылает последний, что
-- видел, и получает всё, что изменилось после.
create sequence change_seq;

create table cars (
  account_id uuid not null references accounts(id) on delete cascade,
  id uuid not null,
  name text not null,
  odometer integer not null,
  tracked_km integer not null default 0,
  -- Время правки по часам телефона: по нему решается, чья правка новее.
  updated_at timestamptz not null,
  deleted boolean not null default false,
  seq bigint not null,
  primary key (account_id, id)
);
create index cars_seq on cars(account_id, seq);

create table trips (
  account_id uuid not null references accounts(id) on delete cascade,
  id uuid not null,
  car_id uuid,
  started_at timestamptz not null,
  ended_at timestamptz not null,
  meters double precision not null,
  auto boolean not null default false,
  updated_at timestamptz not null,
  deleted boolean not null default false,
  seq bigint not null,
  primary key (account_id, id)
);
create index trips_seq on trips(account_id, seq);
create index trips_started on trips(started_at);

-- Журнал доступа к персональным данным (152-ФЗ): кто из админки что
-- смотрел и менял. Ссылки на аккаунт нет намеренно — запись переживает
-- удаление аккаунта, а сам идентификатор ни о ком не говорит.
create table audit_log (
  id bigserial primary key,
  at timestamptz not null default now(),
  actor text not null,
  action text not null,
  account_id uuid,
  details jsonb not null default '{}'
);
create index audit_at on audit_log(at desc);

create table admin_sessions (
  token_hash text primary key,
  login text not null,
  created_at timestamptz not null default now(),
  expires_at timestamptz not null
);
