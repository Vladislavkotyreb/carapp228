import { useMemo, useState } from "react";
import { CalendarClock, Columns3, List, Phone, Search } from "lucide-react";
import {
  AccordionContent,
  AccordionGroup,
  AccordionItem,
  AccordionTrigger,
} from "@/components/ui/accordion";
import {
  Combobox,
  ComboboxContent,
  ComboboxEmpty,
  ComboboxInput,
  ComboboxItem,
  ComboboxList,
} from "@/components/ui/combobox";
import { InputField, InputGroup } from "@/components/ui/input-group";
import { Select, SelectContent, SelectItem, SelectTrigger } from "@/components/ui/select";
import { TabItem, Tabs, TabsList } from "@/components/ui/tabs";
import { Avatar, Meter, PageHeader, SectionTitle, SourceBadge, StatusBadge } from "@/components/bits";
import { ago, count, dateTime, km, percent, tel } from "@/data/format";
import { useStore } from "@/data/store";
import { KanbanBoard } from "@/pages/Kanban";
import {
  ROLE_LABEL,
  STATUS_LABEL,
  type Employee,
  type RequestSource,
  type RequestStatus,
  type ServiceRequest,
} from "@/data/types";

type StatusFilter = "all" | "new" | "work" | "done" | "cancelled";

const FILTERS: { value: StatusFilter; label: string; match: (s: RequestStatus) => boolean }[] = [
  { value: "all", label: "Все", match: () => true },
  { value: "new", label: "Новые", match: (s) => s === "new" },
  { value: "work", label: "В работе", match: (s) => s === "in_progress" || s === "waiting_parts" },
  { value: "done", label: "Готово", match: (s) => s === "done" },
  { value: "cancelled", label: "Отменённые", match: (s) => s === "cancelled" },
];

const STATUSES = Object.keys(STATUS_LABEL) as RequestStatus[];

type View = "list" | "board";
const VIEW_KEY = "beepy-crm-requests-view";

function readView(): View {
  try {
    return localStorage.getItem(VIEW_KEY) === "board" ? "board" : "list";
  } catch {
    return "list";
  }
}

/** Заявки сервиса. Список — аккордеон: строка отвечает на «кто, с чем,
 *  откуда, у кого», раскрытие — на «что именно и что с этим делать». */
/** `initiallyOpen` — заявка, которую раскрыть при входе (переход с дашборда).
 *  Дальше раскрытием владеет сама группа: управляемое `value` она в этой
 *  версии не слушает — щелчки раскрывали строку мимо `onValueChange`. */
export function RequestsPage({ initiallyOpen }: { initiallyOpen: string }) {
  const { state } = useStore();
  const [filter, setFilter] = useState<StatusFilter>("all");
  const [source, setSource] = useState<"any" | RequestSource>("any");
  const [query, setQuery] = useState("");
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
          <Tabs value={filter} onValueChange={(v) => setFilter(v as StatusFilter)}>
            <TabsList>
              {FILTERS.map((f) => (
                <TabItem key={f.value} value={f.value} label={f.label} />
              ))}
            </TabsList>
          </Tabs>
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
        <KanbanBoard requests={visible} />
      ) : visible.length === 0 ? (
        <p className="py-16 text-center text-[13px] text-muted-foreground">Под эти фильтры заявок нет</p>
      ) : (
        <AccordionGroup
          type="single"
          collapsible
          key={initiallyOpen}
          defaultValue={initiallyOpen}
          highlight="trigger"
          // По умолчанию группа шириной w-72 — под боковую панель, а не под список.
          className="w-full"
        >
          {visible.map((r, i) => (
            <AccordionItem key={r.id} value={r.id} index={i}>
              {/* Триггер кладёт содержимое в inline-grid с колонкой по ширине
                  содержимого — и колонка «клиент · проблема» схлопывалась в
                  ноль. Растягиваем её снаружи, не правя библиотеку. */}
              <AccordionTrigger className="[&>span:first-child]:grid-cols-[minmax(0,1fr)]">
                <RequestRow request={r} assignee={employee(r.assigneeId)} />
              </AccordionTrigger>
              <AccordionContent>
                <RequestDetail request={r} />
              </AccordionContent>
            </AccordionItem>
          ))}
        </AccordionGroup>
      )}
    </div>
  );
}

/** Строка заявки внутри триггера. Только текст: в кнопке-триггере не может
 *  быть других кнопок, все действия — в раскрытии. */
function RequestRow({ request: r, assignee }: { request: ServiceRequest; assignee?: Employee }) {
  return (
    <span className="grid w-full grid-cols-[84px_minmax(0,1fr)_104px_120px_150px] items-center gap-4 text-left">
      <span className="flex flex-col">
        <span className="text-[13px] font-medium tabular-nums">№{r.number}</span>
        <span className="text-[11px] text-muted-foreground">{ago(r.createdAt)}</span>
      </span>
      <span className="flex min-w-0 flex-col">
        <span className="truncate text-[13px] font-medium">
          {r.client.name} · {r.car.name}
        </span>
        <span className="truncate text-[12px] text-muted-foreground">{r.summary}</span>
      </span>
      <SourceBadge source={r.payload.source} />
      <span>
        <StatusBadge status={r.status} />
      </span>
      <span className="flex min-w-0 items-center gap-2">
        {assignee ? (
          <>
            <Avatar name={assignee.name} />
            <span className="truncate text-[12px]">{assignee.name.split(" ")[0]}</span>
          </>
        ) : (
          <span className="text-[12px] text-muted-foreground">Не назначен</span>
        )}
      </span>
    </span>
  );
}

export function RequestDetail({ request: r }: { request: ServiceRequest }) {
  const { state, dispatch } = useStore();
  // Сначала те, кто на смене: назначать на того, кого нет, — отложить заявку.
  const people = [...state.employees].sort((a, b) => Number(b.onShift) - Number(a.onShift));
  const items = people.map((e) => ({
    value: e.id,
    label: `${e.name} — ${ROLE_LABEL[e.role]}${e.onShift ? "" : " (не на смене)"}`,
  }));

  return (
    <div className="grid gap-6 pb-2 pt-1 md:grid-cols-[minmax(0,1fr)_280px]">
      <section className="flex flex-col gap-3">
        {r.payload.source === "app" ? (
          <>
            <SectionTitle>Итоги прослушивания в Beepy</SectionTitle>
            <ul className="flex flex-col gap-3">
              {r.payload.findings.map((f) => (
                <li key={f.title} className="flex flex-col gap-1.5">
                  <div className="flex items-baseline justify-between gap-3">
                    <span className="text-[13px] font-medium">
                      {f.title}
                      <span className="font-normal text-muted-foreground"> · {f.system}</span>
                    </span>
                    <span className="text-[12px] tabular-nums text-muted-foreground">{percent(f.confidence)}</span>
                  </div>
                  <Meter share={f.confidence} tone={f.confidence >= 0.7 ? "bg-amber-500" : "bg-muted-foreground"} />
                  <p className="text-[12px] text-muted-foreground">{f.advice}</p>
                </li>
              ))}
            </ul>
          </>
        ) : (
          <>
            <SectionTitle>Запись с сайта</SectionTitle>
            <p className="text-[13px] leading-relaxed">{r.payload.comment}</p>
            {r.payload.preferredAt && (
              <p className="flex items-center gap-1.5 text-[12px] text-muted-foreground">
                <CalendarClock className="size-3.5" aria-hidden />
                Удобно: {dateTime(r.payload.preferredAt)}
              </p>
            )}
          </>
        )}
      </section>

      <aside className="flex flex-col gap-4">
        <div className="flex flex-col gap-1">
          <SectionTitle>Клиент</SectionTitle>
          <span className="text-[13px] font-medium">{r.client.name}</span>
          <a href={tel(r.client.phone)} className="inline-flex items-center gap-1.5 text-[13px] hover:underline">
            <Phone className="size-3.5" aria-hidden />
            {r.client.phone}
          </a>
          <span className="text-[12px] text-muted-foreground">
            {[r.car.name, r.car.plate, r.car.mileage ? km(r.car.mileage) : undefined].filter(Boolean).join(" · ")}
          </span>
          <span className="text-[12px] text-muted-foreground">Пришла {dateTime(r.createdAt)}</span>
        </div>

        <div className="flex flex-col gap-1.5">
          <SectionTitle>Исполнитель</SectionTitle>
          <Combobox
            items={items}
            value={r.assigneeId ?? ""}
            onValueChange={(v) => dispatch({ type: "assign", id: r.id, employeeId: v || undefined })}
            size="compact"
          >
            <ComboboxInput placeholder="Назначить сотрудника" clearable />
            <ComboboxContent>
              <ComboboxList>
                {(item) =>
                  typeof item === "string" ? null : (
                    <ComboboxItem key={item.value} value={item.value}>
                      {item.label}
                    </ComboboxItem>
                  )
                }
              </ComboboxList>
              <ComboboxEmpty>Никого не нашли</ComboboxEmpty>
            </ComboboxContent>
          </Combobox>
        </div>

        <div className="flex flex-col gap-1.5">
          <SectionTitle>Статус</SectionTitle>
          <Select
            value={r.status}
            onValueChange={(v) => dispatch({ type: "setStatus", id: r.id, status: v as RequestStatus })}
            size="compact"
          >
            <SelectTrigger />
            <SelectContent>
              {STATUSES.map((s, i) => (
                <SelectItem key={s} index={i} value={s}>
                  {STATUS_LABEL[s]}
                </SelectItem>
              ))}
            </SelectContent>
          </Select>
        </div>
      </aside>
    </div>
  );
}
