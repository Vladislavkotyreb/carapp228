import { ArrowRight } from "lucide-react";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { Avatar, Meter, PageHeader, SectionTitle, SourceBadge } from "@/components/bits";
import { ago, count } from "@/data/format";
import { useStore } from "@/data/store";
import { roleName } from "@/data/stats";
import { bySource, isOpen, kpi, load, topSystems } from "@/data/stats";
import { SOURCE_LABEL, type RequestSource } from "@/data/types";
import { isOnShift } from "@/data/payroll";

/** Дашборд: что требует внимания сейчас, откуда идут люди и кто чем занят.
 *  Сверху — то, на что надо отреагировать, ниже — то, на что посмотреть. */
export function DashboardPage({ onOpenRequest }: { onOpenRequest: (id: string) => void }) {
  const { state } = useStore();
  const k = kpi(state.requests);
  const sources = bySource(state.requests);
  const total = sources.app + sources.site;
  const loads = load(state.requests, state.employees);
  const maxLoad = Math.max(1, ...loads.map((l) => l.open));
  const systems = topSystems(state.requests);
  const maxSystem = Math.max(1, ...systems.map((s) => s.count));
  const waiting = state.requests
    .filter((r) => isOpen(r) && !r.assigneeId)
    .sort((a, b) => Date.parse(a.createdAt) - Date.parse(b.createdAt));

  const tiles = [
    { label: "Новые", value: k.fresh, hint: "ещё не взяты в работу" },
    { label: "Без исполнителя", value: k.unassigned, hint: "открытые, никто не назначен" },
    { label: "В работе", value: k.inWork, hint: "включая ожидание запчастей" },
    { label: "Готово за неделю", value: k.doneWeek, hint: "закрытые за 7 дней" },
  ];

  return (
    <div className="flex flex-col gap-6">
      <PageHeader title="Дашборд" subtitle="Автосервис «Фсервис» · Турчанинов пер., 6" />

      <div className="grid grid-cols-2 gap-3 lg:grid-cols-4">
        {tiles.map((t) => (
          <Card key={t.label} className="border border-border">
            <CardHeader>
              <CardDescription>{t.label}</CardDescription>
              <CardTitle className="text-[28px] tabular-nums">{t.value}</CardTitle>
            </CardHeader>
            <CardContent>
              <span className="text-[12px] text-muted-foreground">{t.hint}</span>
            </CardContent>
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
          <SectionTitle>Загрузка сотрудников</SectionTitle>
          <div className="flex flex-col gap-3 rounded-xl border border-border p-4">
            {loads.map(({ employee, open }) => (
              <div key={employee.id} className="flex items-center gap-3">
                <Avatar name={employee.name} muted={!isOnShift(employee)} />
                <span className="flex w-44 min-w-0 flex-col">
                  <span className="truncate text-[13px]">{employee.name}</span>
                  <span className="truncate text-[11px] text-muted-foreground">
                    {roleName(state.roles, employee.roleId)}
                    {isOnShift(employee) ? "" : " · не на смене"}
                  </span>
                </span>
                <Meter share={open / maxLoad} />
                <span className="w-6 text-right text-[13px] tabular-nums">{open}</span>
              </div>
            ))}
          </div>
        </section>

        <section className="flex flex-col gap-3">
          <SectionTitle>С чем приходят (по прослушиванию)</SectionTitle>
          <div className="flex flex-col gap-3 rounded-xl border border-border p-4">
            {systems.length === 0 && <p className="text-[13px] text-muted-foreground">Пока нет заявок из приложения</p>}
            {systems.map((s) => (
              <div key={s.system} className="flex items-center gap-3">
                <span className="w-52 shrink-0 truncate text-[13px]">{s.system}</span>
                <Meter share={s.count / maxSystem} tone="bg-amber-500" />
                <span className="w-6 text-right text-[13px] tabular-nums">{s.count}</span>
              </div>
            ))}
          </div>
        </section>
      </div>
    </div>
  );
}
