import assert from "node:assert/strict";
import { test } from "node:test";
import { avtoVinCod } from "../src/vehicles.ts";
import { configFromEnv } from "../src/config.ts";

for (const [name, status, body, expected] of [
  ["не найдено в HTTP 200", 200, { success: 0, status: "not_found" }, "not_found"],
  ["ошибка HTTP не становится найденной машиной", 402, { success: 1, brand: "BMW", model: "X5" }, "unavailable"],
  ["оплаченный неполный ответ сохраняет резерв", 200, { success: 1, vin: "test" }, "unavailable"],
  ["успешный поиск", 200, { success: 1, brand: "bmw", model: "x5", year: 2020 }, "found"],
] as const) {
  test(name, async (t) => {
    t.mock.method(globalThis, "fetch", async () => new Response(JSON.stringify(body), { status }));
    assert.equal((await avtoVinCod("test-token").lookup("Т000ТТ00")).kind, expected);
  });
}

test("неверный лимит останавливает запуск вместо снятия защиты", () => {
  for (const value of ["", "abc", "NaN", "Infinity", "-1", "1.5"]) {
    assert.throws(() => configFromEnv({ LOOKUP_DAILY_FOUND: value }));
    assert.throws(() => configFromEnv({ LOOKUP_PER_INSTALL_DAILY: value }));
  }
  assert.equal(configFromEnv({ LOOKUP_DAILY_FOUND: "0" }).lookup.dailyFound, 0);
});
