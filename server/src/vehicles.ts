import { z } from "zod";

/** Поиск машины по госномеру и рыночная оценка по VIN — у поставщиков, с
 *  их платным токеном. Раньше запросы шли прямо из приложения, и токен
 *  вынимался из `.ipa` за минуты (docs/BACKEND.md, «Поиск авто по госномеру»).
 *  Разбор ответов — тот же, что был в `VehicleLookup.swift`. */

export type FoundVehicle = { name: string; vin: string | null; year: number | null };
export type Estimate = { average: number; low: number | null; high: number | null; offers: number | null };
export type Outcome<T> = { kind: "found"; value: T } | { kind: "not_found" } | { kind: "unavailable" };

export interface VehicleProvider {
  lookup(plate: string): Promise<Outcome<FoundVehicle>>;
  price(vin: string): Promise<Outcome<Estimate>>;
}

/** Номер слитно кириллицей, как его шлёт `PlateFormat.significant`: «В777ОР777». */
export const plateSchema = z.string().regex(/^[АВЕКМНОРСТУХ0-9]{6,9}$/);
/** VIN — 17 знаков без I, O, Q; замаскированный звёздочками не годится. */
export const vinSchema = z.string().regex(/^[A-HJ-NPR-Z0-9]{17}$/i);

const TIMEOUT_MS = 15_000;

async function get(url: string, headers: Record<string, string>): Promise<Response | null> {
  const host = new URL(url).host + new URL(url).pathname;
  try {
    const res = await fetch(url, { headers, signal: AbortSignal.timeout(TIMEOUT_MS) });
    // Код ответа поставщика — в журнал: 401 токен, 402 баланс, 429 частота.
    // Без адреса запроса и тела: в них номер и VIN.
    if (!res.ok) console.warn(`vehicles: ${host} ответил ${res.status}`);
    return res;
  } catch (error) {
    console.warn(`vehicles: ${host} не ответил (${(error as Error).name})`);
    return null;
  }
}

/** Марка и модель приходят строчными («volkswagen multivan»): первые буквы
 *  слов — заглавные, короткие латинские слова — аббревиатуры (gl → GL). */
export function prettyName(raw: string): string {
  return raw
    .trim()
    .split(/\s+/)
    .filter(Boolean)
    .map((word) => {
      const cap = word
        .split("-")
        .map((part) => part.charAt(0).toLocaleUpperCase("ru") + part.slice(1).toLocaleLowerCase("ru"))
        .join("-");
      return cap.length <= 3 && /^[A-Za-z]+$/.test(cap) ? cap.toUpperCase() : cap;
    })
    .join(" ");
}

/** avtovincod.ru: `gos2vin` и `price`. Ненайденное бесплатно, найденное —
 *  8 ₽ (по ответу сервиса 23.10.2026; было 5.5 ₽); оценка без данных по
 *  модели не списывается. При балансе ниже цены запроса сервис отвечает 402
 *  ещё до поиска — так проверяют баланс, ничего не тратя. */
export function avtoVinCod(token: string): VehicleProvider {
  const auth = { Authorization: `Bearer ${token}` };
  return {
    async lookup(plate) {
      const res = await get(`https://api.avtovincod.ru/gos2vin?plate=${encodeURIComponent(plate)}`, auth);
      if (!res) return { kind: "unavailable" };
      // 404 — «номер не найден»; 401, 402, 429 — токен, баланс, частота.
      if (res.status === 404) return { kind: "not_found" };
      const body = (await res.json().catch(() => null)) as
        | { success?: number; vin?: string; brand?: string; model?: string; year?: number }
        | null;
      if (!body || body.success !== 1) return { kind: "unavailable" };
      const name = prettyName([body.brand, body.model].filter(Boolean).join(" "));
      if (!name) return { kind: "not_found" };
      return { kind: "found", value: { name, vin: body.vin ?? null, year: body.year ?? null } };
    },
    async price(vin) {
      const res = await get(`https://api.avtovincod.ru/price?vin=${encodeURIComponent(vin)}`, auth);
      if (!res) return { kind: "unavailable" };
      if (res.status === 404) return { kind: "not_found" };
      type Block = { average?: number; min?: number; max?: number; count?: number };
      const body = (await res.json().catch(() => null)) as
        | (Block & { success?: number; found?: boolean; price?: Block; offers?: number })
        | null;
      if (!body || body.success !== 1) return { kind: "unavailable" };
      // Живой сервис кладёт числа в `price`, пример в документации — плоский.
      const average = body.price?.average ?? body.average;
      if (body.found === false || !average || average <= 0) return { kind: "not_found" };
      return {
        kind: "found",
        value: {
          average,
          low: body.price?.min ?? body.min ?? null,
          high: body.price?.max ?? body.max ?? null,
          offers: body.price?.count ?? body.offers ?? null,
        },
      };
    },
  };
}

/** api-cloud.ru, база полисов ОСАГО: марка с моделью и VIN (бывает со
 *  звёздочками). Оценки цены у него нет. */
export function apiCloud(token: string): VehicleProvider {
  return {
    async lookup(plate) {
      const res = await get(
        `https://api-cloud.ru/api/rsa.php?type=osago&regNumber=${encodeURIComponent(plate)}`,
        { Token: token },
      );
      if (!res) return { kind: "unavailable" };
      const body = (await res.json().catch(() => null)) as
        | { status?: number; rez?: Array<{ brandmodel?: string; vin?: string; status?: string }> }
        | null;
      if (!body || body.status !== 200) return { kind: "unavailable" };
      const entries = body.rez ?? [];
      const entry = entries.find((e) => e.status === "Действует") ?? entries[0];
      if (!entry?.brandmodel) return { kind: "not_found" };
      const vin = entry.vin && !entry.vin.includes("*") ? entry.vin : null;
      return { kind: "found", value: { name: entry.brandmodel, vin, year: null } };
    },
    async price() {
      return { kind: "unavailable" };
    },
  };
}

/** AvtoVinCod предпочтительнее: год выпуска, оценка цены, нет месячных платежей. */
export function providerFromEnv(env: NodeJS.ProcessEnv = process.env): VehicleProvider | null {
  if (env.AVTOVINCOD_TOKEN) return avtoVinCod(env.AVTOVINCOD_TOKEN);
  if (env.APICLOUD_TOKEN) return apiCloud(env.APICLOUD_TOKEN);
  return null;
}
