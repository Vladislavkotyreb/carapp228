import { useState } from "react";
import { ArrowRight } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Card, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Avatar, Meter, PageHeader, SectionTitle, SourceBadge } from "@/components/bits";
import { ago, count } from "@/data/format";
import { useStore } from "@/data/store";
import { roleName } from "@/data/stats";
import { bySource, isOpen, kpi, load, topSystems } from "@/data/stats";
import { SOURCE_LABEL, type Employee, type RequestSource } from "@/data/types";
import { isActive, isOnShift } from "@/data/staff";

/** Дашборд: что требует внимания сейчас, откуда идут люди и кто чем занят.
 *  Сверху — то, на что надо отреагировать, ниже — то, на что посмотреть. */
export function DashboardPage({ onOpenRequest }: { onOpenRequest: (id: string) => void }) {
  const { state } = useStore();
  const k = kpi(state.requests);
  const sources = bySource(state.requests);
  const total = sources.app + sources.site;
  const loads = load(state.requests, state.employees.filter(isActive));
  const maxLoad = Math.max(1, ...loads.map((l) => l.open));
  const systems = topSystems(state.requests);
  const waiting = state.requests
    .filter((r) => isOpen(r) && !r.assigneeId)
    .sort((a, b) => Date.parse(a.createdAt) - Date.parse(b.createdAt));

  const tiles = [
    { label: "Новые", value: k.fresh },
    { label: "Без исполнителя", value: k.unassigned },
    { label: "В работе", value: k.inWork },
    { label: "Готово за неделю", value: k.doneWeek },
  ];

  return (
    <div className="flex flex-col gap-6">
      <PageHeader title="Дашборд" />

      <div className="grid grid-cols-2 gap-3 lg:grid-cols-4">
        {tiles.map((t) => (
          <Card key={t.label} className="border border-border">
            <CardHeader>
              <CardDescription>{t.label}</CardDescription>
              <CardTitle className="text-[28px] tabular-nums">{t.value}</CardTitle>
            </CardHeader>
          </Card>
        ))}
      </div>

      <div className="grid gap-6 lg:grid-cols-[minmax(0,1.4fr)_minmax(0,1fr)]">
        <section className="flex flex-col gap-3">
          <SectionTitle>Ждут исполнителя</SectionTitle>
          {waiting.length === 0 ? (
            <p className="text-[13px] text-muted-foreground">Все открытые заявки назначены</p>
          ) : (
            <ul className="flex flex-col divide-y divide-border rounded-xl border border-border">
              {waiting.map((r) => (
                <li key={r.id} className="flex items-center gap-4 px-4 py-3">
                  <span className="flex min-w-0 flex-1 flex-col">
                    <span className="truncate text-[13px] font-medium">
                      №{r.number} · {r.client.name} · {r.car.name}
                    </span>
                    <span className="truncate text-[12px] text-muted-foreground">{r.summary}</span>
                  </span>
                  <SourceBadge source={r.payload.source} />
                  <span className="w-20 text-right text-[12px] text-muted-foreground">{ago(r.createdAt)}</span>
                  <Button variant="secondary" size="compact" trailingIcon={ArrowRight} onClick={() => onOpenRequest(r.id)}>
                    Назначить
                  </Button>
                </li>
              ))}
            </ul>
          )}
        </section>

        <section className="flex flex-col gap-3">
          <SectionTitle>Откуда заявки</SectionTitle>
          <div className="flex flex-col gap-3 rounded-xl border border-border p-4">
            {(["app", "site"] as RequestSource[]).map((s) => (
              <div key={s} className="flex flex-col gap-1.5">
                <div className="flex justify-between text-[13px]">
                  <span>{s === "app" ? "Приложение Beepy · после прослушивания" : "Сайт-визитка из Яндекс Карт"}</span>
                  <span className="tabular-nums text-muted-foreground">{sources[s]}</span>
                </div>
                <Meter share={total ? sources[s] / total : 0} tone={s === "app" ? "bg-amber-500" : "bg-sky-500"} />
              </div>
            ))}
            <p className="text-[12px] text-muted-foreground">
              {count(total, "заявка", "заявки", "заявок")} всего; {SOURCE_LABEL.app.toLowerCase()} приносит заявки
              уже с диагнозом.
            </p>
          </div>
        </section>
      </div>

      <div className="grid gap-6 lg:grid-cols-2">
        <section className="flex flex-col gap-3">
          <SectionTitle>Загрузка сотрудников · открытые заявки</SectionTitle>
          <LoadColumns loads={loads} max={maxLoad} roleOf={(id) => roleName(state.roles, id)} />
        </section>

        <section className="flex flex-col gap-3">
          <SectionTitle>С чем приходят · по прослушиванию</SectionTitle>
          {systems.length === 0 ? (
            <p className="rounded-xl border border-border p-4 text-[13px] text-muted-foreground">
              Пока нет заявок из приложения
            </p>
          ) : (
            <SystemsDonut systems={systems} />
          )}
        </section>
      </div>
    </div>
  );
}

/** Столбцы: сотрудник — столбец высотой по открытым заявкам, число над
 *  ним, аватар и имя под ним. Кто не на смене — приглушён. Сравнивать
 *  высоты глазу проще, чем длины полос в строках (правка 28.09.2026). */
function LoadColumns({
  loads,
  max,
  roleOf,
}: {
  loads: { employee: Employee; open: number }[];
  max: number;
  roleOf: (roleId: string) => string;
}) {
  const H = 140;
  return (
    <div className="flex h-full flex-col rounded-xl border border-border p-4">
      <div className="relative flex flex-1 items-end gap-3" style={{ minHeight: H + 24 }}>
        {/* Линии сетки: 0, половина, максимум. */}
        {[0, 0.5, 1].map((f) => (
          <span
            key={f}
            className="pointer-events-none absolute inset-x-0 border-t border-dashed border-border"
            style={{ bottom: f * H }}
            aria-hidden
          />
        ))}
        {loads.map(({ employee, open }) => {
          const on = isOnShift(employee);
          return (
            <div key={employee.id} className="relative flex flex-1 flex-col items-center justify-end gap-1.5">
              <span className="text-[13px] font-medium tabular-nums">{open}</span>
              <span
                className={"w-full max-w-10 rounded-t-md transition-[height] duration-500 " + (on ? "bg-primary" : "bg-muted-foreground/40")}
                style={{ height: Math.max(3, (open / max) * H) }}
                title={`${employee.name}: ${open}`}
              />
            </div>
          );
        })}
      </div>
      <div className="mt-2 flex gap-3 border-t border-border pt-3">
        {loads.map(({ employee }) => {
          const on = isOnShift(employee);
          return (
            <div key={employee.id} className="flex min-w-0 flex-1 flex-col items-center gap-1 text-center">
              <Avatar name={employee.name} muted={!on} size={22} />
              <span className="w-full truncate text-[12px]">{employee.name.split(" ")[0]}</span>
              <span className="w-full truncate text-[11px] text-muted-foreground">
                {on ? roleOf(employee.roleId) : "не на смене"}
              </span>
            </div>
          );
        })}
      </div>
    </div>
  );
}

const DONUT_TONES = ["#f59e0b", "#5e6ad2", "#10b981", "#ec4899", "#0ea5e9", "#8b5cf6"];

/** Кольцо: доли систем, в центре — сколько заявок из приложения. Рядом —
 *  легенда с числом и процентом, чтобы цвет не приходилось угадывать. */
function SystemsDonut({ systems }: { systems: { system: string; count: number }[] }) {
  // Наведённая система — на кольце или в легенде, это одно состояние: её
  // сегмент утолщается, остальные гаснут, строка легенды подсвечена, в
  // центре — её число и доля вместо общего итога.
  const [active, setActive] = useState<number | null>(null);
  const total = systems.reduce((sum, s) => sum + s.count, 0);
  const R = 52;
  const C = 2 * Math.PI * R;
  // Начало каждого сегмента — сумма длин предыдущих.
  const lens = systems.map((s) => (s.count / total) * C);
  const starts = lens.map((_, i) => lens.slice(0, i).reduce((a, b) => a + b, 0));
  const tone = (i: number) => DONUT_TONES[i % DONUT_TONES.length];
  const share = (n: number) => `${Math.round((n / total) * 100)}%`;
  const dim = (i: number) => active !== null && active !== i;
  const current = active !== null ? systems[active] : null;

  return (
    <div
      className="flex h-full flex-wrap items-center gap-6 rounded-xl border border-border p-4"
      onMouseLeave={() => setActive(null)}
    >
      <svg viewBox="0 0 140 140" className="size-36 shrink-0" role="img" aria-label="Доли систем">
        <g transform="rotate(-90 70 70)">
          <circle cx="70" cy="70" r={R} fill="none" stroke="var(--muted)" strokeWidth="18" />
          {systems.map((s, i) => (
            // Зазор в 2 pt между сегментами — иначе соседние цвета сливаются.
            <circle
              key={s.system}
              cx="70"
              cy="70"
              r={R}
              fill="none"
              stroke={tone(i)}
              strokeWidth={active === i ? 22 : 18}
              strokeDasharray={`${Math.max(0, lens[i] - 2)} ${C}`}
              strokeDashoffset={-starts[i]}
              className="cursor-pointer transition-[opacity,stroke-width] duration-200"
              style={{ opacity: dim(i) ? 0.2 : 1 }}
              onMouseEnter={() => setActive(i)}
            >
              <title>{`${s.system}: ${s.count}`}</title>
            </circle>
          ))}
        </g>
        <text x="70" y={current ? 64 : 70} className="fill-foreground" textAnchor="middle" dominantBaseline="central" fontSize="22" fontWeight="600">
          {current ? current.count : total}
        </text>
        {current && (
          <text x="70" y="86" className="fill-muted-foreground" textAnchor="middle" dominantBaseline="central" fontSize="11">
            {share(current.count)}
          </text>
        )}
      </svg>
      <ul className="flex min-w-0 flex-1 flex-col gap-1">
        {systems.map((s, i) => (
          <li
            key={s.system}
            onMouseEnter={() => setActive(i)}
            className={
              "flex cursor-default items-center gap-2.5 rounded-md px-2 py-1.5 text-[13px] transition-[opacity,background-color] duration-200 " +
              (active === i ? "bg-hover" : "") +
              (dim(i) ? " opacity-40" : "")
            }
          >
            <span className="size-2.5 shrink-0 rounded-sm" style={{ background: tone(i) }} />
            <span className="min-w-0 flex-1 truncate">{s.system}</span>
            <span className="tabular-nums">{s.count}</span>
            <span className="w-10 text-right tabular-nums text-muted-foreground">{share(s.count)}</span>
          </li>
        ))}
      </ul>
    </div>
  );
}
