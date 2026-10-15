import { useMemo, useState } from "react";
import { ArrowDownToLine, ClipboardCheck, PackageCheck, ScanBarcode, Search, Undo2 } from "lucide-react";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { InputField, InputGroup } from "@/components/ui/input-group";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { TabItem, TabPanel, Tabs, TabsList } from "@/components/ui/tabs";
import { Tooltip } from "@/components/ui/tooltip";
import { PageHeader } from "@/components/bits";
import { count, dateTime, qty } from "@/data/format";
import { findByCode, isLow, receiptQty, stockLevels } from "@/data/inventory";
import { rub } from "@/data/staff";
import { useStore } from "@/data/store";
import { UNIT_LABEL, type StockItem, type StockMove } from "@/data/types";
import { useBarcodeScanner } from "@/hooks/use-barcode-scanner";

type Filter = "all" | "low" | "marked";
type Mode = "receive" | "count";

/** Что сделал последний скан — строкой над таблицей, с отменой: сканер
 *  пикает быстрее, чем глаз успевает проверить, та ли это позиция. */
interface LastScan {
  item: StockItem;
  added: number;
  before: number;
}

/** Склад расходников. Остаток — сумма движений (`stockLevels`), поэтому
 *  любое число здесь объясняется журналом на второй вкладке. */
export function StockPage({ focusItemId }: { focusItemId?: string }) {
  const { state, dispatch } = useStore();
  const levels = useMemo(() => stockLevels(state.moves), [state.moves]);
  const [tab, setTab] = useState<"items" | "moves">("items");
  const [filter, setFilter] = useState<Filter>("all");
  const [query, setQuery] = useState("");
  const [last, setLast] = useState<LastScan | null>(null);
  const [notFound, setNotFound] = useState<string | null>(null);
  const [dialog, setDialog] = useState<{ item: StockItem; mode: Mode } | null>(null);

  const level = (id: string) => levels.get(id) ?? 0;

  /** Скан или Enter в поле: код нашёлся — приход упаковкой; нет — это был
   *  поиск, и таблица уже отфильтрована по нему. */
  function onCode(code: string, fromField: boolean) {
    const item = findByCode(state.stock, code);
    if (!item) {
      if (!fromField) setNotFound(code);
      return;
    }
    const added = receiptQty(item);
    setLast({ item, added, before: level(item.id) });
    setNotFound(null);
    dispatch({ type: "receive", itemId: item.id, qty: added });
    if (fromField) setQuery("");
  }

  useBarcodeScanner((code) => onCode(code, false), tab === "items" && !dialog);

  const visible = state.stock
    .filter((i) => filter === "all" || (filter === "low" ? isLow(i, level(i.id)) : i.marked))
    .filter((i) => {
      const q = query.trim().toLowerCase();
      return !q || [i.name, i.sku, ...i.barcodes].join(" ").toLowerCase().includes(q);
    });

  const lowCount = state.stock.filter((i) => isLow(i, level(i.id))).length;
  const value = state.stock.reduce((sum, i) => sum + Math.max(0, level(i.id)) * i.price, 0);

  return (
    <div className="flex flex-col gap-5">
      <PageHeader
        title="Склад"
        subtitle={`${count(state.stock.length, "позиция", "позиции", "позиций")} · ${lowCount} заканчиваются · на ${rub(value)}`}
        actions={
          <Tabs value={tab} onValueChange={(v) => setTab(v as "items" | "moves")}>
            <TabsList>
              <TabItem value="items" label="Остатки" />
              <TabItem value="moves" label="Движение" />
            </TabsList>
          </Tabs>
        }
      />

      <Tabs value={tab} onValueChange={(v) => setTab(v as "items" | "moves")}>
        <TabPanel value="items" className="flex flex-col gap-4">
          <div className="flex flex-wrap items-center gap-3">
            <InputGroup className="min-w-0 flex-1 basis-72">
              <InputField
                index={0}
                label="Скан или поиск"
                labelHidden
                icon={ScanBarcode}
                placeholder="Скан упаковки — приход. Или поиск по названию, артикулу"
                value={query}
                onChange={setQuery}
                onKeyDown={(e) => {
                  if (e.key === "Enter") onCode(query, true);
                }}
              />
            </InputGroup>
            <Tabs value={filter} onValueChange={(v) => setFilter(v as Filter)}>
              <TabsList>
                <TabItem value="all" label="Все" />
                <TabItem value="low" label={`Заканчиваются · ${lowCount}`} />
                <TabItem value="marked" label="Честный знак" />
              </TabsList>
            </Tabs>
          </div>

          {last && (
            <div className="flex flex-wrap items-center gap-x-3 gap-y-1 rounded-lg border border-border bg-card px-3 py-2 text-[13px]">
              <PackageCheck className="size-4 text-emerald-500" aria-hidden />
              <span className="min-w-0 flex-1 truncate">
                Приход <b className="font-medium">+{qty(last.added, UNIT_LABEL[last.item.unit])}</b> · {last.item.name}
                <span className="text-muted-foreground">
                  {" "}
                  → {qty(level(last.item.id), UNIT_LABEL[last.item.unit])}
                </span>
              </span>
              <Button
                variant="ghost"
                size="compact"
                leadingIcon={Undo2}
                onClick={() => {
                  dispatch({ type: "count", itemId: last.item.id, actual: last.before });
                  setLast(null);
                }}
              >
                Отменить
              </Button>
            </div>
          )}
          {notFound && (
            <p className="text-[13px] text-muted-foreground">
              Код {notFound} не знаком складу — найдите позицию и добавьте код в её карточке.
            </p>
          )}

          {visible.length === 0 ? (
            <p className="py-12 text-center text-[13px] text-muted-foreground">
              <Search className="mx-auto mb-2 size-4" aria-hidden />
              Ничего не нашли
            </p>
          ) : (
            <Table>
              <TableHeader>
                <TableRow>
                  <TableHead>Позиция</TableHead>
                  <TableHead className="text-right">Остаток</TableHead>
                  <TableHead className="hidden text-right md:table-cell">Порог</TableHead>
                  <TableHead className="hidden text-right md:table-cell">Цена</TableHead>
                  <TableHead className="hidden text-right lg:table-cell">Сумма</TableHead>
                  <TableHead className="w-0" />
                </TableRow>
              </TableHeader>
              <TableBody>
                {visible.map((item, i) => {
                  const have = level(item.id);
                  const low = isLow(item, have);
                  const unit = UNIT_LABEL[item.unit];
                  return (
                    <TableRow
                      key={item.id}
                      index={i}
                      className={focusItemId === item.id ? "bg-[color:var(--primary)]/10" : undefined}
                    >
                      <TableCell>
                        <span className="flex min-w-0 flex-col">
                          <span className="flex items-center gap-2 text-[13px] font-medium text-foreground">
                            <span className="truncate">{item.name}</span>
                            {item.marked && (
                              <Badge variant="dot" size="compact" color="gray" title="Маркировка «Честный знак»">
                                ЧЗ
                              </Badge>
                            )}
                          </span>
                          <span className="font-mono text-[11px] text-muted-foreground">{item.sku}</span>
                        </span>
                      </TableCell>
                      <TableCell className="whitespace-nowrap text-right">
                        <span className={"text-[13px] tabular-nums " + (low ? "font-medium text-red-500" : "")}>
                          {qty(have, unit)}
                        </span>
                      </TableCell>
                      <TableCell className="hidden text-right text-[13px] tabular-nums text-muted-foreground md:table-cell">
                        {qty(item.min, unit)}
                      </TableCell>
                      <TableCell className="hidden whitespace-nowrap text-right text-[13px] tabular-nums text-muted-foreground md:table-cell">
                        {rub(item.price)}/{unit}
                      </TableCell>
                      <TableCell className="hidden whitespace-nowrap text-right text-[13px] tabular-nums lg:table-cell">
                        {rub(Math.max(0, have) * item.price)}
                      </TableCell>
                      <TableCell>
                        {/* Иконками: две текстовые кнопки не влезали в строку и
                            срезались правым краем таблицы. */}
                        <span className="flex justify-end gap-0.5">
                          <Tooltip content="Приход">
                            <Button
                              variant="ghost"
                              size="icon-compact"
                              aria-label={`Приход: ${item.name}`}
                              onClick={() => setDialog({ item, mode: "receive" })}
                            >
                              <ArrowDownToLine />
                            </Button>
                          </Tooltip>
                          <Tooltip content="Пересчёт">
                            <Button
                              variant="ghost"
                              size="icon-compact"
                              aria-label={`Пересчёт: ${item.name}`}
                              onClick={() => setDialog({ item, mode: "count" })}
                            >
                              <ClipboardCheck />
                            </Button>
                          </Tooltip>
                        </span>
                      </TableCell>
                    </TableRow>
                  );
                })}
              </TableBody>
            </Table>
          )}
        </TabPanel>

        <TabPanel value="moves">
          <MovesTable moves={state.moves} />
        </TabPanel>
      </Tabs>

      {dialog && (
        <QtyDialog
          item={dialog.item}
          mode={dialog.mode}
          have={level(dialog.item.id)}
          onClose={() => setDialog(null)}
          onSubmit={(value) => {
            if (dialog.mode === "receive") dispatch({ type: "receive", itemId: dialog.item.id, qty: value });
            else dispatch({ type: "count", itemId: dialog.item.id, actual: value });
            setDialog(null);
          }}
        />
      )}
    </div>
  );
}

/** Журнал: новые сверху. Основание — словами и номером заявки. */
function MovesTable({ moves }: { moves: StockMove[] }) {
  const { state } = useStore();
  const sorted = [...moves].sort((a, b) => Date.parse(b.at) - Date.parse(a.at));
  const reason = (m: StockMove) => {
    switch (m.reason.kind) {
      case "receipt":
        return "Приход";
      case "count":
        return "Пересчёт";
      case "writeoff":
      case "return": {
        const id = m.reason.requestId;
        const n = state.requests.find((r) => r.id === id)?.number;
        return `${m.reason.kind === "writeoff" ? "Расход по заявке" : "Возврат с заявки"} №${n ?? "?"}`;
      }
    }
  };
  return (
    <Table>
      <TableHeader>
        <TableRow>
          <TableHead>Когда</TableHead>
          <TableHead>Позиция</TableHead>
          <TableHead className="text-right">Изменение</TableHead>
          <TableHead className="hidden md:table-cell">Основание</TableHead>
        </TableRow>
      </TableHeader>
      <TableBody>
        {sorted.map((m, i) => {
          const item = state.stock.find((s) => s.id === m.itemId);
          const unit = item ? UNIT_LABEL[item.unit] : "";
          return (
            <TableRow key={m.id} index={i}>
              <TableCell className="whitespace-nowrap text-[12px] text-muted-foreground">{dateTime(m.at)}</TableCell>
              <TableCell className="text-[13px]">{item?.name ?? m.itemId}</TableCell>
              <TableCell
                className={
                  "text-right text-[13px] tabular-nums " + (m.delta > 0 ? "text-emerald-500" : "text-foreground")
                }
              >
                {m.delta > 0 ? "+" : ""}
                {qty(m.delta, unit)}
              </TableCell>
              <TableCell className="hidden text-[12px] text-muted-foreground md:table-cell">{reason(m)}</TableCell>
            </TableRow>
          );
        })}
      </TableBody>
    </Table>
  );
}

/** Приход количеством или пересчёт: сколько лежит на самом деле. */
function QtyDialog({
  item,
  mode,
  have,
  onClose,
  onSubmit,
}: {
  item: StockItem;
  mode: Mode;
  have: number;
  onClose: () => void;
  onSubmit: (value: number) => void;
}) {
  const unit = UNIT_LABEL[item.unit];
  const [text, setText] = useState(mode === "count" ? String(have).replace(".", ",") : String(receiptQty(item)));
  const value = Number(text.replace(",", ".").replace(/\s/g, ""));
  const valid = Number.isFinite(value) && (mode === "count" ? value >= 0 : value > 0);

  return (
    <Dialog open onOpenChange={(o) => !o && onClose()}>
      <DialogContent size="sm">
        <DialogHeader>
          <DialogTitle>{mode === "receive" ? "Приход" : "Пересчёт"}</DialogTitle>
          <DialogDescription>
            {item.name}. В учёте {qty(have, unit)}
            {mode === "count" ? " — впишите, сколько лежит на самом деле." : "."}
          </DialogDescription>
        </DialogHeader>
        <InputGroup>
          <InputField
            index={0}
            label={mode === "receive" ? `Пришло, ${unit}` : `Фактически, ${unit}`}
            value={text}
            onChange={(v) => setText(v.replace(/[^\d.,\s]/g, ""))}
            inputMode="decimal"
            autoFocus
            onKeyDown={(e) => {
              if (e.key === "Enter" && valid) onSubmit(value);
            }}
          />
        </InputGroup>
        {mode === "count" && valid && value !== have && (
          <p className="text-[12px] text-muted-foreground">
            Разница {value > have ? "+" : ""}
            {qty(value - have, unit)} уйдёт в журнал как пересчёт.
          </p>
        )}
        <DialogFooter>
          <Button variant="ghost" onClick={onClose}>
            Отмена
          </Button>
          <Button disabled={!valid} onClick={() => onSubmit(value)}>
            {mode === "receive" ? "Оприходовать" : "Сохранить"}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
