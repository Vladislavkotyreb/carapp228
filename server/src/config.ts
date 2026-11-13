/** Настройки сервера — только из окружения. Секретов в коде нет: пароль
 *  админки приходит хешем (`npm run hash-password`), строка подключения к
 *  базе — из `DATABASE_URL`. */
export type Config = {
  port: number;
  /** Публиковать только health, регистрацию установки и поиск по номеру. */
  vehicleProxyOnly?: boolean;
  /** `postgres://…` — боевой Postgres. Пусто — встроенный PGlite. */
  databaseUrl?: string;
  /** Папка PGlite; пусто вместе с `databaseUrl` — база в памяти (тесты). */
  pgliteDir?: string;
  /** Редакция согласия на обработку персональных данных, которую сервер
   *  принимает. Сменили текст согласия — сменили редакцию, и новые аккаунты
   *  без нового согласия не заводятся. */
  consentVersion: string;
  /** Лимиты прокси поиска по госномеру: платный поставщик не должен
   *  обнулить баланс, даже если токен установки украдут или наштампуют. */
  lookup: {
    /** Запросов с одной установки за сутки (любой исход). */
    perInstallDaily: number;
    /** Общий резерв на сутки: найденные, выполняющиеся и неизвестные исходы. */
    dailyFound: number;
  };
  admin: {
    login?: string;
    /** `scrypt$N$r$p$соль$хеш` из `npm run hash-password`. */
    passwordHash?: string;
    /** Cookie только по HTTPS. В проде включено всегда. */
    secureCookies: boolean;
    /** Собранная админка (`crm`: `npm run admin:build`). */
    distDir?: string;
  };
};

export const CONSENT_VERSION = "2026-10-12";

function limit(value: string | undefined, fallback: number, name: string): number {
  const parsed = value === undefined ? fallback : Number(value);
  if (value?.trim() === "" || !Number.isSafeInteger(parsed) || parsed < 0) {
    throw new Error(`${name} должен быть целым неотрицательным числом`);
  }
  return parsed;
}

export function configFromEnv(env: NodeJS.ProcessEnv = process.env): Config {
  const production = env.NODE_ENV === "production";
  return {
    port: Number(env.PORT ?? 8787),
    vehicleProxyOnly: env.VEHICLE_PROXY_ONLY === "1",
    databaseUrl: env.DATABASE_URL || undefined,
    pgliteDir: env.DATABASE_URL ? undefined : (env.PGLITE_DIR ?? "./data/pglite"),
    consentVersion: env.CONSENT_VERSION ?? CONSENT_VERSION,
    lookup: {
      perInstallDaily: limit(env.LOOKUP_PER_INSTALL_DAILY, 20, "LOOKUP_PER_INSTALL_DAILY"),
      dailyFound: limit(env.LOOKUP_DAILY_FOUND, 100, "LOOKUP_DAILY_FOUND"),
    },
    admin: {
      login: env.ADMIN_LOGIN || undefined,
      passwordHash: env.ADMIN_PASSWORD_HASH || undefined,
      secureCookies: production || env.ADMIN_SECURE_COOKIES === "1",
      distDir: env.ADMIN_DIST ?? new URL("../../crm/dist-admin", import.meta.url).pathname,
    },
  };
}
