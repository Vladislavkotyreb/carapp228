// Проверки чистой логики склада: `node scripts/check-inventory.ts`
// (Node 22.6+ сам снимает типы). Браузер и React не нужны.

import {
  applyTemplate,
  emptyScan,
  feedScan,
  findByCode,
  mergeLines,
  oilNorm,
  shortages,
  stockLevels,
  WORK_TEMPLATES,
  type ScanBuffer,
} from "../src/data/inventory.ts";
import type { StockItem, StockMove } from "../src/data/types.ts";

let checks = 0;
let failures = 0;

function check(name: string, got: unknown, want: unknown) {
  checks++;
  const g = JSON.stringify(got);
  const w = JSON.stringify(want);
  if (g !== w) {
    failures++;
    console.log(`  ✗ ${name}\n      получили: ${g}\n      ожидали:  ${w}`);
  }
}

const items: StockItem[] = [
  { id: "oil", name: "Масло 5W-30", sku: "LM-3707", barcodes: ["4 607 000 000 017"], unit: "l", pack: 4, min: 8, price: 820, role: "engine_oil" },
  { id: "f-kia", name: "Фильтр Kia", sku: "26300-35505", barcodes: [], unit: "pcs", min: 2, price: 450, role: "oil_filter", fits: ["Kia", "Hyundai"] },
  { id: "f-vag", name: "Фильтр VAG", sku: "04E115561H", barcodes: [], unit: "pcs", min: 2, price: 690, role: "oil_filter", fits: ["Volkswagen", "Skoda"] },
  { id: "washer", name: "Шайба", sku: "W-14", barcodes: [], unit: "pcs", min: 10, price: 30, role: "drain_washer" },
];

const moves: StockMove[] = [
  { id: "1", itemId: "oil", delta: 4, at: "", reason: { kind: "receipt" } },
  { id: "2", itemId: "oil", delta: 4, at: "", reason: { kind: "receipt" } },
  { id: "3", itemId: "oil", delta: -3.3, at: "", reason: { kind: "writeoff", requestId: "r" } },
  { id: "4", itemId: "oil", delta: -0.2, at: "", reason: { kind: "writeoff", requestId: "r" } },
];

console.log("Остатки");
check("сумма движений без хвоста 0.999", stockLevels(moves).get("oil"), 4.5);
check("нет движений — нет строки", stockLevels(moves).get("washer"), undefined);

console.log("Поиск по коду");
check("штрихкод с пробелами", findByCode(items, "4607000000017")?.id, "oil");
check("артикул без дефиса и регистра", findByCode(items, "2630035505")?.id, "f-kia");
check("пустой код", findByCode(items, "  "), undefined);

console.log("Нормы");
check("Kia Rio", oilNorm("Kia Rio"), 3.3);
check("Škoda с диакритикой", oilNorm("Škoda Octavia"), 4);
check("незнакомая машина", oilNorm("ЗАЗ Запорожец"), undefined);

console.log("Шаблоны");
const oil = WORK_TEMPLATES.find((t) => t.id === "oil")!;
check("Kia: масло по норме, свой фильтр, шайба",
  applyTemplate(oil, items, "Kia Rio"),
  { lines: [{ itemId: "oil", qty: 3.3 }, { itemId: "f-kia", qty: 1 }, { itemId: "washer", qty: 1 }], notes: [] });
check("Škoda берёт фильтр VAG", applyTemplate(oil, items, "Škoda Octavia").lines[1], { itemId: "f-vag", qty: 1 });
const lada = applyTemplate(oil, items, "Lada Vesta");
check("Lada: норма есть, фильтра нет — заметка", lada.notes, ["Нет на складе: масляный фильтр для Lada Vesta"]);
check("Lada: масло 4.4", lada.lines[0], { itemId: "oil", qty: 4.4 });
check("без нормы — 4 л и просьба проверить",
  applyTemplate(oil, items, "ЗАЗ Запорожец").notes.includes("Нормы масла для ЗАЗ Запорожец нет — поставили 4 л, проверьте"), true);
check("слияние складывает, а не дублирует",
  mergeLines([{ itemId: "oil", qty: 3.3 }], [{ itemId: "oil", qty: 0.5 }, { itemId: "washer", qty: 1 }]),
  [{ itemId: "oil", qty: 3.8 }, { itemId: "washer", qty: 1 }]);
check("нехватка", shortages([{ itemId: "oil", qty: 5 }, { itemId: "washer", qty: 1 }], new Map([["oil", 4.5], ["washer", 3]])),
  [{ itemId: "oil", have: 4.5 }]);

console.log("Сканер");
function type(text: string, gap: number, start = 1000): string | undefined {
  let b: ScanBuffer = emptyScan;
  let t = start;
  let code: string | undefined;
  for (const ch of [...text, "Enter"]) {
    const r = feedScan(b, ch, t);
    b = r.buffer;
    code = r.code ?? code;
    t += gap;
  }
  return code;
}
check("поток сканера — код", type("4607000000017", 8), "4607000000017");
check("человек печатает — не код", type("4607000000017", 180), undefined);
check("короткий быстрый ввод — не код", type("123", 8), undefined);
{
  // Человек набрал пару букв, пауза, потом скан: код — только быстрая часть.
  let b: ScanBuffer = emptyScan;
  b = feedScan(b, "a", 0).buffer;
  b = feedScan(b, "b", 300).buffer;
  let t = 900;
  for (const ch of "4607000000017") { b = feedScan(b, ch, t).buffer; t += 10; }
  check("пауза отрезает ручной набор", feedScan(b, "Enter", t).code, "4607000000017");
}

console.log("");
if (failures) {
  console.log(`Провалено ${failures} из ${checks}.`);
  process.exit(1);
}
console.log(`Все ${checks} проверок прошли.`);
