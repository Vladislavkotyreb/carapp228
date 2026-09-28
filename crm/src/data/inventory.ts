// Склад без React: остатки, поиск по коду, нормы, шаблоны работ, разбор
// потока сканера. Функции берут значения и отдают значения — проверяются
// скриптом `scripts/check-inventory.ts` без браузера.

import type { PartLine, StockItem, StockMove, StockRole } from "./types";

// ------------------------------------------------------------------ Остатки

/** Остаток по каждой позиции — сумма движений. */
export function stockLevels(moves: readonly StockMove[]): Map<string, number> {
  const levels = new Map<string, number>();
  for (const m of moves) levels.set(m.itemId, round(levels.get(m.itemId) ?? 0) + m.delta);
  for (const [id, v] of levels) levels.set(id, round(v));
  return levels;
}

/** Литры складываются дробями (4.3 + 0.2): без округления в остатке
 *  всплывает 4.499999999. Точность — сотые, мельче на СТО не отпускают. */
export function round(v: number): number {
  return Math.round(v * 100) / 100;
}

export function isLow(item: StockItem, qty: number): boolean {
  return qty <= item.min;
}

/** Позиция по штрихкоду или артикулу. Сканер отдаёт код целиком, человек
 *  вбивает артикул как угодно — поэтому без пробелов и регистра. */
export function findByCode(items: readonly StockItem[], code: string): StockItem | undefined {
  const key = normalizeCode(code);
  if (!key) return undefined;
  return items.find(
    (i) => i.barcodes.some((b) => normalizeCode(b) === key) || normalizeCode(i.sku) === key,
  );
}

function normalizeCode(code: string): string {
  return code.replace(/[\s-]/g, "").toUpperCase();
}

/** Сколько добавляет скан упаковки при приходе: канистра — её литры. */
export function receiptQty(item: StockItem): number {
  return item.pack ?? 1;
}

export function linesCost(lines: readonly PartLine[], items: readonly StockItem[]): number {
  return lines.reduce((sum, l) => sum + (items.find((i) => i.id === l.itemId)?.price ?? 0) * l.qty, 0);
}

/** Чего не хватает под расход: позиция и сколько есть. Списать можно и в
 *  минус (привезли, не оприходовав), но мастер должен это видеть. */
export function shortages(
  lines: readonly PartLine[],
  levels: ReadonlyMap<string, number>,
): { itemId: string; have: number }[] {
  return lines
    .filter((l) => (levels.get(l.itemId) ?? 0) < l.qty)
    .map((l) => ({ itemId: l.itemId, have: levels.get(l.itemId) ?? 0 }));
}

// ------------------------------------------------------------------- Нормы

/** Заправочный объём моторного масла с заменой фильтра, л. Примерные
 *  значения для популярных в РФ машин — для наброска. В проде это каталог
 *  по VIN и двигателю: у одной модели разные моторы льют по-разному. */
const OIL_NORMS: { match: string[]; liters: number }[] = [
  { match: ["kia rio"], liters: 3.3 },
  { match: ["hyundai solaris"], liters: 3.3 },
  { match: ["hyundai creta"], liters: 3.6 },
  { match: ["kia sportage"], liters: 4.0 },
  { match: ["lada vesta"], liters: 4.4 },
  { match: ["lada granta"], liters: 3.2 },
  { match: ["toyota camry"], liters: 4.4 },
  { match: ["toyota rav4"], liters: 4.4 },
  { match: ["volkswagen polo"], liters: 3.6 },
  { match: ["skoda octavia"], liters: 4.0 },
  { match: ["skoda rapid"], liters: 3.6 },
  { match: ["renault logan"], liters: 4.8 },
  { match: ["renault duster"], liters: 4.8 },
];

/** Название машины без регистра и диакритики: «Škoda» и «Skoda» — одно. */
export function normalizeCar(name: string): string {
  return name
    .normalize("NFD")
    .replace(/\p{Diacritic}/gu, "")
    .toLowerCase()
    .replace(/\s+/g, " ")
    .trim();
}

export function oilNorm(carName: string): number | undefined {
  const car = normalizeCar(carName);
  return OIL_NORMS.find((n) => n.match.some((m) => car.includes(m)))?.liters;
}

/** Подходит ли позиция машине: без `fits` — любой. */
export function fitsCar(item: StockItem, carName: string): boolean {
  if (!item.fits?.length) return true;
  const car = normalizeCar(carName);
  return item.fits.some((f) => car.includes(normalizeCar(f)));
}

// ---------------------------------------------------------- Шаблоны работ

type TemplateQty = number | "oil-norm";

export interface WorkTemplate {
  id: string;
  name: string;
  lines: { role: StockRole; qty: TemplateQty }[];
}

/** Если нормы на машину нет — столько и ставим, с просьбой проверить. */
export const FALLBACK_OIL_LITERS = 4;

export const WORK_TEMPLATES: readonly WorkTemplate[] = [
  {
    id: "oil",
    name: "Замена масла",
    lines: [
      { role: "engine_oil", qty: "oil-norm" },
      { role: "oil_filter", qty: 1 },
      { role: "drain_washer", qty: 1 },
    ],
  },
  {
    id: "service",
    name: "ТО: масло и фильтры",
    lines: [
      { role: "engine_oil", qty: "oil-norm" },
      { role: "oil_filter", qty: 1 },
      { role: "drain_washer", qty: 1 },
      { role: "air_filter", qty: 1 },
      { role: "cabin_filter", qty: 1 },
    ],
  },
  {
    id: "pads",
    name: "Передние колодки",
    lines: [{ role: "brake_pads_front", qty: 1 }],
  },
];

/** Расход по шаблону для машины: позиции по роли и совместимости, масло —
 *  по норме. `notes` — что мастеру стоит проверить глазами. */
export function applyTemplate(
  template: WorkTemplate,
  items: readonly StockItem[],
  carName: string,
): { lines: PartLine[]; notes: string[] } {
  const lines: PartLine[] = [];
  const notes: string[] = [];
  for (const t of template.lines) {
    const item = items.find((i) => i.role === t.role && fitsCar(i, carName));
    if (!item) {
      notes.push(`Нет на складе: ${ROLE_TITLE[t.role]} для ${carName}`);
      continue;
    }
    let qty: number;
    if (t.qty === "oil-norm") {
      const norm = oilNorm(carName);
      qty = norm ?? FALLBACK_OIL_LITERS;
      if (norm === undefined) {
        notes.push(`Нормы масла для ${carName} нет — поставили ${FALLBACK_OIL_LITERS} л, проверьте`);
      }
    } else {
      qty = t.qty;
    }
    lines.push({ itemId: item.id, qty });
  }
  return { lines, notes };
}

/** Слить расход: повтор позиции увеличивает количество, а не дублирует
 *  строку — «Замена масла» после «Колодок» дописывает, а не затирает. */
export function mergeLines(base: readonly PartLine[], add: readonly PartLine[]): PartLine[] {
  const out = base.map((l) => ({ ...l }));
  for (const a of add) {
    const same = out.find((l) => l.itemId === a.itemId);
    if (same) same.qty = round(same.qty + a.qty);
    else out.push({ ...a });
  }
  return out;
}

export const ROLE_TITLE: Record<StockRole, string> = {
  engine_oil: "моторное масло",
  oil_filter: "масляный фильтр",
  drain_washer: "шайба сливной пробки",
  air_filter: "воздушный фильтр",
  cabin_filter: "салонный фильтр",
  brake_pads_front: "передние колодки",
  antifreeze: "антифриз",
  brake_fluid: "тормозная жидкость",
};

// ------------------------------------------------------------------ Сканер

/** USB- и Bluetooth-сканеры штрихкодов притворяются клавиатурой: печатают
 *  код за десятки миллисекунд и жмут Enter. Человек так быстро не печатает —
 *  по скорости поток сканера и отличается от набора руками, и ловить его
 *  можно, даже когда фокус не в поле. */
export const SCAN_MAX_GAP_MS = 50;
export const SCAN_MIN_LENGTH = 6;

export interface ScanBuffer {
  chars: string;
  last: number;
}

export const emptyScan: ScanBuffer = { chars: "", last: 0 };

/** Шаг разбора: символ или Enter с отметкой времени. Возвращает новый буфер
 *  и код, если Enter закрыл быстрый поток нужной длины. */
export function feedScan(
  buffer: ScanBuffer,
  key: string,
  at: number,
): { buffer: ScanBuffer; code?: string } {
  const fast = buffer.chars.length === 0 || at - buffer.last <= SCAN_MAX_GAP_MS;
  if (key === "Enter") {
    const ok = fast && buffer.chars.length >= SCAN_MIN_LENGTH;
    return { buffer: emptyScan, code: ok ? buffer.chars : undefined };
  }
  if (key.length !== 1) return { buffer: emptyScan };
  return { buffer: { chars: (fast ? buffer.chars : "") + key, last: at } };
}
