import type { Context } from "hono";

export type Env = { Variables: { accountId: string; deviceId: string; adminLogin: string } };

/** Окно для счётчика попыток: регистрация и вход в админку. Память
 *  процесса — для одного сервера хватает. */
export class RateLimit {
  private hits = new Map<string, number[]>();
  constructor(private limit: number, private windowMs: number) {}
  /** Лимит исчерпан — не пускать, но и не считать попытку. */
  blocked(key: string, now = Date.now()): boolean {
    return (this.hits.get(key) ?? []).filter((t) => now - t < this.windowMs).length >= this.limit;
  }
  /** Засчитать попытку, не решая, пускать ли. */
  hit(key: string, now = Date.now()): void {
    const recent = (this.hits.get(key) ?? []).filter((t) => now - t < this.windowMs);
    recent.push(now);
    this.hits.set(key, recent);
  }
  allow(key: string, now = Date.now()): boolean {
    const recent = (this.hits.get(key) ?? []).filter((t) => now - t < this.windowMs);
    if (recent.length >= this.limit) {
      this.hits.set(key, recent);
      return false;
    }
    recent.push(now);
    this.hits.set(key, recent);
    return true;
  }
}

export function clientIp(c: Context): string {
  // За обратным прокси (nginx) адрес клиента — в X-Forwarded-For.
  const forwarded = c.req.header("x-forwarded-for")?.split(",")[0]?.trim();
  return forwarded || c.req.header("x-real-ip") || "local";
}
