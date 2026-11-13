import assert from "node:assert/strict";
import { after, before, describe, test } from "node:test";
import { createApp, LOOKUP_LOG_DAYS, purgeLookupLog } from "../src/app.ts";
import { CONSENT_VERSION, type Config } from "../src/config.ts";
import { migrate, openPglite, type Db } from "../src/db.ts";
import { prettyName, type VehicleProvider } from "../src/vehicles.ts";

// Поставщик-подделка: настоящий платный API в тестах не трогаем.
const calls: string[] = [];
const fake: VehicleProvider = {
  async lookup(plate) {
    calls.push(plate);
    if (plate === "В777ОР777") return { kind: "found", value: { name: "Mercedes-Benz GL", vin: "WDC1668241A123456", year: 2015 } };
    if (plate === "А000АА00") return { kind: "unavailable" };
    return { kind: "not_found" };
  },
  async price(vin) {
    calls.push(vin);
    return { kind: "found", value: { average: 3_200_000, low: 2_900_000, high: 3_600_000, offers: 14 } };
  },
};

let db: Db;
let app: ReturnType<typeof createApp>;
const config: Config = {
  port: 0,
  consentVersion: CONSENT_VERSION,
  lookup: { perInstallDaily: 3, dailyFound: 2 },
  admin: { secureCookies: false },
};

before(async () => {
  db = await openPglite();
  await migrate(db);
  app = createApp(db, config, fake);
});
after(() => db.close());

const post = (path: string, body: unknown, token?: string) =>
  app.request(path, {
    method: "POST",
    headers: { "content-type": "application/json", ...(token ? { authorization: `Bearer ${token}` } : {}) },
    body: JSON.stringify(body),
  });

async function install(): Promise<string> {
  const res = await post("/v1/installs", {});
  assert.equal(res.status, 201);
  return ((await res.json()) as { token: string }).token;
}

describe("прокси поиска по госномеру", () => {
  test("без токена установки — 401, поставщик не вызывается", async () => {
    calls.length = 0;
    assert.equal((await post("/v1/vehicles/lookup", { plate: "В777ОР777" })).status, 401);
    assert.equal(calls.length, 0);
  });

  test("найдено, не найдено, недоступно", async () => {
    const token = await install();
    const found = await post("/v1/vehicles/lookup", { plate: "В777ОР777" }, token);
    assert.equal(found.status, 200);
    assert.equal(found.headers.get("cache-control"), "no-store");
    assert.deepEqual(await found.json(), { name: "Mercedes-Benz GL", vin: "WDC1668241A123456", year: 2015 });
    assert.equal((await post("/v1/vehicles/lookup", { plate: "Е123КХ199" }, token)).status, 404);
    assert.equal((await post("/v1/vehicles/lookup", { plate: "А000АА00" }, token)).status, 503);
  });

  test("номер и VIN сервер не хранит: в журнале только исход", async () => {
    const rows = await db.query<Record<string, unknown>>("select * from lookup_log");
    assert.ok(rows.length > 0);
    const text = JSON.stringify(rows);
    assert.ok(!text.includes("В777ОР777") && !text.includes("WDC1668241A123456"));
  });

  test("мусор вместо номера и VIN — 400 без обращения к поставщику", async () => {
    const token = await install();
    calls.length = 0;
    assert.equal((await post("/v1/vehicles/lookup", { plate: "DROP TABLE" }, token)).status, 400);
    assert.equal((await post("/v1/vehicles/price", { vin: "123" }, token)).status, 400);
    assert.equal((await post("/v1/vehicles/price", { vin: "WDC16682*1A123456" }, token)).status, 400);
    assert.equal(calls.length, 0);
  });

  test("лимит найденных на всех за сутки: дальше 429, поставщик не вызывается", async () => {
    await db.query("delete from lookup_log");
    const first = await install();
    assert.equal((await post("/v1/vehicles/lookup", { plate: "В777ОР777" }, first)).status, 200);
    const token = await install();
    assert.equal((await post("/v1/vehicles/price", { vin: "WDC1668241A123456" }, token)).status, 200);
    calls.length = 0;
    const limited = await post("/v1/vehicles/lookup", { plate: "В777ОР777" }, token);
    assert.equal(limited.status, 429);
    assert.equal(calls.length, 0);
  });

  test("лимит одной установки за сутки", async () => {
    await db.query("delete from lookup_log where outcome = 'found'");
    const token = await install();
    for (let i = 0; i < 3; i++) assert.equal((await post("/v1/vehicles/lookup", { plate: "Е123КХ199" }, token)).status, 404);
    assert.equal((await post("/v1/vehicles/lookup", { plate: "Е123КХ199" }, token)).status, 429);
    // Чужая установка в свой лимит.
    assert.equal((await post("/v1/vehicles/lookup", { plate: "Е123КХ199" }, await install())).status, 404);
  });

  test("без токена поставщика — 503 not_configured", async () => {
    const bare = createApp(db, config, null);
    const reg = await bare.request("/v1/installs", { method: "POST" });
    const { token } = (await reg.json()) as { token: string };
    const res = await bare.request("/v1/vehicles/lookup", {
      method: "POST",
      headers: { "content-type": "application/json", authorization: `Bearer ${token}` },
      body: JSON.stringify({ plate: "В777ОР777" }),
    });
    assert.equal(res.status, 503);
    assert.deepEqual(await res.json(), { error: "not_configured" });
  });

  test("журнал поиска чистится по сроку из политики, свежие записи целы", async () => {
    await db.query("delete from lookup_log");
    await db.query(
      `insert into lookup_log (at, kind, outcome) values
         (now() - interval '${LOOKUP_LOG_DAYS + 1} days', 'plate', 'found'),
         (now() - interval '${LOOKUP_LOG_DAYS - 1} days', 'plate', 'found'),
         (now(), 'price', 'not_found')`,
    );
    assert.equal(await purgeLookupLog(db), 1);
    const [remaining] = await db.query<{ left: number }>("select count(*)::int as left from lookup_log");
    assert.equal(remaining?.left, 2);
  });

  test("политика конфиденциальности отдаётся страницей", async () => {
    const res = await app.request("/privacy");
    assert.equal(res.status, 200);
    assert.match(res.headers.get("content-type") ?? "", /text\/html/);
    const html = await res.text();
    assert.match(html, /Политика конфиденциальности Beepy/);
    assert.match(html, /Вход через Apple/);
    assert.match(html, /Удалить аккаунт и данные/);
    assert.doesNotMatch(html, /Подписка «Beepy Плюс»/);
  });

  test("название машины как в приложении", () => {
    assert.equal(prettyName("volkswagen multivan"), "Volkswagen Multivan");
    assert.equal(prettyName("mercedes-benz gl"), "Mercedes-Benz GL");
    assert.equal(prettyName("bmw x5"), "BMW X5");
    assert.equal(prettyName("лада веста"), "Лада Веста");
  });
});

// Независимые сценарии с медленным поставщиком: запросы пересекаются до ответа.
for (const [name, perInstallDaily, dailyFound] of [
  ["общий резерв", 10, 2],
  ["лимит установки", 2, 10],
] as const) {
  test(`параллельные запросы не обходят ${name}`, async () => {
    const isolated = await openPglite();
    await migrate(isolated);
    let requested = 0;
    const slow: VehicleProvider = {
      async lookup() {
        requested++;
        await new Promise((resolve) => setTimeout(resolve, 60));
        return { kind: "found", value: { name: "BMW X5", vin: null, year: 2020 } };
      },
      price: fake.price,
    };
    try {
      const local = createApp(isolated, { ...config, lookup: { perInstallDaily, dailyFound } }, slow);
      const registration = await local.request("/v1/installs", { method: "POST" });
      const { token } = await registration.json() as { token: string };
      const requests = Array.from({ length: 8 }, () => local.request("/v1/vehicles/lookup", {
        method: "POST",
        headers: { "content-type": "application/json", authorization: `Bearer ${token}` },
        body: JSON.stringify({ plate: "В777ОР777" }),
      }));
      const responses = await Promise.all(requests);
      assert.equal(requested, 2);
      assert.equal(responses.filter((r) => r.status === 200).length, 2);
      assert.equal(responses.filter((r) => r.status === 429).length, 6);
    } finally { await isolated.close(); }
  });
}

test("ошибка поставщика сохраняет резерв, не открывая бюджет для повторов", async () => {
  const isolated = await openPglite();
  await migrate(isolated);
  let requested = 0;
  try {
    const local = createApp(isolated, { ...config, lookup: { perInstallDaily: 20, dailyFound: 1 } }, {
      async lookup() { requested++; throw new Error("provider failed"); }, price: fake.price,
    });
    const registration = await local.request("/v1/installs", { method: "POST" });
    const { token } = await registration.json() as { token: string };
    const lookup = () => local.request("/v1/vehicles/lookup", {
      method: "POST", headers: { "content-type": "application/json", authorization: `Bearer ${token}` },
      body: JSON.stringify({ plate: "В777ОР777" }),
    });
    assert.equal((await lookup()).status, 503);
    assert.equal((await lookup()).status, 429);
    assert.equal(requested, 1);
  } finally { await isolated.close(); }
});
