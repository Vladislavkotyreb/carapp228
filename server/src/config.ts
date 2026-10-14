/** Настройки сервера — только из окружения. Секретов в коде нет: пароль
 *  админки приходит хешем (`npm run hash-password`), строка подключения к
 *  базе — из `DATABASE_URL`. */
export type Config = {
  port: number;
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
    /** Найденных — то есть оплаченных — запросов за сутки на всех. */
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

export function configFromEnv(env: NodeJS.ProcessEnv = process.env): Config {
  const production = env.NODE_ENV === "production";
  return {
    port: Number(env.PORT ?? 8787),
    databaseUrl: env.DATABASE_URL || undefined,
    pgliteDir: env.DATABASE_URL ? undefined : (env.PGLITE_DIR ?? "./data/pglite"),
    consentVersion: env.CONSENT_VERSION ?? CONSENT_VERSION,
    lookup: {
      perInstallDaily: Number(env.LOOKUP_PER_INSTALL_DAILY ?? 20),
      dailyFound: Number(env.LOOKUP_DAILY_FOUND ?? 100),
    },
    admin: {
      login: env.ADMIN_LOGIN || undefined,
      passwordHash: env.ADMIN_PASSWORD_HASH || undefined,
      secureCookies: production || env.ADMIN_SECURE_COOKIES === "1",
      distDir: env.ADMIN_DIST ?? new URL("../../crm/dist-admin", import.meta.url).pathname,
    },
  };
}
