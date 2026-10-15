import { useEffect, useState } from "react";
import { Card, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";
import { PageHeader, SectionTitle } from "@/components/bits";
import { count, grouped, km } from "@/data/format";
import { api, type Day, type Totals } from "./api";

/** Сводка: сколько людей синхронизирует поездки и сколько ездят. Цифры —
 *  по всем аккаунтам разом; персональных данных на экране нет, поэтому и
 *  в журнал доступа этот экран не пишется. */
export function OverviewPage() {
  const [data, setData] = useState<{ totals: Totals; days: Day[] } | null>(null);
  const [failed, setFailed] = useState(false);

  useEffect(() => {
    api.stats().then(setData).catch(() => setFailed(true));
  }, []);

  if (failed) return <p className="py-16 text-center text-[13px] text-muted-foreground">Сервер не ответил</p>;
  if (!data) return null;
  const t = data.totals;

  const tiles = [
    { label: "Аккаунты", value: grouped(t.accounts), note: `+${t.new_week} за\u00A0неделю` },
    { label: "Активны за\u00A0неделю", value: grouped(t.active_week) },
    { label: "Поездки", value: grouped(t.trips), note: count(t.cars, "машина", "машины", "машин") },
    { label: "Проехали", value: km(t.meters / 1000) },
  ];

  const days = lastDays(14, data.days);
  const peak = Math.max(1, ...days.map((d) => d.trips));

  return (
    <div className="flex flex-col gap-6">
      <PageHeader title="Сводка" subtitle="Синхронизация поездок из приложения" />

      <div className="grid grid-cols-2 gap-3 lg:grid-cols-4">
        {tiles.map((tile) => (
          <Card key={tile.label} className="border border-border">
            <CardHeader>
              <CardDescription>{tile.label}</CardDescription>
              <CardTitle className="text-[22px] tabular-nums sm:text-[28px]">{tile.value}</CardTitle>
              {tile.note && <p className="text-[12px] text-muted-foreground">{tile.note}</p>}
            </CardHeader>
          </Card>
        ))}
      </div>

      <section className="flex flex-col gap-3">
        <SectionTitle>Поездки за две недели</SectionTitle>
        <div className="flex h-40 items-end gap-1.5 rounded-xl border border-border px-4 pb-3 pt-4">
          {days.map((d) => (
            <div key={d.day} className="flex h-full flex-1 flex-col items-center justify-end gap-1.5" title={`${d.label}: ${d.trips}`}>
              <span className="text-[11px] tabular-nums text-muted-foreground">{d.trips || ""}</span>
              <span
                className="w-full rounded-sm bg-primary/80 transition-[height] duration-500"
                style={{ height: `${Math.max(d.trips ? 6 : 2, (d.trips / peak) * 100)}%`, opacity: d.trips ? 1 : 0.25 }}
              />
              <span className="text-[10px] tabular-nums text-muted-foreground">{d.short}</span>
            </div>
          ))}
        </div>
      </section>
    </div>
  );
}

/** Ровно N последних дней по Москве, с нулями там, где поездок не было. */
function lastDays(n: number, days: Day[]) {
  const byDay = new Map(days.map((d) => [d.day, d]));
  const out: { day: string; trips: number; label: string; short: string }[] = [];
  const moscow = new Date(Date.now() + 3 * 3600_000);
  for (let i = n - 1; i >= 0; i--) {
    const d = new Date(Date.UTC(moscow.getUTCFullYear(), moscow.getUTCMonth(), moscow.getUTCDate() - i));
    const key = d.toISOString().slice(0, 10);
    out.push({
      day: key,
      trips: byDay.get(key)?.trips ?? 0,
      label: d.toLocaleDateString("ru-RU", { day: "numeric", month: "long", timeZone: "UTC" }),
      short: String(d.getUTCDate()),
    });
  }
  return out;
}
