import { createContext, useContext, useEffect, useReducer, type ReactNode } from "react";
import { seedEmployees, seedRequests } from "./seed";
import type { Employee, RequestStatus, Role, ServiceRequest } from "./types";

// Хранилище наброска. Данные живут в браузере (localStorage): сервера нет,
// а персональные данные клиентов по 152-ФЗ должны лежать на сервере в РФ —
// до него это прототип интерфейса, не система учёта.

interface State {
  requests: ServiceRequest[];
  employees: Employee[];
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
  | { type: "addEmployee"; name: string; role: Role; phone: string }
  | { type: "toggleShift"; id: string }
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
          { id: `e${Date.now()}`, name: action.name, role: action.role, phone: action.phone, onShift: true },
        ],
      };
    case "toggleShift":
      return {
        ...state,
        employees: state.employees.map((e) => (e.id === action.id ? { ...e, onShift: !e.onShift } : e)),
      };
    case "reset":
      return initial();
  }
}

const KEY = "beepy-crm-v1";

function initial(): State {
  return { requests: seedRequests, employees: seedEmployees };
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
