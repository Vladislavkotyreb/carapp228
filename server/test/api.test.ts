import assert from "node:assert/strict";
import { randomUUID } from "node:crypto";
import { after, before, describe, test } from "node:test";
import { createApp } from "../src/app.ts";
import { CONSENT_VERSION, type Config } from "../src/config.ts";
import { migrate, openPglite, openPostgres, type Db } from "../src/db.ts";
import { hashPassword, hashToken } from "../src/secrets.ts";

// Тестовые учётные данные админки — только для этой базы в памяти.
const ADMIN = { login: "admin", password: "test-password-for-ci" };

let db: Db;
let app: ReturnType<typeof createApp>;

/** По умолчанию — PGlite в памяти. С TEST_DATABASE_URL — настоящий Postgres:
 *  база должна называться *_test, схема в ней пересоздаётся. */
async function openTestDb(): Promise<Db> {
  const url = process.env.TEST_DATABASE_URL;
  if (!url) return openPglite();
  if (!/_test(\?|$)/.test(new URL(url).pathname + new URL(url).search)) {
    throw new Error("TEST_DATABASE_URL должен вести в базу *_test: тесты стирают её схему");
  }
  const pg = await openPostgres(url);
  await pg.exec("drop schema public cascade; create schema public;");
  return pg;
}

before(async () => {
  db = await openTestDb();
  await migrate(db);
  const config: Config = {
    port: 0,
    consentVersion: CONSENT_VERSION,
    lookup: { perInstallDaily: 20, dailyFound: 100 },
    admin: { login: ADMIN.login, passwordHash: await hashPassword(ADMIN.password), secureCookies: false, distDir: undefined },
  };
  app = createApp(db, config);
});
after(() => db.close());

const json = (body: unknown, headers: Record<string, string> = {}) => ({
  method: "POST",
  headers: { "content-type": "application/json", ...headers },
  body: JSON.stringify(body),
});

async function register(): Promise<{ accountId: string; token: string }> {
  const res = await app.request(
    "/v1/accounts",
    json({ consentVersion: CONSENT_VERSION, device: { model: "iPhone16,1", os: "iOS 27.0.1", appVersion: "1.0" } }),
  );
  assert.equal(res.status, 201);
  return (await res.json()) as { accountId: string; token: string };
}

async function syncAs(token: string, body: object) {
  return app.request("/v1/sync", json(body, { authorization: `Bearer ${token}` }));
}

const now = Date.now();
const at = (minutes: number) => new Date(now + minutes * 60_000).toISOString();
function trip(over: Partial<Record<string, unknown>> = {}) {
  return {
    id: randomUUID(),
    carId: null,
    startedAt: at(-30),
    endedAt: at(-10),
    meters: 5400,
    auto: true,
    updatedAt: at(-10),
    deleted: false,
    ...over,
  };
}

describe("аккаунт", () => {
  test("без действующего согласия аккаунт не заводится", async () => {
    const res = await app.request("/v1/accounts", json({ consentVersion: "2020-01-01", device: { model: "", os: "", appVersion: "" } }));
    assert.equal(res.status, 409);
    assert.deepEqual(await res.json(), { error: "consent_outdated", current: CONSENT_VERSION });
  });

  test("токен хранится только хешем", async () => {
    const { token } = await register();
    const rows = await db.query<{ token_hash: string }>("select token_hash from devices");
    assert.ok(rows.every((r) => r.token_hash !== token && r.token_hash.length === 64));
  });

  test("без токена и с чужим токеном — 401", async () => {
    assert.equal((await app.request("/v1/sync", json({ cursor: null, cars: [], trips: [] }))).status, 401);
    assert.equal((await syncAs("nope", { cursor: null, cars: [], trips: [] })).status, 401);
  });
});

describe("синхронизация", () => {
  test("поездка уходит и приходит на второе устройство того же аккаунта", async () => {
    const { accountId, token } = await register();
    // Второе устройство — тот же аккаунт, свой токен.
    const second = "second-device-token";
    await db.query(
      "insert into devices (id, account_id, token_hash) values ($1, $2, $3)",
      [randomUUID(), accountId, hashToken(second)],
    );
    const carId = randomUUID();
    const t = trip({ carId });
    const push = await syncAs(token, {
      cursor: null,
      cars: [{ id: carId, name: "Mercedes-Benz GL-класс", odometer: 112_421, trackedKm: 5, updatedAt: at(-10), deleted: false }],
      trips: [t],
    });
    assert.equal(push.status, 200);
    const pushed = (await push.json()) as { cursor: string; trips: unknown[]; cars: unknown[] };
    assert.equal(pushed.trips.length, 0, "своё эхо не возвращается");
    assert.ok(Number(pushed.cursor) > 0);

    const pull = (await (await syncAs(second, { cursor: null, cars: [], trips: [] })).json()) as {
      cursor: string;
      trips: Array<{ id: string; meters: number; carId: string }>;
      cars: Array<{ id: string; name: string }>;
    };
    assert.equal(pull.trips.length, 1);
    assert.equal(pull.trips[0]!.id, t.id);
    assert.equal(pull.trips[0]!.carId, carId);
    assert.equal(pull.cars[0]!.name, "Mercedes-Benz GL-класс");

    const again = (await (await syncAs(second, { cursor: pull.cursor, cars: [], trips: [] })).json()) as { trips: unknown[] };
    assert.equal(again.trips.length, 0, "после курсора ничего нового");
  });

  test("новее побеждает; старая правка получает серверную версию", async () => {
    const { token } = await register();
    const t = trip({ meters: 1000, updatedAt: at(-5) });
    await syncAs(token, { cursor: null, cars: [], trips: [t] });
    const newer = { ...t, meters: 2000, updatedAt: at(-1) };
    const r1 = (await (await syncAs(token, { cursor: null, cars: [], trips: [newer] })).json()) as { cursor: string };
    const older = { ...t, meters: 1500, updatedAt: at(-3) };
    const r2 = (await (await syncAs(token, { cursor: r1.cursor, cars: [], trips: [older] })).json()) as {
      trips: Array<{ meters: number }>;
    };
    assert.deepEqual(r2.trips.map((x) => x.meters), [2000]);
    const [row] = await db.query<{ meters: number }>("select meters from trips where id = $1", [t.id]);
    assert.equal(row!.meters, 2000);
  });

  test("удаление окончательно: правку после удаления сервер не берёт", async () => {
    const { token } = await register();
    const t = trip({ updatedAt: at(-5) });
    await syncAs(token, { cursor: null, cars: [], trips: [t] });
    await syncAs(token, { cursor: null, cars: [], trips: [{ ...t, deleted: true, updatedAt: at(-4) }] });
    const revive = (await (await syncAs(token, { cursor: null, cars: [], trips: [{ ...t, meters: 9, updatedAt: at(-1) }] })).json()) as {
      trips: Array<{ deleted: boolean }>;
    };
    assert.equal(revive.trips[0]!.deleted, true);
    const old = { ...t, deleted: true, updatedAt: at(-60) };
    const [row] = await db.query<{ deleted: boolean }>("select deleted from trips where id = $1", [t.id]);
    assert.equal(row!.deleted, true);
    assert.ok(old);
  });

  test("удаление перебивает даже более новую правку", async () => {
    const { token } = await register();
    const t = trip({ updatedAt: at(-1) });
    await syncAs(token, { cursor: null, cars: [], trips: [t] });
    await syncAs(token, { cursor: null, cars: [], trips: [{ ...t, deleted: true, updatedAt: at(-30) }] });
    const [row] = await db.query<{ deleted: boolean }>("select deleted from trips where id = $1", [t.id]);
    assert.equal(row!.deleted, true);
  });

  test("аккаунты не видят поездок друг друга", async () => {
    const a = await register();
    const b = await register();
    await syncAs(a.token, { cursor: null, cars: [], trips: [trip()] });
    const pull = (await (await syncAs(b.token, { cursor: null, cars: [], trips: [] })).json()) as { trips: unknown[] };
    assert.equal(pull.trips.length, 0);
  });

  test("мусор не проходит: дата из будущего, конец раньше начала, 3000 км", async () => {
    const { token } = await register();
    for (const bad of [
      trip({ updatedAt: at(60 * 48) }),
      trip({ startedAt: at(-1), endedAt: at(-10) }),
      trip({ meters: 3_000_000 }),
      trip({ id: "not-a-uuid" }),
    ]) {
      assert.equal((await syncAs(token, { cursor: null, cars: [], trips: [bad] })).status, 400);
    }
  });

  test("большая история приходит страницами", async () => {
    const { accountId, token } = await register();
    const second = "paging-device-token";
    await db.query(
      "insert into devices (id, account_id, token_hash) values ($1, $2, $3)",
      [randomUUID(), accountId, hashToken(second)],
    );
    const all = Array.from({ length: 700 }, (_, i) => trip({ updatedAt: at(-100 + i / 100) }));
    await syncAs(token, { cursor: null, cars: [], trips: all.slice(0, 500) });
    await syncAs(token, { cursor: null, cars: [], trips: all.slice(500) });
    const seen = new Set<string>();
    let cursor: string | null = null;
    for (let page = 0; page < 5; page++) {
      const res = (await (await syncAs(second, { cursor, cars: [], trips: [] })).json()) as {
        cursor: string;
        more: boolean;
        trips: Array<{ id: string }>;
      };
      res.trips.forEach((t) => seen.add(t.id));
      cursor = res.cursor;
      if (!res.more) break;
    }
    assert.equal(seen.size, 700);
  });

  test("удаление аккаунта уносит всё", async () => {
    const { accountId, token } = await register();
    await syncAs(token, { cursor: null, cars: [], trips: [trip()] });
    const res = await app.request("/v1/account", { method: "DELETE", headers: { authorization: `Bearer ${token}` } });
    assert.equal(res.status, 204);
    const left = await db.query<{ n: number }>(
      `select (select count(*)::int from accounts where id = $1) + (select count(*)::int from trips where account_id = $1)
            + (select count(*)::int from devices where account_id = $1) as n`,
      [accountId],
    );
    assert.equal(left[0]!.n, 0);
    assert.equal((await syncAs(token, { cursor: null, cars: [], trips: [] })).status, 401);
  });
});

describe("админка", () => {
  async function login(password = ADMIN.password) {
    return app.request("/admin/api/login", json({ login: ADMIN.login, password }));
  }
  async function cookie(): Promise<string> {
    const res = await login();
    assert.equal(res.status, 200);
    const set = res.headers.get("set-cookie") ?? "";
    assert.match(set, /HttpOnly/i);
    assert.match(set, /SameSite=Strict/i);
    return set.split(";")[0]!;
  }

  test("без сессии — 401, неверный пароль — 401 и запись в журнале", async () => {
    assert.equal((await app.request("/admin/api/stats")).status, 401);
    assert.equal((await login("wrong")).status, 401);
    const [row] = await db.query<{ action: string }>("select action from audit_log order by id desc limit 1");
    assert.equal(row!.action, "admin.login_failed");
  });

  test("сводка, список, карточка аккаунта — и каждый просмотр в журнале", async () => {
    const c = await cookie();
    const { accountId, token } = await register();
    await syncAs(token, { cursor: null, cars: [], trips: [trip({ meters: 12_000 })] });

    const stats = (await (await app.request("/admin/api/stats", { headers: { cookie: c } })).json()) as {
      totals: { accounts: number; trips: number; meters: number };
    };
    assert.ok(stats.totals.accounts >= 1 && stats.totals.trips >= 1 && stats.totals.meters >= 12_000);

    const list = (await (await app.request(`/admin/api/accounts?q=${accountId.slice(0, 8)}`, { headers: { cookie: c } })).json()) as {
      accounts: Array<{ id: string; trips: number; meters: number }>;
    };
    assert.equal(list.accounts[0]!.id, accountId);
    assert.equal(list.accounts[0]!.trips, 1);

    const detail = await app.request(`/admin/api/accounts/${accountId}`, { headers: { cookie: c } });
    assert.equal(detail.status, 200);
    const [row] = await db.query<{ action: string; account_id: string }>(
      "select action, account_id from audit_log order by id desc limit 1",
    );
    assert.deepEqual({ ...row }, { action: "account.view", account_id: accountId });
  });

  test("изменение без заголовка X-Beepy-Admin отклоняется", async () => {
    const c = await cookie();
    const { accountId } = await register();
    const res = await app.request(`/admin/api/accounts/${accountId}`, { method: "DELETE", headers: { cookie: c } });
    assert.equal(res.status, 403);
  });

  test("отозванное устройство больше не синхронизирует", async () => {
    const c = await cookie();
    const { accountId, token } = await register();
    const [dev] = await db.query<{ id: string }>("select id from devices where account_id = $1", [accountId]);
    const res = await app.request(`/admin/api/devices/${dev!.id}/revoke`, {
      method: "POST",
      headers: { cookie: c, "x-beepy-admin": "1" },
    });
    assert.equal(res.status, 200);
    assert.equal((await syncAs(token, { cursor: null, cars: [], trips: [] })).status, 401);
  });

  test("удаление аккаунта из админки", async () => {
    const c = await cookie();
    const { accountId } = await register();
    const res = await app.request(`/admin/api/accounts/${accountId}`, {
      method: "DELETE",
      headers: { cookie: c, "x-beepy-admin": "1" },
    });
    assert.equal(res.status, 200);
    const [n] = await db.query<{ n: number }>("select count(*)::int as n from accounts where id = $1", [accountId]);
    assert.equal(n!.n, 0);
  });

  test("выход гасит сессию", async () => {
    const c = await cookie();
    await app.request("/admin/api/logout", { method: "POST", headers: { cookie: c, "x-beepy-admin": "1" } });
    assert.equal((await app.request("/admin/api/me", { headers: { cookie: c } })).status, 401);
  });

  // Последним: после него вход с этого адреса закрыт на 15 минут.
  test("пять неудачных входов — пауза, даже с верным паролем", async () => {
    for (let i = 0; i < 4; i++) assert.equal((await login("wrong")).status, 401);
    assert.equal((await login()).status, 429);
  });
});
