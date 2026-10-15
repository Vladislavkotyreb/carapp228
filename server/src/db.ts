import { readdir, readFile } from "node:fs/promises";
import { PGlite } from "@electric-sql/pglite";
import pg from "pg";

/** То, через что ходят запросы: сама база или открытая транзакция. */
export type Queryable = {
  query<T = Record<string, unknown>>(sql: string, params?: unknown[]): Promise<T[]>;
};

/** База одним интерфейсом для двух движков: боевой Postgres (`pg`) и
 *  встроенный PGlite — тот же Postgres, собранный в WebAssembly, для
 *  разработки и тестов без установки сервера. SQL один и тот же. */
export type Db = Queryable & {
  tx<R>(fn: (q: Queryable) => Promise<R>): Promise<R>;
  exec(sql: string): Promise<void>;
  close(): Promise<void>;
};

export async function openPglite(dir?: string): Promise<Db> {
  const lite = dir ? new PGlite(dir) : new PGlite();
  await lite.waitReady;
  const wrap = (q: { query: PGlite["query"] }): Queryable => ({
    async query<T>(sql: string, params: unknown[] = []) {
      return (await q.query<T>(sql, params)).rows;
    },
  });
  return {
    ...wrap(lite),
    tx: (fn) => lite.transaction((t) => fn(wrap(t))),
    exec: async (sql) => {
      await lite.exec(sql);
    },
    close: () => lite.close(),
  };
}

export async function openPostgres(url: string): Promise<Db> {
  const pool = new pg.Pool({ connectionString: url, max: 10 });
  // bigint у pg по умолчанию строка; числа у нас помещаются в double.
  pg.types.setTypeParser(20, (v) => Number(v));
  return {
    async query<T>(sql: string, params: unknown[] = []) {
      return (await pool.query(sql, params)).rows as T[];
    },
    async tx(fn) {
      const client = await pool.connect();
      try {
        await client.query("begin");
        const result = await fn({
          async query<T>(sql: string, params: unknown[] = []) {
            return (await client.query(sql, params)).rows as T[];
          },
        });
        await client.query("commit");
        return result;
      } catch (error) {
        await client.query("rollback");
        throw error;
      } finally {
        client.release();
      }
    },
    exec: async (sql) => {
      await pool.query(sql);
    },
    close: () => pool.end(),
  };
}

/** Миграции из `migrations/*.sql` по порядку имён, каждая один раз. */
export async function migrate(db: Db, dir = new URL("../migrations/", import.meta.url)): Promise<string[]> {
  await db.exec(
    "create table if not exists schema_migrations (name text primary key, applied_at timestamptz not null default now())",
  );
  const done = new Set((await db.query<{ name: string }>("select name from schema_migrations")).map((r) => r.name));
  const files = (await readdir(dir)).filter((f) => f.endsWith(".sql")).sort();
  const applied: string[] = [];
  for (const file of files) {
    if (done.has(file)) continue;
    const sql = await readFile(new URL(file, dir), "utf8");
    await db.exec(`begin;\n${sql}\ninsert into schema_migrations (name) values ('${file.replace(/'/g, "")}');\ncommit;`);
    applied.push(file);
  }
  return applied;
}
