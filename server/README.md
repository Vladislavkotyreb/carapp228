# Сервер Beepy

Синхронизация поездок из приложения и API админки — один процесс на Node
(Hono). База — Postgres, по 152-ФЗ только на площадке в РФ
([`docs/DATABASES.md`](../docs/DATABASES.md)). Почему так устроено —
[`docs/BACKEND.md`](../docs/BACKEND.md), раздел «Синхронизация поездок».

## Что уходит на сервер

Только с согласия человека (экран в «Ещё»). Аккаунт анонимный: ни имени, ни
телефона, ни почты. У машины — название и пробег, у поездки — время, метры и
машина. Госномер, VIN, маршруты и адреса остаются на телефоне.

## Запуск

```bash
npm install
cp .env.example .env.local   # логин и хеш пароля админки
npm run hash-password        # хеш для ADMIN_PASSWORD_HASH
npm run dev                  # http://127.0.0.1:8787, база — PGlite в ./data
```

Без `DATABASE_URL` база — PGlite: тот же Postgres, собранный в WebAssembly,
без установки. Только для разработки: `NODE_ENV=production` без
`DATABASE_URL` не стартует.

Админка — сборка из `crm/` (`npm run admin:build` там), сервер отдаёт её по
`/admin`. В разработке интерфейса удобнее `npm run admin:dev` в `crm/`: запросы
к `/admin/api` он сам проксирует сюда.

Демо-данные для локального сервера: `npm run seed`.

## Проверка

```bash
npm test          # 26 проверок на PGlite в памяти
npm run typecheck
TEST_DATABASE_URL=postgres://…/beepy_test npm test   # то же на настоящем Postgres
```

База для `TEST_DATABASE_URL` должна называться `*_test`: тесты стирают её схему.

## Docker

```bash
docker compose up --build    # сервер + Postgres 17, пароли — из .env
```

Наружу смотрит только `127.0.0.1:8787`; на площадке перед сервером ставится
nginx с TLS, и с ним включается `ADMIN_SECURE_COOKIES=1`.

## API

| Метод | Путь | Что делает |
|---|---|---|
| `POST` | `/v1/accounts` | новый аккаунт и устройство; без действующего согласия — 409 |
| `POST` | `/v1/sync` | изменения телефона → изменения с других устройств (курсор, страницы по 500) |
| `DELETE` | `/v1/account` | удалить аккаунт со всеми данными |
| `GET` | `/v1/health` | жив ли сервер и база |
| `POST` | `/v1/installs` | токен установки для поиска (без согласия и персональных данных) |
| `POST` | `/v1/vehicles/lookup` | машина по госномеру через поставщика; 404 — нет, 429 — лимит |
| `POST` | `/v1/vehicles/price` | рыночная оценка по VIN |
| `POST` | `/admin/api/login`, `/logout` | вход в админку, cookie HttpOnly |
| `GET` | `/admin/api/stats`, `/accounts`, `/accounts/:id`, `/audit` | сводка, аккаунты, журнал |
| `DELETE` | `/admin/api/accounts/:id` | удалить аккаунт |
| `POST` | `/admin/api/devices/:id/revoke` | отозвать устройство |

Каждый просмотр и каждая правка в админке пишутся в `audit_log`.
