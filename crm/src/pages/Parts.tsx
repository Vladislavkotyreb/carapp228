import { useMemo, useState } from "react";
import { Minus, PackageMinus, Plus, ScanBarcode, Undo2, Wand2, X } from "lucide-react";
import { Button } from "@/components/ui/button";
import { InputField, InputGroup } from "@/components/ui/input-group";
import { dateTime, qty } from "@/data/format";
import {
  applyTemplate,
  findByCode,
  fitsCar,
  linesCost,
  mergeLines,
  round,
  shortages,
  stockLevels,
  WORK_TEMPLATES,
} from "@/data/inventory";
import { rub } from "@/data/staff";
import { useStore } from "@/data/store";
import { UNIT_LABEL, type PartLine, type ServiceRequest, type StockItem } from "@/data/types";

/** Расход по заявке. Мастер не считает литры: шаблон работы кладёт масло по
 *  норме для этой машины, фильтр под её марку и шайбу, — остаётся поправить
 *  число, если долил, и нажать «Списать». Позицию сверх шаблона — сканом
 *  упаковки или поиском. Экран один и тот же на компьютере и на телефоне. */
export function PartsSection({ request: r }: { request: ServiceRequest }) {
  const { state, dispatch } = useStore();
  const levels = useMemo(() => stockLevels(state.moves), [state.moves]);
  const [notes, setNotes] = useState<string[]>([]);
  const [query, setQuery] = useState("");

  const lines = r.parts ?? [];
  const locked = Boolean(r.partsWrittenOffAt);
  const itemOf = (id: string) => state.stock.find((i) => i.id === id);
  const short = shortages(lines, levels);

  function setLines(next: PartLine[]) {
    dispatch({ type: "setParts", requestId: r.id, lines: next });
  }

  function add(item: StockItem) {
    setLines(mergeLines(lines, [{ itemId: item.id, qty: 1 }]));
    setQuery("");
  }

  // Подсказки поиска: сначала то, что подходит этой машине.
  const q = query.trim().toLowerCase();
  const matches = q
    ? state.stock
        .filter((i) => [i.name, i.sku, ...i.barcodes].join(" ").toLowerCase().includes(q))
        .sort((a, b) => Number(fitsCar(b, r.car.name)) - Number(fitsCar(a, r.car.name)))
        .slice(0, 5)
    : [];

  return (
    // Заголовок и подсказку даёт секция панели заявки (`RequestPanel`).
    <section className="flex flex-col gap-3">

      {!locked && (
        <>
          <div className="flex flex-wrap gap-2">
            {WORK_TEMPLATES.map((t) => (
              <Button
                key={t.id}
                variant="tertiary"
                size="compact"
                leadingIcon={Wand2}
                onClick={() => {
                  const res = applyTemplate(t, state.stock, r.car.name);
                  setLines(mergeLines(lines, res.lines));
                  setNotes(res.notes);
                }}
              >
                {t.name}
              </Button>
            ))}
          </div>

          <div className="relative">
            <InputGroup size="compact">
              <InputField
                index={0}
                label="Добавить позицию"
                labelHidden
                icon={ScanBarcode}
                placeholder="Скан упаковки или поиск по названию, артикулу"
                value={query}
                onChange={setQuery}
                onKeyDown={(e) => {
                  if (e.key !== "Enter") return;
                  const item = findByCode(state.stock, query) ?? (matches.length === 1 ? matches[0] : undefined);
                  if (item) add(item);
                }}
              />
            </InputGroup>
            {matches.length > 0 && (
              <ul className="absolute inset-x-0 top-full z-10 mt-1 overflow-hidden rounded-lg border border-border bg-popover shadow-lg">
                {matches.map((m) => (
                  <li key={m.id}>
                    <button
                      type="button"
                      className="flex w-full items-center justify-between gap-3 px-3 py-2 text-left text-[13px] hover:bg-hover"
                      onClick={() => add(m)}
                    >
                      <span className="min-w-0 truncate">
                        {m.name}
                        {!fitsCar(m, r.car.name) && (
                          <span className="text-muted-foreground"> · не для {r.car.name}</span>
                        )}
                      </span>
                      <span className="shrink-0 text-[12px] tabular-nums text-muted-foreground">
                        {qty(levels.get(m.id) ?? 0, UNIT_LABEL[m.unit])}
                      </span>
                    </button>
                  </li>
                ))}
              </ul>
            )}
          </div>

          {notes.length > 0 && (
            <ul className="flex flex-col gap-1 text-[12px] text-amber-600 dark:text-amber-400">
              {notes.map((n) => (
                <li key={n}>{n}</li>
              ))}
            </ul>
          )}
        </>
      )}

      {lines.length === 0 ? (
        locked ? null : <p className="text-[12px] text-muted-foreground">Пока ничего не добавлено.</p>
      ) : (
        <ul className="flex flex-col divide-y divide-border rounded-lg border border-border">
          {lines.map((l) => {
            const item = itemOf(l.itemId);
            if (!item) return null;
            const unit = UNIT_LABEL[item.unit];
            const step = item.unit === "l" ? 0.1 : 1;
            const lack = short.find((s) => s.itemId === l.itemId);
            const change = (next: number) =>
              setLines(lines.map((x) => (x.itemId === l.itemId ? { ...x, qty: round(Math.max(0, next)) } : x)));
            return (
              <li key={l.itemId} className="flex flex-wrap items-center gap-x-3 gap-y-1 px-3 py-2">
                <span className="flex min-w-0 flex-1 basis-48 flex-col">
                  <span className="truncate text-[13px]">{item.name}</span>
                  <span className="text-[11px] text-muted-foreground">
                    <span className="font-mono">{item.sku}</span>
                    {lack && !locked && (
                      <span className="text-red-500"> · на складе {qty(lack.have, unit)}</span>
                    )}
                  </span>
                </span>
                {locked ? (
                  <span className="text-[13px] tabular-nums">{qty(l.qty, unit)}</span>
                ) : (
                  <span className="flex items-center gap-1">
                    <Button
                      variant="ghost"
                      size="icon-compact"
                      aria-label="Меньше"
                      onClick={() => change(l.qty - step)}
                    >
                      <Minus />
                    </Button>
                    <input
                      className="h-7 w-16 rounded-md border border-border bg-transparent text-center text-[13px] tabular-nums outline-none focus:border-[color:var(--ring)]"
                      inputMode="decimal"
                      aria-label={`Количество, ${unit}`}
                      value={String(l.qty).replace(".", ",")}
                      onChange={(e) => {
                        const v = Number(e.target.value.replace(",", "."));
                        if (Number.isFinite(v)) change(v);
                      }}
                    />
                    <Button variant="ghost" size="icon-compact" aria-label="Больше" onClick={() => change(l.qty + step)}>
                      <Plus />
                    </Button>
                    <span className="w-5 text-[12px] text-muted-foreground">{unit}</span>
                  </span>
                )}
                <span className="w-20 text-right text-[12px] tabular-nums text-muted-foreground">
                  {rub(item.price * l.qty)}
                </span>
                {!locked && (
                  <Button
                    variant="ghost"
                    size="icon-compact"
                    aria-label="Убрать"
                    onClick={() => setLines(lines.filter((x) => x.itemId !== l.itemId))}
                  >
                    <X />
                  </Button>
                )}
              </li>
            );
          })}
        </ul>
      )}

      {lines.length > 0 && (
        <p className="text-right text-[12px] tabular-nums text-muted-foreground">
          Себестоимость запчастей: <span className="font-medium text-foreground">{rub(linesCost(lines, state.stock))}</span>
        </p>
      )}

      {lines.length > 0 && (
        <div className="flex flex-wrap items-center justify-end gap-3">
          {locked ? (
            <>
              <span className="text-[12px] text-muted-foreground">Списано {dateTime(r.partsWrittenOffAt!)}</span>
              <Button
                variant="ghost"
                size="compact"
                leadingIcon={Undo2}
                onClick={() => dispatch({ type: "undoWriteOff", requestId: r.id })}
              >
                Вернуть на склад
              </Button>
            </>
          ) : (
            <>
              {r.status === "done" && (
                <span className="text-[12px] text-amber-600 dark:text-amber-400">Заявка готова, а расход не списан</span>
              )}
              <Button
                size="compact"
                leadingIcon={PackageMinus}
                onClick={() => dispatch({ type: "writeOff", requestId: r.id })}
              >
                Списать со склада
              </Button>
            </>
          )}
        </div>
      )}
    </section>
  );
}
