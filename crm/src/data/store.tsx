import { createContext, useContext, useEffect, useReducer, type ReactNode } from "react";
import { round, stockLevels } from "./inventory";
import { todayKey } from "./staff";
import { seedEmployees, seedMoves, seedRequests, seedRoles, seedStock } from "./seed";
import { OPEN_STATUSES } from "./types";
import type {
  Employee,
  PartLine,
  RequestStatus,
  RoleDef,
  ServiceRequest,
  StockItem,
  StockMove,
} from "./types";

// Хранилище наброска. Данные живут в браузере (localStorage): сервера нет,
// а персональные данные клиентов по 152-ФЗ должны лежать на сервере в РФ —
// до него это прототип интерфейса, не система учёта.

interface State {
  requests: ServiceRequest[];
  employees: Employee[];
  roles: RoleDef[];
  stock: StockItem[];
  moves: StockMove[];
}

type Action =
  | { type: "setStatus"; id: string; status: RequestStatus }
  | { type: "assign"; id: string; employeeId: string | undefined }
  /** Перенос карточки на доске: колонка задаёт статус, дорожка исполнителя —
   *  исполнителя. Одним действием, а не двумя: иначе «назначили на новую →
   *  в работу» из `assign` перебил бы колонку, в которую карточку бросили.
   *  `assigneeId: undefined` — дорожка не про людей, исполнитель не меняется;
   *  `null` — дорожка «Без исполнителя». */
  | { type: "move"; id: string; status: RequestStatus; assigneeId?: string | null }
  | { type: "addEmployee"; name: string; roleId: string; phone: string }
  | { type: "updateEmployee"; id: string; roleId: string }
  | { type: "toggleShift"; id: string }
  /** Деактивация вместо удаления: открытые заявки остаются без исполнителя,
   *  закрытые сохраняют имя. */
  | { type: "deactivate"; id: string }
  | { type: "reactivate"; id: string }
  | { type: "addRole"; name: string }
  | { type: "renameRole"; id: string; name: string }
  /** Удалить можно только пустую роль: у сотрудника роль обязательна. */
  | { type: "deleteRole"; id: string }
  /** Приход: вручную или сканом упаковки. */
  | { type: "receive"; itemId: string; qty: number }
  /** Пересчёт: сколько лежит на самом деле. Движение — разница с учётом. */
  | { type: "count"; itemId: string; actual: number }
  | { type: "addItem"; item: StockItem }
  /** Черновик расхода по заявке. Списанный не правится. */
  | { type: "setParts"; requestId: string; lines: PartLine[] }
  | { type: "writeOff"; requestId: string }
  | { type: "undoWriteOff"; requestId: string }
  | { type: "reset" };

function reducer(state: State, action: Action): State {
  switch (action.type) {
    case "setStatus":
      return {
        ...state,
        requests: state.requests.map((r) => (r.id === action.id ? { ...r, status: action.status } : r)),
      };
    case "assign":
      return {
        ...state,
        requests: state.requests.map((r) => {
          if (r.id !== action.id) return r;
          // Назначили исполнителя на новую заявку — она ушла в работу.
          // Обратное не делаем: снять исполнителя не значит вернуть заявку.
          const status = r.status === "new" && action.employeeId ? "in_progress" : r.status;
          return { ...r, assigneeId: action.employeeId, status };
        }),
      };
    case "move":
      return {
        ...state,
        requests: state.requests.map((r) => {
          if (r.id !== action.id) return r;
          const assigneeId = action.assigneeId === undefined ? r.assigneeId : (action.assigneeId ?? undefined);
          return { ...r, status: action.status, assigneeId };
        }),
      };
    case "addEmployee":
      return {
        ...state,
        employees: [
          ...state.employees,
          {
            id: `e${Date.now()}`,
            name: action.name,
            roleId: action.roleId,
            phone: action.phone,
            // Добавили — значит, вышел: сегодня на смене.
            workDays: [todayKey()],
          },
        ],
      };
    case "updateEmployee":
      return {
        ...state,
        employees: state.employees.map((e) =>
          e.id === action.id ? { ...e, roleId: action.roleId } : e,
        ),
      };
    case "toggleShift":
      return { ...state, employees: state.employees.map((e) => (e.id === action.id ? toggle(e, todayKey()) : e)) };
    case "deactivate":
      return {
        ...state,
        employees: state.employees.map((e) =>
          e.id === action.id ? { ...e, deactivatedAt: new Date().toISOString() } : e,
        ),
        requests: state.requests.map((r) =>
          r.assigneeId === action.id && OPEN_STATUSES.includes(r.status) ? { ...r, assigneeId: undefined } : r,
        ),
      };
    case "reactivate":
      return {
        ...state,
        employees: state.employees.map((e) => (e.id === action.id ? { ...e, deactivatedAt: undefined } : e)),
      };
    case "addRole": {
      const name = action.name.trim();
      if (!name || state.roles.some((r) => r.name.toLowerCase() === name.toLowerCase())) return state;
      return { ...state, roles: [...state.roles, { id: `r${Date.now()}`, name }] };
    }
    case "renameRole": {
      const name = action.name.trim();
      if (!name) return state;
      return { ...state, roles: state.roles.map((r) => (r.id === action.id ? { ...r, name } : r)) };
    }
    case "deleteRole":
      if (state.employees.some((e) => e.roleId === action.id)) return state;
      return { ...state, roles: state.roles.filter((r) => r.id !== action.id) };
    case "receive":
      if (action.qty <= 0) return state;
      return { ...state, moves: [...state.moves, move(action.itemId, action.qty, { kind: "receipt" })] };
    case "count": {
      const have = stockLevels(state.moves).get(action.itemId) ?? 0;
      const delta = round(action.actual - have);
      if (delta === 0) return state;
      return { ...state, moves: [...state.moves, move(action.itemId, delta, { kind: "count" })] };
    }
    case "addItem":
      return { ...state, stock: [...state.stock, action.item] };
    case "setParts":
      return {
        ...state,
        requests: state.requests.map((r) =>
          r.id === action.requestId && !r.partsWrittenOffAt
            ? { ...r, parts: action.lines.filter((l) => l.qty > 0) }
            : r,
        ),
      };
    case "writeOff": {
      const r = state.requests.find((x) => x.id === action.requestId);
      if (!r || r.partsWrittenOffAt || !r.parts?.length) return state;
      const reason = { kind: "writeoff", requestId: r.id } as const;
      return {
        ...state,
        moves: [...state.moves, ...r.parts.map((l) => move(l.itemId, -l.qty, reason))],
        requests: state.requests.map((x) =>
          x.id === r.id ? { ...x, partsWrittenOffAt: new Date().toISOString() } : x,
        ),
      };
    }
    case "undoWriteOff": {
      const r = state.requests.find((x) => x.id === action.requestId);
      if (!r?.partsWrittenOffAt || !r.parts?.length) return state;
      const reason = { kind: "return", requestId: r.id } as const;
      return {
        ...state,
        moves: [...state.moves, ...r.parts.map((l) => move(l.itemId, l.qty, reason))],
        requests: state.requests.map((x) => (x.id === r.id ? { ...x, partsWrittenOffAt: undefined } : x)),
      };
    }
    case "reset":
      return initial();
  }
}

// v3: склад и расход по заявкам. v2 склада не знает — по нему начинаем с
// посева, иначе раздел открылся бы пустым без единой позиции.
// v2: у сотрудника роль по id.
const KEY = "beepy-crm-v3";

let moveSeq = 0;

/** Движение по складу с отметкой времени. Id — время и счётчик: два
 *  движения одного списания создаются в одну миллисекунду. */
function move(itemId: string, delta: number, reason: StockMove["reason"]): StockMove {
  moveSeq += 1;
  return { id: `m${Date.now()}-${moveSeq}`, itemId, delta: round(delta), at: new Date().toISOString(), reason };
}

function toggle(e: Employee, day: string): Employee {
  const has = e.workDays.includes(day);
  return { ...e, workDays: has ? e.workDays.filter((d) => d !== day) : [...e.workDays, day].sort() };
}

function initial(): State {
  return { requests: seedRequests, employees: seedEmployees, roles: seedRoles, stock: seedStock, moves: seedMoves };
}

function load(): State {
  try {
    const raw = localStorage.getItem(KEY);
    if (raw) return JSON.parse(raw) as State;
  } catch {
    // Приватное окно или битые данные — начинаем с посева.
  }
  return initial();
}

const StoreContext = createContext<{ state: State; dispatch: (a: Action) => void } | null>(null);

export function StoreProvider({ children }: { children: ReactNode }) {
  const [state, dispatch] = useReducer(reducer, undefined, load);
  useEffect(() => {
    try {
      localStorage.setItem(KEY, JSON.stringify(state));
    } catch {
      // Хранилище недоступно — набросок работает и без него.
    }
  }, [state]);
  return <StoreContext.Provider value={{ state, dispatch }}>{children}</StoreContext.Provider>;
}

export function useStore() {
  const ctx = useContext(StoreContext);
  if (!ctx) throw new Error("useStore вне StoreProvider");
  return ctx;
}
