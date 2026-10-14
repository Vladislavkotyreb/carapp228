import assert from "node:assert/strict";
import { after, before, describe, test } from "node:test";
import { createApp } from "../src/app.ts";
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
    // Два найденных уже есть? Первое найденное было выше — добираем до лимита.
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

  test("название машины как в приложении", () => {
    assert.equal(prettyName("volkswagen multivan"), "Volkswagen Multivan");
    assert.equal(prettyName("mercedes-benz gl"), "Mercedes-Benz GL");
    assert.equal(prettyName("bmw x5"), "BMW X5");
    assert.equal(prettyName("лада веста"), "Лада Веста");
  });
});
