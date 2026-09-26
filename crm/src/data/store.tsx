import { createContext, useContext, useEffect, useReducer, type ReactNode } from "react";
import { todayKey } from "./payroll";
import { seedEmployees, seedRequests, seedRoles } from "./seed";
import type { Employee, Pay, RequestStatus, RoleDef, ServiceRequest } from "./types";

// Хранилище наброска. Данные живут в браузере (localStorage): сервера нет,
// а персональные данные клиентов по 152-ФЗ должны лежать на сервере в РФ —
// до него это прототип интерфейса, не система учёта.

interface State {
  requests: ServiceRequest[];
  employees: Employee[];
  roles: RoleDef[];
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
  | { type: "addEmployee"; name: string; roleId: string; phone: string; pay: Pay }
  | { type: "updateEmployee"; id: string; roleId: string; pay: Pay }
  /** Отметить или снять день в табеле. «На смене» — тот же переключатель
   *  для сегодняшнего дня. */
  | { type: "toggleDay"; id: string; day: string }
  | { type: "toggleShift"; id: string }
  | { type: "addRole"; name: string }
  | { type: "renameRole"; id: string; name: string }
  /** Удалить можно только пустую роль: у сотрудника роль обязательна. */
  | { type: "deleteRole"; id: string }
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
            pay: action.pay,
            // Добавили — значит, вышел: сегодня отмечен в табеле.
            workDays: [todayKey()],
          },
        ],
      };
    case "updateEmployee":
      return {
        ...state,
        employees: state.employees.map((e) =>
          e.id === action.id ? { ...e, roleId: action.roleId, pay: action.pay } : e,
        ),
      };
    case "toggleDay":
      return { ...state, employees: state.employees.map((e) => (e.id === action.id ? toggle(e, action.day) : e)) };
    case "toggleShift":
      return { ...state, employees: state.employees.map((e) => (e.id === action.id ? toggle(e, todayKey()) : e)) };
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
    case "reset":
      return initial();
  }
}

// v2: у сотрудника роль по id, оплата и табель. Данные v1 этого не знают,
// и читать их значило бы получить сотрудников без ставки и роли.
const KEY = "beepy-crm-v2";

function toggle(e: Employee, day: string): Employee {
  const has = e.workDays.includes(day);
  return { ...e, workDays: has ? e.workDays.filter((d) => d !== day) : [...e.workDays, day].sort() };
}

function initial(): State {
  return { requests: seedRequests, employees: seedEmployees, roles: seedRoles };
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
