// Клиент API админки (`server/src/admin.ts`). Сессия — HttpOnly-cookie,
// её JS не видит; изменяющие запросы несут заголовок X-Beepy-Admin — без
// него сервер их не примет (защита от подделки запроса с чужого сайта).

export class ApiError extends Error {
  status: number;
  code: string;
  constructor(status: number, code: string) {
    super(code);
    this.status = status;
    this.code = code;
  }
}

async function call<T>(path: string, init: RequestInit = {}): Promise<T> {
  const res = await fetch(`/admin/api${path}`, {
    credentials: "same-origin",
    ...init,
    headers: { "content-type": "application/json", "x-beepy-admin": "1", ...init.headers },
  });
  if (!res.ok) {
    const body = (await res.json().catch(() => ({}))) as { error?: string };
    throw new ApiError(res.status, body.error ?? "error");
  }
  return res.json() as Promise<T>;
}

export type Totals = {
  accounts: number;
  new_week: number;
  active_week: number;
  devices: number;
  cars: number;
  trips: number;
  meters: number;
};
export type Day = { day: string; trips: number; meters: number };

export type AccountRow = {
  id: string;
  created_at: string;
  last_sync_at: string | null;
  consent_version: string;
  devices: number;
  cars: number;
  trips: number;
  meters: number;
};

export type Device = {
  id: string;
  model: string;
  os: string;
  app_version: string;
  created_at: string;
  last_seen_at: string | null;
  revoked_at: string | null;
};
export type Car = {
  id: string;
  name: string;
  odometer: number;
  tracked_km: number;
  updated_at: string;
  deleted: boolean;
  trips: number;
};
export type Trip = {
  id: string;
  car_id: string | null;
  car_name: string | null;
  started_at: string;
  ended_at: string;
  meters: number;
  auto: boolean;
};
export type AccountDetail = {
  account: { id: string; created_at: string; last_sync_at: string | null; consent_version: string; consent_at: string };
  devices: Device[];
  cars: Car[];
  trips: Trip[];
};

export type AuditEntry = {
  id: number;
  at: string;
  actor: string;
  action: string;
  account_id: string | null;
  details: Record<string, string>;
};

export const api = {
  me: () => call<{ login: string; consentVersion: string }>("/me"),
  login: (login: string, password: string) =>
    call<{ login: string }>("/login", { method: "POST", body: JSON.stringify({ login, password }) }),
  logout: () => call<{ ok: true }>("/logout", { method: "POST" }),
  stats: () => call<{ totals: Totals; days: Day[] }>("/stats"),
  accounts: (q: string, offset = 0) =>
    call<{ accounts: AccountRow[]; total: number }>(`/accounts?q=${encodeURIComponent(q)}&offset=${offset}`),
  account: (id: string) => call<AccountDetail>(`/accounts/${id}`),
  deleteAccount: (id: string) => call<{ ok: true }>(`/accounts/${id}`, { method: "DELETE" }),
  revokeDevice: (id: string) => call<{ ok: true }>(`/devices/${id}/revoke`, { method: "POST" }),
  audit: () => call<{ entries: AuditEntry[] }>("/audit"),
};

/** Короткий вид идентификатора: первые 8 знаков, как у коммитов. */
export const shortId = (id: string) => id.slice(0, 8);
