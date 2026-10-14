import { randomUUID } from "node:crypto";
import { Hono, type Context } from "hono";
import { clientIp, RateLimit, type Env } from "./http.ts";
import { bodyLimit } from "hono/body-limit";
import { z } from "zod";
import type { Config } from "./config.ts";
import type { Db } from "./db.ts";
import { adminRoutes } from "./admin.ts";
import { PRIVACY_HTML } from "./privacy.ts";
import { hashToken, newToken } from "./secrets.ts";
import { sync, syncRequest } from "./sync.ts";
import { plateSchema, vinSchema, type Estimate, type FoundVehicle, type Outcome, type VehicleProvider } from "./vehicles.ts";

const registerRequest = z.object({
  consentVersion: z.string().max(32),
  device: z.object({
    model: z.string().max(64),
    os: z.string().max(32),
    appVersion: z.string().max(32),
  }),
});

/** Сколько дней хранится журнал поиска по номеру — столько обещает
 *  политика конфиденциальности (`privacy.ts`). */
export const LOOKUP_LOG_DAYS = 90;

/** Стереть записи журнала поиска старше срока. Зовётся при старте и раз в
 *  сутки (`main.ts`); возвращает, сколько стёрто. */
export async function purgeLookupLog(db: Db): Promise<number> {
  const rows = await db.query<{ id: string }>(
    `delete from lookup_log where at < now() - interval '${LOOKUP_LOG_DAYS} days' returning id`,
  );
  return rows.length;
}

export function createApp(db: Db, config: Config, vehicles: VehicleProvider | null = null) {
  const app = new Hono<Env>();
  const registrations = new RateLimit(20, 3600_000);

  // Журнал запросов: метод, путь, код, время. Тел и заголовков в нём нет —
  // там токены и персональные данные.
  app.use("*", async (c, next) => {
    const started = performance.now();
    await next();
    if (process.env.NODE_ENV !== "test") {
      console.log(`${c.req.method} ${c.req.path} ${c.res.status} ${Math.round(performance.now() - started)}ms`);
    }
  });
  app.use("*", bodyLimit({ maxSize: 1024 * 1024, onError: (c) => c.json({ error: "too_large" }, 413) }));
  app.onError((error, c) => {
    // В журнал — без тела запроса: в нём персональные данные.
    console.error(`${c.req.method} ${c.req.path}:`, error.message);
    return c.json({ error: "internal" }, 500);
  });

  /** Политика конфиденциальности: ссылка из App Store и из «Ещё». */
  app.get("/privacy", (c) => c.html(PRIVACY_HTML));

  app.get("/v1/health", async (c) => {
    await db.query("select 1");
    return c.json({ ok: true, consentVersion: config.consentVersion });
  });

  /** Новый аккаунт и первое устройство. Токен отдаётся один раз — дальше
   *  сервер знает только его хеш. */
  app.post("/v1/accounts", async (c) => {
    if (!registrations.allow(clientIp(c))) return c.json({ error: "rate_limited" }, 429);
    const body = registerRequest.safeParse(await c.req.json().catch(() => null));
    if (!body.success) return c.json({ error: "bad_request" }, 400);
    if (body.data.consentVersion !== config.consentVersion) {
      return c.json({ error: "consent_outdated", current: config.consentVersion }, 409);
    }
    const accountId = randomUUID();
    const deviceId = randomUUID();
    const token = newToken();
    const { model, os, appVersion } = body.data.device;
    await db.tx(async (q) => {
      await q.query("insert into accounts (id, consent_version, consent_at) values ($1, $2, now())", [
        accountId,
        body.data.consentVersion,
      ]);
      await q.query(
        "insert into devices (id, account_id, token_hash, model, os, app_version) values ($1, $2, $3, $4, $5, $6)",
        [deviceId, accountId, hashToken(token), model, os, appVersion],
      );
    });
    return c.json({ accountId, deviceId, token }, 201);
  });

  // Дальше — по токену устройства.
  const auth = async (c: Context<Env>, next: () => Promise<void>) => {
    const header = c.req.header("authorization") ?? "";
    const token = header.startsWith("Bearer ") ? header.slice(7) : "";
    if (!token) return c.json({ error: "unauthorized" }, 401);
    const rows = await db.query<{ id: string; account_id: string }>(
      "update devices set last_seen_at = now() where token_hash = $1 and revoked_at is null returning id, account_id",
      [hashToken(token)],
    );
    const found = rows[0];
    if (!found) return c.json({ error: "unauthorized" }, 401);
    c.set("accountId", found.account_id);
    c.set("deviceId", found.id);
    await next();
  };

  app.post("/v1/sync", auth, async (c) => {
    const body = syncRequest.safeParse(await c.req.json().catch(() => null));
    if (!body.success) {
      // Пути полей и причины, без значений: значения — персональные данные.
      const issues = body.error.issues.slice(0, 5).map((i) => `${i.path.join(".")}: ${i.message}`);
      console.warn("sync bad_request", issues.join("; "));
      return c.json({ error: "bad_request", issues }, 400);
    }
    const result = await db.tx((q) => sync(q, c.get("accountId"), body.data));
    return c.json(result);
  });

  /** Удалить аккаунт со всеми машинами, поездками и устройствами — право
   *  человека по 152-ФЗ, кнопка в приложении. В журнале остаётся только
   *  сам факт. */
  app.delete("/v1/account", auth, async (c) => {
    const accountId = c.get("accountId");
    await db.tx(async (q) => {
      await q.query("delete from accounts where id = $1", [accountId]);
      await q.query("insert into audit_log (actor, action, account_id) values ('app', 'account.delete', $1)", [accountId]);
    });
    return c.body(null, 204);
  });

  // ---------------------------------------------------- поиск по госномеру

  /** Установка приложения: случайный токен без согласия и без персональных
   *  данных — им считаются лимиты. Отдаётся один раз, хранится хешем. */
  app.post("/v1/installs", async (c) => {
    if (!registrations.allow(clientIp(c))) return c.json({ error: "rate_limited" }, 429);
    const id = randomUUID();
    const token = newToken();
    await db.query("insert into installs (id, token_hash) values ($1, $2)", [id, hashToken(token)]);
    return c.json({ token }, 201);
  });

  const install = async (c: Context<Env>, next: () => Promise<void>) => {
    const header = c.req.header("authorization") ?? "";
    const token = header.startsWith("Bearer ") ? header.slice(7) : "";
    if (!token) return c.json({ error: "unauthorized" }, 401);
    const rows = await db.query<{ id: string }>(
      "update installs set last_seen_at = now() where token_hash = $1 and revoked_at is null returning id",
      [hashToken(token)],
    );
    if (!rows[0]) return c.json({ error: "unauthorized" }, 401);
    c.set("deviceId", rows[0].id);
    await next();
  };

  /** Общая часть поиска и оценки: лимиты, вызов поставщика, журнал без
   *  номера и VIN, ответ. */
  async function proxied(c: Context<Env>, kind: "plate" | "price", call: () => Promise<Outcome<FoundVehicle | Estimate>>) {
    const installId = c.get("deviceId");
    const log = (outcome: string) =>
      db.query("insert into lookup_log (install_id, kind, outcome) values ($1, $2, $3)", [installId, kind, outcome]);
    if (!vehicles) return c.json({ error: "not_configured" }, 503);
    const [usage] = await db.query<{ mine: number; found: number }>(
      `select
         (select count(*)::int from lookup_log where install_id = $1 and at > now() - interval '1 day' and outcome <> 'limited') as mine,
         (select count(*)::int from lookup_log where outcome = 'found' and at > now() - interval '1 day') as found`,
      [installId],
    );
    if ((usage?.mine ?? 0) >= config.lookup.perInstallDaily || (usage?.found ?? 0) >= config.lookup.dailyFound) {
      await log("limited");
      return c.json({ error: "limited" }, 429);
    }
    const result = await call();
    await log(result.kind);
    if (result.kind === "found") return c.json(result.value);
    return result.kind === "not_found" ? c.json({ error: "not_found" }, 404) : c.json({ error: "unavailable" }, 503);
  }

  app.post("/v1/vehicles/lookup", install, async (c) => {
    const body = z.object({ plate: plateSchema }).safeParse(await c.req.json().catch(() => null));
    if (!body.success) return c.json({ error: "bad_request" }, 400);
    return proxied(c, "plate", () => vehicles!.lookup(body.data.plate));
  });

  app.post("/v1/vehicles/price", install, async (c) => {
    const body = z.object({ vin: vinSchema }).safeParse(await c.req.json().catch(() => null));
    if (!body.success) return c.json({ error: "bad_request" }, 400);
    return proxied(c, "price", () => vehicles!.price(body.data.vin.toUpperCase()));
  });

  app.route("/admin", adminRoutes(db, config));
  return app;
}
