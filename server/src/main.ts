import { mkdirSync } from "node:fs";
import { serve } from "@hono/node-server";
import { createApp } from "./app.ts";
import { configFromEnv } from "./config.ts";
import { migrate, openPglite, openPostgres, type Db } from "./db.ts";
import { providerFromEnv } from "./vehicles.ts";

const config = configFromEnv();

let db: Db;
if (config.databaseUrl) {
  db = await openPostgres(config.databaseUrl);
} else {
  if (process.env.NODE_ENV === "production") {
    // Встроенная база — для разработки. В проде данные — в управляемом
    // Postgres в РФ с резервными копиями (docs/DATABASES.md).
    throw new Error("NODE_ENV=production требует DATABASE_URL");
  }
  if (config.pgliteDir) mkdirSync(config.pgliteDir, { recursive: true });
  db = await openPglite(config.pgliteDir);
}

const applied = await migrate(db);
if (applied.length) console.log("миграции:", applied.join(", "));
if (!config.admin.login || !config.admin.passwordHash) {
  console.log("админка выключена: нет ADMIN_LOGIN и ADMIN_PASSWORD_HASH (npm run hash-password)");
}

const vehicles = providerFromEnv();
if (!vehicles) console.log("поиск по госномеру выключен: нет AVTOVINCOD_TOKEN или APICLOUD_TOKEN");
const app = createApp(db, config, vehicles);
const server = serve({ fetch: app.fetch, port: config.port, hostname: process.env.HOST ?? "127.0.0.1" }, (info) => {
  console.log(`Beepy server: http://${info.address}:${info.port} (база: ${config.databaseUrl ? "Postgres" : "PGlite"})`);
});

const stop = async () => {
  server.close();
  await db.close();
  process.exit(0);
};
process.on("SIGINT", stop);
process.on("SIGTERM", stop);
