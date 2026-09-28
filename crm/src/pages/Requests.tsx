import { useMemo, useState } from "react";
import { Columns3, Globe, List, Search, Smartphone } from "lucide-react";
import { InputField, InputGroup } from "@/components/ui/input-group";
import { Select, SelectContent, SelectItem, SelectTrigger } from "@/components/ui/select";
import { TabItem, Tabs, TabsList } from "@/components/ui/tabs";
import { Avatar, PageHeader, StatusBadge } from "@/components/bits";
import { ago, count } from "@/data/format";
import { useStore } from "@/data/store";
import { KanbanBoard } from "@/pages/Kanban";
import { RequestPanel } from "@/pages/RequestPanel";
import type { Employee, RequestSource, RequestStatus, ServiceRequest } from "@/data/types";

type StatusFilter = "all" | "new" | "work" | "done" | "cancelled";

const FILTERS: { value: StatusFilter; label: string; match: (s: RequestStatus) => boolean }[] = [
  { value: "all", label: "Все", match: () => true },
  { value: "new", label: "Новые", match: (s) => s === "new" },
  { value: "work", label: "В работе", match: (s) => s === "in_progress" || s === "waiting_parts" },
  { value: "done", label: "Готово", match: (s) => s === "done" },
  { value: "cancelled", label: "Отменённые", match: (s) => s === "cancelled" },
];

type View = "list" | "board";
const VIEW_KEY = "beepy-crm-requests-view";

function readView(): View {
  try {
    return localStorage.getItem(VIEW_KEY) === "board" ? "board" : "list";
  } catch {
    return "list";
  }
}

/** Заявки сервиса. Список — таблица с явными границами: строка отвечает на
 *  «кто, на чём, с чем, у кого». Клик открывает заявку панелью справа
 *  (`RequestPanel`). Аккордеон в строке заменён 28.09.2026: раскрытая
 *  заявка сливалась с соседними, и было непонятно, что к чему относится.
 *  `initiallyOpen` — заявка, которую открыть при входе (дашборд, ⌘K). */
export function RequestsPage({ initiallyOpen }: { initiallyOpen: string }) {
  const { state } = useStore();
  const [filter, setFilter] = useState<StatusFilter>("all");
  const [source, setSource] = useState<"any" | RequestSource>("any");
  const [query, setQuery] = useState("");
  const [openId, setOpenId] = useState<string | null>(initiallyOpen || null);
  // Новая заявка на открытие пришла снаружи (⌘K при уже открытых заявках) —
  // открываем её. Без эффекта: так значение есть в том же кадре.
  const [seen, setSeen] = useState(initiallyOpen);
  if (initiallyOpen !== seen) {
    setSeen(initiallyOpen);
    setOpenId(initiallyOpen || null);
  }
  // Вид запоминается: приёмка обычно живёт в одном из двух весь день.
  const [view, setViewState] = useState<View>(readView);
  const setView = (v: View) => {
    setViewState(v);
    try {
      localStorage.setItem(VIEW_KEY, v);
    } catch {
      // Не запомнится — не страшно.
    }
  };

  const visible = useMemo(() => {
    const match = FILTERS.find((f) => f.value === filter)!.match;
    const q = query.trim().toLowerCase();
    return state.requests
      // На доске статусы — это колонки, фильтр по ним там не нужен.
      .filter((r) => view === "board" || match(r.status))
      .filter((r) => source === "any" || r.payload.source === source)
      .filter(
        (r) =>
          !q ||
          [r.client.name, r.car.name, r.car.plate ?? "", r.summary, String(r.number)]
            .join(" ")
            .toLowerCase()
            .includes(q),
      )
      .sort((a, b) => Date.parse(b.createdAt) - Date.parse(a.createdAt));
  }, [state.requests, filter, source, query, view]);

  const employee = (id?: string) => state.employees.find((e) => e.id === id);
  const opened = state.requests.find((r) => r.id === openId);

  return (
    <div className="flex flex-col gap-5">
      <PageHeader
        title="Заявки"
        subtitle={`${count(visible.length, "заявка", "заявки", "заявок")} · из приложения Beepy и с сайта-визитки`}
        actions={
          <Tabs value={view} onValueChange={(v) => setView(v as View)}>
            <TabsList>
              <TabItem value="list" label="Список" icon={List} />
              <TabItem value="board" label="Канбан" icon={Columns3} />
            </TabsList>
          </Tabs>
        }
      />

      <div className="flex flex-wrap items-center gap-3">
        {view === "list" && (
          // На телефоне пять статусов не влезают — ряд прокручивается вбок.
          <div className="-mx-4 max-w-[calc(100%+2rem)] overflow-x-auto px-4 scrollbar-hide md:mx-0 md:max-w-none md:px-0">
          <Tabs value={filter} onValueChange={(v) => setFilter(v as StatusFilter)}>
            <TabsList>
              {FILTERS.map((f) => (
                <TabItem key={f.value} value={f.value} label={f.label} />
              ))}
            </TabsList>
          </Tabs>
          </div>
        )}

        <div className="ml-auto flex items-center gap-2">
          <div className="w-44">
            <Select value={source} onValueChange={(v) => setSource(v as "any" | RequestSource)} size="compact">
              <SelectTrigger placeholder="Источник" />
              <SelectContent>
                <SelectItem index={0} value="any">Все источники</SelectItem>
                <SelectItem index={1} value="app">Приложение</SelectItem>
                <SelectItem index={2} value="site">Сайт</SelectItem>
              </SelectContent>
            </Select>
          </div>
          <InputGroup size="compact" className="w-56">
            <InputField
              index={0}
              label="Поиск"
              labelHidden
              icon={Search}
              placeholder="Клиент, машина, номер"
              value={query}
              onChange={setQuery}
            />
          </InputGroup>
        </div>
      </div>

      {view === "board" ? (
        <KanbanBoard requests={visible} onOpen={setOpenId} />
      ) : visible.length === 0 ? (
        <p className="py-16 text-center text-[13px] text-muted-foreground">Под эти фильтры заявок нет</p>
      ) : (
        <RequestTable requests={visible} selectedId={openId} onOpen={setOpenId} employee={employee} />
      )}

      {opened && <RequestPanel request={opened} onClose={() => setOpenId(null)} />}
    </div>
  );
}

type Col = { title: string; className: string };

const COLS: Col[] = [
  { title: "№", className: "w-[76px]" },
  { title: "Клиент и машина", className: "w-[220px]" },
  { title: "С чем приехал", className: "min-w-[240px]" },
  { title: "Откуда", className: "w-[130px]" },
  { title: "Статус", className: "w-[140px]" },
  { title: "Исполнитель", className: "w-[160px]" },
  { title: "Пришла", className: "w-[110px] text-right" },
];

/** Таблица заявок: рамка, шапка на подложке, границы между строками и
 *  колонками. Вся строка — кнопка: клик или Enter открывает заявку. На
 *  узком экране таблица прокручивается вбок, колонки не сжимаются в кашу. */
function RequestTable({
  requests,
  selectedId,
  onOpen,
  employee,
}: {
  requests: ServiceRequest[];
  selectedId: string | null;
  onOpen: (id: string) => void;
  employee: (id?: string) => Employee | undefined;
}) {
  const cell = "border-r border-border px-3 last:border-r-0";
  return (
    <div className="overflow-x-auto rounded-lg border border-border">
      <table className="w-full min-w-[980px] border-collapse text-[13px]">
        <thead>
          <tr className="border-b border-border bg-muted/60">
            {COLS.map((c) => (
              <th
                key={c.title}
                scope="col"
                className={`${cell} ${c.className} h-9 text-left text-[12px] font-medium text-muted-foreground`}
              >
                {c.title}
              </th>
            ))}
          </tr>
        </thead>
        <tbody>
          {requests.map((r) => {
            const who = employee(r.assigneeId);
            const selected = r.id === selectedId;
            const SourceIcon = r.payload.source === "app" ? Smartphone : Globe;
            return (
              <tr
                key={r.id}
                tabIndex={0}
                aria-selected={selected}
                onClick={() => onOpen(r.id)}
                onKeyDown={(e) => {
                  if (e.key === "Enter" || e.key === " ") {
                    e.preventDefault();
                    onOpen(r.id);
                  }
                }}
                className={
                  "h-12 cursor-pointer border-b border-border outline-none transition-colors last:border-b-0 hover:bg-hover focus-visible:bg-hover " +
                  (selected ? "bg-primary/10 shadow-[inset_2px_0_0_var(--primary)]" : "")
                }
              >
                <td className={`${cell} font-medium tabular-nums`}>№{r.number}</td>
                <td className={cell}>
                  <span className="flex min-w-0 flex-col">
                    <span className="truncate font-medium">{r.client.name}</span>
                    <span className="truncate text-[12px] text-muted-foreground">
                      {[r.car.name, r.car.plate].filter(Boolean).join(" · ")}
                    </span>
                  </span>
                </td>
                <td className={`${cell} max-w-0`}>
                  <span className="block truncate">{r.summary}</span>
                </td>
                <td className={cell}>
                  <span className="inline-flex items-center gap-1.5 text-[12px] text-muted-foreground">
                    <SourceIcon className="size-3.5" aria-hidden />
                    {r.payload.source === "app" ? "Приложение" : "Сайт"}
                  </span>
                </td>
                <td className={cell}>
                  <StatusBadge status={r.status} />
                </td>
                <td className={cell}>
                  {who ? (
                    <span className="flex min-w-0 items-center gap-2">
                      <Avatar name={who.name} size={20} muted={Boolean(who.deactivatedAt)} />
                      <span className="truncate text-[12px]">{who.name.split(" ")[0]}</span>
                    </span>
                  ) : (
                    <span className="text-[12px] text-amber-600 dark:text-amber-400">Не назначен</span>
                  )}
                </td>
                <td className={`${cell} text-right text-[12px] text-muted-foreground`}>{ago(r.createdAt)}</td>
              </tr>
            );
          })}
        </tbody>
      </table>
    </div>
  );
}
