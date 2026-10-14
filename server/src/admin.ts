import { existsSync } from "node:fs";
import { readFile } from "node:fs/promises";
import path from "node:path";
import { Hono, type Context } from "hono";
import { deleteCookie, getCookie, setCookie } from "hono/cookie";
import { z } from "zod";
import type { Config } from "./config.ts";
import type { Db, Queryable } from "./db.ts";
import { clientIp, RateLimit, type Env } from "./http.ts";
import { hashToken, newToken, verifyPassword } from "./secrets.ts";

/** Админка Beepy: сводка, аккаунты с машинами и поездками, отзыв
 *  устройства, удаление аккаунта, журнал доступа.
 *
 *  Вход — логин и хеш пароля из окружения, сессия — HttpOnly-cookie с
 *  токеном, в базе хеш. Каждый просмотр и каждая правка персональных
 *  данных пишется в `audit_log` (152-ФЗ). Изменяющие запросы требуют
 *  заголовок `X-Beepy-Admin`: форма с чужого сайта его не пришлёт. */

const COOKIE = "beepy_admin";
const SESSION_MS = 12 * 3600 * 1000;
const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

async function audit(q: Queryable, actor: string, action: string, accountId: string | null, details: object = {}) {
  await q.query("insert into audit_log (actor, action, account_id, details) values ($1, $2, $3, $4)", [
    actor,
    action,
    accountId,
    JSON.stringify(details),
  ]);
}

export function adminRoutes(db: Db, config: Config) {
  const admin = new Hono<Env>();
  const logins = new RateLimit(5, 15 * 60 * 1000);

  admin.use("*", async (c, next) => {
    await next();
    c.header("X-Content-Type-Options", "nosniff");
    c.header("Referrer-Policy", "no-referrer");
    c.header("X-Frame-Options", "DENY");
    c.header("Cache-Control", c.req.path.includes("/assets/") ? "public, max-age=31536000, immutable" : "no-store");
  });

  admin.post("/api/login", async (c) => {
    // Считаются только неудачные попытки: пять подряд — пауза 15 минут.
    if (logins.blocked(clientIp(c))) return c.json({ error: "rate_limited" }, 429);
    const body = z
      .object({ login: z.string().max(64), password: z.string().max(256) })
      .safeParse(await c.req.json().catch(() => null));
    if (!body.success) return c.json({ error: "bad_request" }, 400);
    const { login, passwordHash } = config.admin;
    // Не настроено — админки нет вовсе, а не «пустой пароль подходит».
    if (!login || !passwordHash) return c.json({ error: "admin_disabled" }, 503);
    const ok = body.data.login === login && (await verifyPassword(body.data.password, passwordHash));
    await audit(db, body.data.login.slice(0, 64), ok ? "admin.login" : "admin.login_failed", null, { ip: clientIp(c) });
    if (!ok) {
      logins.hit(clientIp(c));
      return c.json({ error: "wrong_credentials" }, 401);
    }
    const token = newToken();
    await db.query("insert into admin_sessions (token_hash, login, expires_at) values ($1, $2, $3)", [
      hashToken(token),
      login,
      new Date(Date.now() + SESSION_MS).toISOString(),
    ]);
    setCookie(c, COOKIE, token, {
      httpOnly: true,
      sameSite: "Strict",
      secure: config.admin.secureCookies,
      path: "/admin",
      maxAge: SESSION_MS / 1000,
    });
    return c.json({ login });
  });

  // Всё ниже — с действующей сессией.
  const session = async (c: Context<Env>, next: () => Promise<void>) => {
    const token = getCookie(c, COOKIE);
    if (!token) return c.json({ error: "unauthorized" }, 401);
    const rows = await db.query<{ login: string }>(
      "select login from admin_sessions where token_hash = $1 and expires_at > now()",
      [hashToken(token)],
    );
    if (!rows[0]) return c.json({ error: "unauthorized" }, 401);
    if (c.req.method !== "GET" && c.req.header("x-beepy-admin") !== "1") {
      return c.json({ error: "csrf" }, 403);
    }
    c.set("adminLogin", rows[0].login);
    await next();
  };

  admin.post("/api/logout", session, async (c) => {
    const token = getCookie(c, COOKIE);
    if (token) await db.query("delete from admin_sessions where token_hash = $1", [hashToken(token)]);
    deleteCookie(c, COOKIE, { path: "/admin" });
    return c.json({ ok: true });
  });

  admin.get("/api/me", session, (c) => c.json({ login: c.get("adminLogin"), consentVersion: config.consentVersion }));

  /** Сводка: аккаунты, активность, поездки по дням за две недели. */
  admin.get("/api/stats", session, async (c) => {
    const [totals] = await db.query<Record<string, number>>(
      `select
         (select count(*)::int from accounts) as accounts,
         (select count(*)::int from accounts where created_at > now() - interval '7 days') as new_week,
         (select count(*)::int from accounts where last_sync_at > now() - interval '7 days') as active_week,
         (select count(*)::int from devices where revoked_at is null) as devices,
         (select count(*)::int from cars where not deleted) as cars,
         (select count(*)::int from trips where not deleted) as trips,
         (select coalesce(sum(meters), 0)::float8 from trips where not deleted) as meters,
         (select count(*)::int from installs where revoked_at is null) as installs,
         (select count(*)::int from lookup_log where at > now() - interval '1 day') as lookups_day,
         (select count(*)::int from lookup_log where at > now() - interval '1 day' and outcome = 'found') as lookups_found,
         (select count(*)::int from lookup_log where at > now() - interval '1 day' and outcome = 'limited') as lookups_limited`,
    );
    // Москва без перехода на летнее время: UTC+3 круглый год.
    const days = await db.query<{ day: string; trips: number; meters: number }>(
      `select to_char((started_at + interval '3 hours')::date, 'YYYY-MM-DD') as day,
              count(*)::int as trips, coalesce(sum(meters), 0)::float8 as meters
       from trips
       where not deleted and started_at > now() - interval '14 days'
       group by 1 order by 1`,
    );
    return c.json({ totals, days, lookupLimit: config.lookup.dailyFound });
  });

  admin.get("/api/accounts", session, async (c) => {
    const query = (c.req.query("q") ?? "").trim().toLowerCase();
    const limit = Math.min(Number(c.req.query("limit") ?? 50) || 50, 200);
    const offset = Math.max(Number(c.req.query("offset") ?? 0) || 0, 0);
    const rows = await db.query(
      `select a.id, a.created_at, a.last_sync_at, a.consent_version,
              (select count(*)::int from devices d where d.account_id = a.id and d.revoked_at is null) as devices,
              (select count(*)::int from cars c where c.account_id = a.id and not c.deleted) as cars,
              (select count(*)::int from trips t where t.account_id = a.id and not t.deleted) as trips,
              (select coalesce(sum(meters), 0)::float8 from trips t where t.account_id = a.id and not t.deleted) as meters
       from accounts a
       where $1 = '' or a.id::text like $1 || '%'
       order by a.last_sync_at desc nulls last, a.created_at desc
       limit $2 offset $3`,
      [query, limit, offset],
    );
    const [total] = await db.query<{ n: number }>(
      "select count(*)::int as n from accounts where $1 = '' or id::text like $1 || '%'",
      [query],
    );
    await audit(db, c.get("adminLogin"), "accounts.list", null, { q: query, offset });
    return c.json({ accounts: rows, total: total?.n ?? 0 });
  });

  admin.get("/api/accounts/:id", session, async (c) => {
    const id = c.req.param("id");
    if (!UUID.test(id)) return c.json({ error: "bad_request" }, 400);
    const [account] = await db.query(
      "select id, created_at, last_sync_at, consent_version, consent_at from accounts where id = $1",
      [id],
    );
    if (!account) return c.json({ error: "not_found" }, 404);
    const devices = await db.query(
      `select id, model, os, app_version, created_at, last_seen_at, revoked_at
       from devices where account_id = $1 order by created_at`,
      [id],
    );
    const cars = await db.query(
      `select id, name, odometer, tracked_km, updated_at, deleted,
              (select count(*)::int from trips t where t.account_id = c.account_id and t.car_id = c.id and not t.deleted) as trips
       from cars c where account_id = $1 order by deleted, name`,
      [id],
    );
    const trips = await db.query(
      `select t.id, t.car_id, c.name as car_name, t.started_at, t.ended_at, t.meters, t.auto, t.updated_at
       from trips t left join cars c on c.account_id = t.account_id and c.id = t.car_id
       where t.account_id = $1 and not t.deleted
       order by t.started_at desc limit 100`,
      [id],
    );
    await audit(db, c.get("adminLogin"), "account.view", id);
    return c.json({ account, devices, cars, trips });
  });

  admin.delete("/api/accounts/:id", session, async (c) => {
    const id = c.req.param("id");
    if (!UUID.test(id)) return c.json({ error: "bad_request" }, 400);
    const deleted = await db.tx(async (q) => {
      const rows = await q.query("delete from accounts where id = $1 returning id", [id]);
      if (rows.length) await audit(q, c.get("adminLogin"), "account.delete", id);
      return rows.length > 0;
    });
    return deleted ? c.json({ ok: true }) : c.json({ error: "not_found" }, 404);
  });

  /** Отозвать устройство: потерянный телефон больше не синхронизирует. */
  admin.post("/api/devices/:id/revoke", session, async (c) => {
    const id = c.req.param("id");
    if (!UUID.test(id)) return c.json({ error: "bad_request" }, 400);
    const rows = await db.query<{ account_id: string }>(
      "update devices set revoked_at = now() where id = $1 and revoked_at is null returning account_id",
      [id],
    );
    if (!rows[0]) return c.json({ error: "not_found" }, 404);
    await audit(db, c.get("adminLogin"), "device.revoke", rows[0].account_id, { device: id });
    return c.json({ ok: true });
  });

  admin.get("/api/audit", session, async (c) => {
    const limit = Math.min(Number(c.req.query("limit") ?? 100) || 100, 500);
    const rows = await db.query(
      "select id, at, actor, action, account_id, details from audit_log order by id desc limit $1",
      [limit],
    );
    return c.json({ entries: rows });
  });

  admin.all("/api/*", (c) => c.json({ error: "not_found" }, 404));

  // Собранный интерфейс админки. Нет сборки — подсказка, как её сделать.
  const dist = config.admin.distDir;
  admin.get("/*", async (c) => {
    if (!dist || !existsSync(dist)) {
      return c.text("Админка не собрана: в crm/ выполните npm run admin:build", 503);
    }
    const rel = c.req.path.replace(/^\/admin\/?/, "");
    const file = path.resolve(dist, rel || "admin.html");
    // Только файлы внутри сборки; остальное — точка входа приложения.
    const inside = file.startsWith(path.resolve(dist) + path.sep);
    const target = inside && existsSync(file) && !file.endsWith(path.sep) ? file : path.join(dist, "admin.html");
    const body = await readFile(target).catch(() => null);
    if (!body) return c.text("not found", 404);
    const type = TYPES[path.extname(target)] ?? "application/octet-stream";
    if (type.startsWith("text/html")) {
      c.header(
        "Content-Security-Policy",
        "default-src 'self'; style-src 'self' 'unsafe-inline'; img-src 'self' data:; font-src 'self' data:; frame-ancestors 'none'; base-uri 'none'",
      );
    }
    return c.body(body, 200, { "Content-Type": type });
  });

  return admin;
}

const TYPES: Record<string, string> = {
  ".html": "text/html; charset=utf-8",
  ".js": "text/javascript; charset=utf-8",
  ".css": "text/css; charset=utf-8",
  ".svg": "image/svg+xml",
  ".png": "image/png",
  ".woff2": "font/woff2",
  ".json": "application/json",
};
