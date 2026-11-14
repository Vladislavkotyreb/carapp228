import assert from "node:assert/strict";
import { test } from "node:test";
import { configFromEnv } from "../src/config.ts";

const budget = { VEHICLE_PROXY_ONLY: "1", LOOKUP_DAILY_BUDGET_RUB: "500", LOOKUP_UNIT_COST_KOPEKS: "800", LOOKUP_DAILY_FOUND: "100" };
test("500 рублей резервируют не более 62 запросов по 8 рублей", () => {
  assert.equal(configFromEnv(budget).lookup.dailyFound, 62);
  assert.equal(configFromEnv({ ...budget, LOOKUP_UNIT_COST_KOPEKS: "850" }).lookup.dailyFound, 58);
  assert.equal(configFromEnv({ ...budget, LOOKUP_DAILY_FOUND: "10" }).lookup.dailyFound, 10);
});
test("нулевой бюджет или ручной выключатель запрещают платные запросы", () => {
  assert.equal(configFromEnv({ ...budget, LOOKUP_DAILY_BUDGET_RUB: "0" }).lookup.dailyFound, 0);
  assert.equal(configFromEnv({ ...budget, LOOKUP_DAILY_FOUND: "0" }).lookup.dailyFound, 0);
});
test("ошибочные денежные ограничения останавливают запуск", () => {
  for (const cost of [undefined, "0", "-1", "NaN", "8.5", ""]) {
    assert.throws(() => configFromEnv({ ...budget, LOOKUP_UNIT_COST_KOPEKS: cost }));
  }
  assert.throws(() => configFromEnv({ ...budget, LOOKUP_DAILY_BUDGET_RUB: "9007199254740991" }));
  assert.throws(() => configFromEnv({ ...budget, VEHICLE_PROXY_ONLY: "0" }));
});
