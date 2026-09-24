import { OPEN_STATUSES, type Employee, type RequestSource, type RequestStatus, type ServiceRequest } from "./types";

// Всё, что считает дашборд, — чистые функции над списком заявок. Вью только
// рисует: логика в разметке — логика, которую никто не проверит.

const DAY = 24 * 60 * 60 * 1000;

export function isOpen(r: ServiceRequest): boolean {
  return OPEN_STATUSES.includes(r.status);
}

export interface Kpi {
  fresh: number;
  unassigned: number;
  inWork: number;
  doneWeek: number;
}

export function kpi(requests: ServiceRequest[], now = Date.now()): Kpi {
  return {
    fresh: requests.filter((r) => r.status === "new").length,
    unassigned: requests.filter((r) => isOpen(r) && !r.assigneeId).length,
    inWork: requests.filter((r) => r.status === "in_progress" || r.status === "waiting_parts").length,
    doneWeek: requests.filter((r) => r.status === "done" && now - Date.parse(r.createdAt) < 7 * DAY).length,
  };
}

export function bySource(requests: ServiceRequest[]): Record<RequestSource, number> {
  return {
    app: requests.filter((r) => r.payload.source === "app").length,
    site: requests.filter((r) => r.payload.source === "site").length,
  };
}

export interface Load {
  employee: Employee;
  open: number;
}

/** Открытые заявки на каждого, самые загруженные сверху. */
export function load(requests: ServiceRequest[], employees: Employee[]): Load[] {
  return employees
    .map((employee) => ({
      employee,
      open: requests.filter((r) => isOpen(r) && r.assigneeId === employee.id).length,
    }))
    .sort((a, b) => b.open - a.open);
}

/** С чем приходят чаще всего — по системам из прослушивания. Берём только
 *  первую находку заявки: она и есть причина визита, остальные — версии. */
export function topSystems(requests: ServiceRequest[], limit = 4): { system: string; count: number }[] {
  const counts = new Map<string, number>();
  for (const r of requests) {
    if (r.payload.source !== "app") continue;
    const first = r.payload.findings[0];
    if (first) counts.set(first.system, (counts.get(first.system) ?? 0) + 1);
  }
  return [...counts.entries()]
    .map(([system, count]) => ({ system, count }))
    .sort((a, b) => b.count - a.count)
    .slice(0, limit);
}

/** Колонки канбана — все статусы в порядке жизни заявки. */
export const BOARD_COLUMNS: readonly RequestStatus[] = ["new", "in_progress", "waiting_parts", "done", "cancelled"];

/** Заявки по колонкам, свежие сверху. Пустая колонка остаётся в раскладке:
 *  в неё тоже надо уметь перетащить. */
export function byStatus(requests: ServiceRequest[]): Record<RequestStatus, ServiceRequest[]> {
  const board = Object.fromEntries(BOARD_COLUMNS.map((s) => [s, [] as ServiceRequest[]])) as Record<
    RequestStatus,
    ServiceRequest[]
  >;
  for (const r of requests) board[r.status].push(r);
  for (const s of BOARD_COLUMNS) board[s].sort((a, b) => Date.parse(b.createdAt) - Date.parse(a.createdAt));
  return board;
}

/** «Требует внимания» — флажок на карточке, как Flagged в Jira: открытая
 *  заявка, которой больше суток. Клиент ждёт, а она всё ещё не закрыта. */
export function needsAttention(r: ServiceRequest, now = Date.now()): boolean {
  return isOpen(r) && now - Date.parse(r.createdAt) > DAY;
}

export type GroupBy = "none" | "assignee" | "source";

export interface Lane {
  id: string;
  label: string;
  /** Исполнитель дорожки: перетаскивание в неё переназначает заявку.
   *  `null` — дорожка «Без исполнителя», `undefined` — дорожка не про людей. */
  assigneeId?: string | null;
  requests: ServiceRequest[];
}

/** Дорожки доски. Люди — только те, у кого есть заявки на доске, в порядке
 *  списка сотрудников; «Без исполнителя» — последней, как «Everything else»
 *  в Jira: это остаток, а не главная полоса. */
export function lanes(requests: ServiceRequest[], employees: Employee[], by: GroupBy): Lane[] {
  if (by === "none") return [{ id: "all", label: "Все заявки", requests }];
  if (by === "source") {
    return (["app", "site"] as const)
      .map((s) => ({
        id: s,
        label: s === "app" ? "Из приложения" : "С сайта",
        requests: requests.filter((r) => r.payload.source === s),
      }))
      .filter((l) => l.requests.length > 0);
  }
  const people = employees
    .map((e) => ({
      id: e.id,
      label: e.name,
      assigneeId: e.id as string | null,
      requests: requests.filter((r) => r.assigneeId === e.id),
    }))
    .filter((l) => l.requests.length > 0);
  const nobody = requests.filter((r) => !r.assigneeId || !employees.some((e) => e.id === r.assigneeId));
  return nobody.length > 0
    ? [...people, { id: "nobody", label: "Без исполнителя", assigneeId: null, requests: nobody }]
    : people;
}
