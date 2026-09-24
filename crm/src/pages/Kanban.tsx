import { useState, type DragEvent } from "react";
import { LayoutGroup, motion, useReducedMotion } from "framer-motion";
import { CalendarClock, ChevronDown, Flag, Globe, Smartphone, UserRound, UserX } from "lucide-react";
import { Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { Select, SelectContent, SelectItem, SelectTrigger } from "@/components/ui/select";
import { Tooltip } from "@/components/ui/tooltip";
import { Avatar } from "@/components/bits";
import { dateTime } from "@/data/format";
import { BOARD_COLUMNS, lanes, needsAttention, type GroupBy, type Lane } from "@/data/stats";
import { useStore } from "@/data/store";
import { SOURCE_LABEL, STATUS_LABEL, type RequestStatus, type ServiceRequest } from "@/data/types";
import { RequestDetail } from "@/pages/Requests";

// Доска по образцу Jira (рефы на Mobbin: Jira board, swimlanes): серые колонки
// фиксированной ширины с горизонтальной прокруткой, заголовки капсом со
// счётчиком, аватары-фильтр над доской, группировка в дорожки, в подвале
// карточки — «тип и ключ» слева и исполнитель справа.

const DRAG_TYPE = "application/x-beepy-request";
const GROUP_KEY = "beepy-crm-board-group";
/** «Без исполнителя» в фильтре аватаров — отдельный ключ рядом с id людей. */
const NOBODY = "__nobody__";
/** Один шаблон на заголовки и все дорожки, чтобы колонки стояли ровно.
 *  Колонки тянутся по ширине, а не 264px как в Jira: у нас их пять, и на
 *  обычном мониторе они помещаются без прокрутки; уже 220px — прокрутка. */
const COLUMNS_GRID = "grid grid-cols-[repeat(5,minmax(220px,1fr))] gap-2";

function readGroup(): GroupBy {
  try {
    const v = localStorage.getItem(GROUP_KEY);
    return v === "assignee" || v === "source" ? v : "none";
  } catch {
    return "none";
  }
}

export function KanbanBoard({ requests }: { requests: ServiceRequest[] }) {
  const { state, dispatch } = useStore();
  const [groupBy, setGroupByState] = useState<GroupBy>(readGroup);
  const [people, setPeople] = useState<Set<string>>(new Set());
  const [collapsed, setCollapsed] = useState<Set<string>>(new Set());
  const [dragging, setDragging] = useState<string | null>(null);
  const [over, setOver] = useState<string | null>(null);
  const [openId, setOpenId] = useState<string | null>(null);
  const reduceMotion = useReducedMotion();

  const setGroupBy = (v: GroupBy) => {
    setGroupByState(v);
    try {
      localStorage.setItem(GROUP_KEY, v);
    } catch {
      // Не запомнится — не страшно.
    }
  };

  // Фильтр аватаров: пустой — видно всех; иначе только выбранных людей
  // (и заявки без исполнителя, если выбран кружок «Без исполнителя»).
  const shown =
    people.size === 0
      ? requests
      : requests.filter((r) => people.has(r.assigneeId ?? NOBODY));
  const rows = lanes(shown, state.employees, groupBy);
  const open = state.requests.find((r) => r.id === openId);
  const employee = (id?: string) => state.employees.find((e) => e.id === id);

  function togglePerson(id: string) {
    setPeople((prev) => {
      const next = new Set(prev);
      if (next.has(id)) next.delete(id);
      else next.add(id);
      return next;
    });
  }

  function toggleLane(id: string) {
    setCollapsed((prev) => {
      const next = new Set(prev);
      if (next.has(id)) next.delete(id);
      else next.add(id);
      return next;
    });
  }

  function drop(e: DragEvent, status: RequestStatus, lane: Lane) {
    e.preventDefault();
    const id = e.dataTransfer.getData(DRAG_TYPE);
    setOver(null);
    setDragging(null);
    const r = state.requests.find((x) => x.id === id);
    if (!r) return;
    // Дорожка исполнителя переназначает, как в Jira; дорожки источника и
    // «все» исполнителя не трогают.
    const assigneeId = lane.assigneeId === undefined ? undefined : lane.assigneeId;
    const sameAssignee = assigneeId === undefined || (assigneeId ?? undefined) === r.assigneeId;
    if (r.status === status && sameAssignee) return;
    dispatch({ type: "move", id, status, assigneeId });
  }

  const columnCount = (status: RequestStatus) => shown.filter((r) => r.status === status).length;

  return (
    <>
      <div className="flex flex-wrap items-center gap-3">
        <div className="flex items-center" role="group" aria-label="Фильтр по исполнителю">
          {state.employees.map((e, i) => (
            <Tooltip key={e.id} content={e.name} side="bottom">
              <button
                type="button"
                aria-pressed={people.has(e.id)}
                aria-label={e.name}
                onClick={() => togglePerson(e.id)}
                style={{ zIndex: people.has(e.id) ? 20 : 10 - i }}
                className={
                  "relative -ml-1 flex items-center justify-center rounded-full border-2 border-background " +
                  "transition-transform first:ml-0 hover:-translate-y-0.5 " +
                  (people.has(e.id) ? "ring-2 ring-[#6B97FF]" : "")
                }
              >
                <Avatar name={e.name} muted={!e.onShift} size={28} />
              </button>
            </Tooltip>
          ))}
          <Tooltip content="Без исполнителя" side="bottom">
            <button
              type="button"
              aria-pressed={people.has(NOBODY)}
              aria-label="Без исполнителя"
              onClick={() => togglePerson(NOBODY)}
              className={
                "relative -ml-1 flex size-8 items-center justify-center rounded-full border-2 border-background transition-transform hover:-translate-y-0.5 " +
                (people.has(NOBODY) ? "bg-foreground text-background ring-2 ring-[#6B97FF]" : "bg-muted text-muted-foreground")
              }
            >
              <UserX className="size-3.5" aria-hidden />
            </button>
          </Tooltip>
          {people.size > 0 && (
            <button
              type="button"
              onClick={() => setPeople(new Set())}
              className="ml-3 text-[12px] text-muted-foreground hover:text-foreground"
            >
              Сбросить
            </button>
          )}
        </div>

        <div className="ml-auto flex items-center gap-2">
          <span className="text-[12px] text-muted-foreground">Группировка</span>
          <div className="w-40">
            <Select value={groupBy} onValueChange={(v) => setGroupBy(v as GroupBy)} size="compact">
              <SelectTrigger />
              <SelectContent>
                <SelectItem index={0} value="none">Нет</SelectItem>
                <SelectItem index={1} value="assignee">Исполнитель</SelectItem>
                <SelectItem index={2} value="source">Источник</SelectItem>
              </SelectContent>
            </Select>
          </div>
        </div>
      </div>

      <LayoutGroup>
        <div className="-mx-6 overflow-x-auto px-6 pb-4">
          <div className="flex min-w-full flex-col gap-2">
            {/* Заголовки колонок — один раз над всеми дорожками. */}
            <div className={COLUMNS_GRID}>
              {BOARD_COLUMNS.map((status) => (
                <div key={status} className="flex items-center gap-2 px-3 pt-1">
                  <h3 className="text-[11px] font-semibold uppercase tracking-wide text-muted-foreground">
                    {STATUS_LABEL[status]}
                  </h3>
                  <span className="rounded bg-muted px-1.5 text-[11px] tabular-nums text-muted-foreground">
                    {columnCount(status)}
                  </span>
                </div>
              ))}
            </div>

            {rows.length === 0 && (
              <p className="px-3 py-10 text-[13px] text-muted-foreground">Под эти фильтры заявок нет</p>
            )}

            {rows.map((lane) => {
              const isCollapsed = collapsed.has(lane.id);
              return (
                <section key={lane.id} aria-label={lane.label} className="flex flex-col gap-1.5">
                  {groupBy !== "none" && (
                    <button
                      type="button"
                      onClick={() => toggleLane(lane.id)}
                      aria-expanded={!isCollapsed}
                      className="flex w-fit items-center gap-2 rounded-md px-1 py-1 text-[13px] hover:bg-muted/50"
                    >
                      <ChevronDown
                        className={"size-4 text-muted-foreground transition-transform " + (isCollapsed ? "-rotate-90" : "")}
                        aria-hidden
                      />
                      {lane.assigneeId ? (
                        <Avatar name={lane.label} />
                      ) : lane.assigneeId === null ? (
                        <UserX className="size-4 text-muted-foreground" aria-hidden />
                      ) : lane.id === "app" ? (
                        <Smartphone className="size-4 text-muted-foreground" aria-hidden />
                      ) : (
                        <Globe className="size-4 text-muted-foreground" aria-hidden />
                      )}
                      <span className="font-medium">{lane.label}</span>
                      <span className="text-muted-foreground">({lane.requests.length})</span>
                    </button>
                  )}

                  {!isCollapsed && (
                    <div className={COLUMNS_GRID}>
                      {BOARD_COLUMNS.map((status) => {
                        const cell = `${lane.id}:${status}`;
                        const cards = lane.requests
                          .filter((r) => r.status === status)
                          .sort((a, b) => Date.parse(b.createdAt) - Date.parse(a.createdAt));
                        const isOver = over === cell && dragging !== null;
                        return (
                          <div
                            key={status}
                            aria-label={`${lane.label} — ${STATUS_LABEL[status]}`}
                            onDragOver={(e) => {
                              if (!e.dataTransfer.types.includes(DRAG_TYPE)) return;
                              e.preventDefault();
                              e.dataTransfer.dropEffect = "move";
                              if (over !== cell) setOver(cell);
                            }}
                            onDragLeave={(e) => {
                              if (!e.currentTarget.contains(e.relatedTarget as Node)) setOver(null);
                            }}
                            onDrop={(e) => drop(e, status, lane)}
                            className={
                              "flex flex-col gap-1.5 rounded-md p-1.5 transition-colors duration-150 " +
                              (groupBy === "none" ? "min-h-[460px] " : "min-h-[112px] ") +
                              (isOver ? "bg-muted ring-2 ring-inset ring-[#6B97FF]/60" : "bg-muted/40")
                            }
                          >
                            {cards.map((r) => (
                              <motion.div
                                key={r.id}
                                layout={!reduceMotion}
                                layoutId={r.id}
                                transition={{ type: "spring", stiffness: 500, damping: 40 }}
                              >
                                <JiraCard
                                  request={r}
                                  assigneeName={employee(r.assigneeId)?.name}
                                  dimmed={dragging === r.id}
                                  onDragStart={(e) => {
                                    e.dataTransfer.setData(DRAG_TYPE, r.id);
                                    e.dataTransfer.effectAllowed = "move";
                                    setDragging(r.id);
                                  }}
                                  onDragEnd={() => {
                                    setDragging(null);
                                    setOver(null);
                                  }}
                                  onOpen={() => setOpenId(r.id)}
                                />
                              </motion.div>
                            ))}
                          </div>
                        );
                      })}
                    </div>
                  )}
                </section>
              );
            })}
          </div>
        </div>
      </LayoutGroup>

      <Dialog open={open !== undefined} onOpenChange={(v) => !v && setOpenId(null)}>
        <DialogContent size="xl">
          {open && (
            <>
              <DialogHeader>
                <DialogTitle>
                  №{open.number} · {open.client.name} · {open.car.name}
                </DialogTitle>
                <DialogDescription>{open.summary}</DialogDescription>
              </DialogHeader>
              <RequestDetail request={open} />
            </>
          )}
        </DialogContent>
      </Dialog>
    </>
  );
}

/** Карточка как в Jira: сверху суть, под ней «метки», в подвале тип и ключ
 *  слева, флажок внимания и исполнитель справа. */
function JiraCard({
  request: r,
  assigneeName,
  dimmed,
  onDragStart,
  onDragEnd,
  onOpen,
}: {
  request: ServiceRequest;
  assigneeName?: string;
  dimmed: boolean;
  onDragStart: (e: DragEvent<HTMLButtonElement>) => void;
  onDragEnd: () => void;
  onOpen: () => void;
}) {
  const SourceIcon = r.payload.source === "app" ? Smartphone : Globe;
  const flagged = needsAttention(r);
  const preferredAt = r.payload.source === "site" ? r.payload.preferredAt : undefined;

  return (
    <button
      type="button"
      draggable
      onDragStart={onDragStart}
      onDragEnd={onDragEnd}
      onClick={onOpen}
      className={
        "flex w-full cursor-grab flex-col gap-2 rounded-md border border-border bg-background p-3 text-left " +
        "transition-[opacity,background-color,border-color] duration-150 hover:bg-muted/30 active:cursor-grabbing " +
        "focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-[#6B97FF] " +
        (dimmed ? "opacity-40" : "")
      }
    >
      <span className="line-clamp-2 text-[13px] leading-snug">{r.summary}</span>

      <span className="flex flex-wrap items-center gap-1">
        <span className="rounded border border-border px-1.5 text-[11px] uppercase tracking-wide text-muted-foreground">
          {r.car.name}
        </span>
        {preferredAt && (
          <span className="inline-flex items-center gap-1 rounded border border-border px-1.5 text-[11px] text-muted-foreground">
            <CalendarClock className="size-3" aria-hidden />
            {dateTime(preferredAt)}
          </span>
        )}
      </span>

      <span className="flex items-center gap-2">
        <span className="flex items-center gap-1.5 text-[12px] text-muted-foreground">
          <SourceIcon className="size-3.5" aria-label={SOURCE_LABEL[r.payload.source]} />
          <span className="font-medium tabular-nums">№{r.number}</span>
        </span>
        <span className="ml-auto flex items-center gap-2">
          {flagged && <Flag className="size-3.5 text-red-500" aria-label="Висит больше суток" />}
          {assigneeName ? (
            <span title={assigneeName}>
              <Avatar name={assigneeName} />
            </span>
          ) : (
            <span
              className="flex size-6 items-center justify-center rounded-full border border-dashed border-muted-foreground/50 text-muted-foreground"
              title="Не назначен"
            >
              <UserRound className="size-3.5" aria-hidden />
            </span>
          )}
        </span>
      </span>
    </button>
  );
}
