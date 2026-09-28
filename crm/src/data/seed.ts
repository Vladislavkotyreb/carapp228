import { dayKey } from "./staff";
import type { Employee, PartLine, RoleDef, ServiceRequest, StockItem, StockMove } from "./types";

// Тестовые данные наброска. Время — относительно момента первого запуска,
// чтобы «12 мин назад» оставалось правдой при любом открытии.

const minutesAgo = (m: number) => new Date(Date.now() - m * 60_000).toISOString();
const inDays = (d: number, hour: number) => {
  const t = new Date();
  t.setDate(t.getDate() + d);
  t.setHours(hour, 0, 0, 0);
  return t.toISOString();
};

export const seedRoles: RoleDef[] = [
  { id: "master", name: "Мастер-приёмщик" },
  { id: "diagnost", name: "Диагност" },
  { id: "mechanic", name: "Механик" },
  { id: "electrician", name: "Автоэлектрик" },
];

/** Дни на смене с начала месяца по сегодня: будни — пятидневка, `shift` — график
 *  «два через два» со сдвигом. Сегодняшний день входит — это «на смене». */
function workDays(schedule: "5/2" | "2/2", shift = 0, skipToday = false): string[] {
  const now = new Date();
  const days: string[] = [];
  for (let d = 1; d <= now.getDate(); d++) {
    const date = new Date(now.getFullYear(), now.getMonth(), d);
    const wd = date.getDay();
    const works = schedule === "5/2" ? wd !== 0 && wd !== 6 : (d + shift) % 4 < 2;
    if (works) days.push(dayKey(date));
  }
  const today = dayKey(now);
  return skipToday ? days.filter((k) => k !== today) : days.includes(today) ? days : [...days, today];
}

export const seedEmployees: Employee[] = [
  { id: "e1", name: "Ольга Смирнова", roleId: "master", phone: "+7 916 204-11-83",
    workDays: workDays("5/2") },
  { id: "e2", name: "Артём Кузнецов", roleId: "diagnost", phone: "+7 925 330-47-12",
    workDays: workDays("5/2") },
  { id: "e3", name: "Игорь Павлов", roleId: "mechanic", phone: "+7 903 118-90-05",
    workDays: workDays("2/2", 0) },
  { id: "e4", name: "Руслан Галиев", roleId: "mechanic", phone: "+7 977 562-38-44",
    workDays: workDays("2/2", 2, true) },
  { id: "e5", name: "Денис Орлов", roleId: "electrician", phone: "+7 999 741-02-67",
    workDays: workDays("5/2") },
];

export const seedRequests: ServiceRequest[] = [
  {
    id: "r1048",
    number: 1048,
    createdAt: minutesAgo(12),
    client: { name: "Алексей", phone: "+7 915 482-19-30" },
    car: { name: "Kia Rio", plate: "В 777 ОР 777", mileage: 56_800 },
    summary: "Свист под капотом на холодную, ТО через 3 200 км",
    payload: {
      source: "app",
      findings: [
        {
          title: "Ремень привода",
          system: "Навесное оборудование",
          confidence: 0.97,
          advice: "Осмотреть ремень на трещины, проверить натяжение. Обычно меняют: ремень навесного, ролик натяжной",
        },
        {
          title: "Подшипник генератора",
          system: "Электрика",
          confidence: 0.41,
          advice: "Послушать генератор стетоскопом на холостых",
        },
      ],
    },
    status: "new",
  },
  {
    id: "r1047",
    number: 1047,
    createdAt: minutesAgo(48),
    client: { name: "Марина Ковалёва", phone: "+7 926 115-73-08" },
    car: { name: "Hyundai Solaris", plate: "К 204 МТ 750" },
    summary: "Плановое ТО-60 и замена колодок",
    payload: {
      source: "site",
      comment: "Хочу ТО на 60 тысяч и поменять передние колодки, скрипят при торможении. Удобно в субботу утром.",
      preferredAt: inDays(3, 10),
    },
    status: "new",
  },
  {
    id: "r1046",
    number: 1046,
    createdAt: minutesAgo(135),
    client: { name: "Сергей", phone: "+7 903 667-21-45" },
    car: { name: "Lada Vesta", plate: "А 512 ХК 799", mileage: 88_200 },
    summary: "Стук в подвеске спереди на неровностях",
    payload: {
      source: "app",
      findings: [
        {
          title: "Стойка стабилизатора",
          system: "Подвеска",
          confidence: 0.88,
          advice: "Проверить люфт стоек стабилизатора и втулок",
        },
      ],
    },
    status: "in_progress",
    assigneeId: "e3",
  },
  {
    id: "r1045",
    number: 1045,
    createdAt: minutesAgo(60 * 5),
    client: { name: "Виктор Андреев", phone: "+7 985 900-12-77" },
    car: { name: "Toyota Camry", plate: "О 001 ОО 177", mileage: 142_000 },
    summary: "Неровная работа двигателя на холостых",
    payload: {
      source: "app",
      findings: [
        {
          title: "Пропуски зажигания",
          system: "Двигатель",
          confidence: 0.76,
          advice: "Считать ошибки, проверить катушки и свечи",
        },
      ],
    },
    status: "waiting_parts",
    assigneeId: "e2",
  },
  {
    id: "r1044",
    number: 1044,
    createdAt: minutesAgo(60 * 26),
    client: { name: "Наталья", phone: "+7 916 004-88-19" },
    car: { name: "Volkswagen Polo" },
    summary: "Горит чек, машина дёргается при разгоне",
    payload: {
      source: "site",
      comment: "Загорелся чек после заправки, при разгоне подёргивания. Нужна диагностика.",
    },
    status: "in_progress",
    assigneeId: "e5",
  },
  {
    id: "r1043",
    number: 1043,
    createdAt: minutesAgo(60 * 50),
    client: { name: "Павел", phone: "+7 977 310-55-62" },
    car: { name: "Škoda Octavia", plate: "Т 845 ВЕ 750", mileage: 97_500 },
    summary: "Гул при повороте направо",
    payload: {
      source: "app",
      findings: [
        {
          title: "Ступичный подшипник",
          system: "Ходовая",
          confidence: 0.91,
          advice: "Проверить люфт колёс, заменить подшипник левой передней ступицы",
        },
      ],
    },
    status: "done",
    assigneeId: "e3",
  },
  {
    id: "r1042",
    number: 1042,
    createdAt: minutesAgo(60 * 76),
    client: { name: "Екатерина", phone: "+7 999 208-64-31" },
    car: { name: "Renault Logan" },
    summary: "Замена масла и фильтров",
    payload: { source: "site", comment: "Масло + все фильтры, своё масло не привезу." },
    status: "done",
    assigneeId: "e4",
    parts: loganService(),
    partsWrittenOffAt: minutesAgo(60 * 70),
  },
  {
    id: "r1041",
    number: 1041,
    createdAt: minutesAgo(60 * 98),
    client: { name: "Илья", phone: "+7 926 781-40-02" },
    car: { name: "Kia Sportage", plate: "Н 330 АУ 197", mileage: 64_100 },
    summary: "Скрип ремня на запуске",
    payload: {
      source: "app",
      findings: [
        {
          title: "Ремень привода",
          system: "Навесное оборудование",
          confidence: 0.82,
          advice: "Проверить натяжитель, заменить ремень",
        },
      ],
    },
    status: "cancelled",
  },
];

// --------------------------------------------------------------------- Склад
// Штрихкоды и артикулы тестовые: похожи на настоящие по виду, но ни на что
// не указывают. Фильтры у каждой марки свои — `fits` из названия машины.

export const seedStock: StockItem[] = [
  { id: "oil-5w30", name: "Масло моторное 5W-30, канистра 4\u00A0л", sku: "MO-530-4", barcodes: ["4607000000017"],
    unit: "l", pack: 4, min: 12, price: 780, role: "engine_oil", marked: true },
  { id: "oil-5w40", name: "Масло моторное 5W-40, бочка 208\u00A0л", sku: "MO-540-208", barcodes: ["4607000000024"],
    unit: "l", pack: 208, min: 20, price: 520, marked: true },
  { id: "flt-kia", name: "Фильтр масляный Hyundai/Kia", sku: "26300-35505", barcodes: ["8800000000011"],
    unit: "pcs", min: 3, price: 420, role: "oil_filter", fits: ["Kia", "Hyundai"] },
  { id: "flt-vag", name: "Фильтр масляный VAG", sku: "04E115561H", barcodes: ["4000000000028"],
    unit: "pcs", min: 2, price: 690, role: "oil_filter", fits: ["Volkswagen", "Skoda", "Audi"] },
  { id: "flt-lada", name: "Фильтр масляный Lada", sku: "21080-1012005", barcodes: ["4600000000035"],
    unit: "pcs", min: 3, price: 260, role: "oil_filter", fits: ["Lada"] },
  { id: "flt-renault", name: "Фильтр масляный Renault", sku: "8200768913", barcodes: ["3600000000042"],
    unit: "pcs", min: 2, price: 380, role: "oil_filter", fits: ["Renault"] },
  { id: "flt-toyota", name: "Фильтр масляный Toyota", sku: "04152-YZZA6", barcodes: ["4900000000059"],
    unit: "pcs", min: 2, price: 640, role: "oil_filter", fits: ["Toyota"] },
  { id: "washer", name: "Шайба сливной пробки, медь 14\u00A0мм", sku: "W-CU-14", barcodes: ["4607000000062"],
    unit: "pcs", min: 20, price: 25, role: "drain_washer" },
  { id: "air-kia", name: "Фильтр воздушный Hyundai/Kia", sku: "28113-1R100", barcodes: ["8800000000073"],
    unit: "pcs", min: 2, price: 510, role: "air_filter", fits: ["Kia", "Hyundai"] },
  { id: "cabin-kia", name: "Фильтр салонный Hyundai/Kia", sku: "97133-4L000", barcodes: ["8800000000080"],
    unit: "pcs", min: 2, price: 590, role: "cabin_filter", fits: ["Kia", "Hyundai"] },
  { id: "air-renault", name: "Фильтр воздушный Renault", sku: "8200431051", barcodes: ["3600000000097"],
    unit: "pcs", min: 2, price: 450, role: "air_filter", fits: ["Renault"] },
  { id: "cabin-renault", name: "Фильтр салонный Renault", sku: "272772835R", barcodes: ["3600000000103"],
    unit: "pcs", min: 2, price: 480, role: "cabin_filter", fits: ["Renault"] },
  { id: "pads-kia", name: "Колодки передние Kia Rio / Hyundai Solaris", sku: "58101-4LA00", barcodes: ["8800000000110"],
    unit: "pcs", min: 2, price: 2350, role: "brake_pads_front", fits: ["Kia Rio", "Hyundai Solaris"] },
  { id: "antifreeze", name: "Антифриз G12+, канистра 5\u00A0л", sku: "AF-G12-5", barcodes: ["4607000000127"],
    unit: "l", pack: 5, min: 10, price: 190, role: "antifreeze", marked: true },
  { id: "brake-fluid", name: "Тормозная жидкость DOT-4, 1\u00A0л", sku: "BF-DOT4-1", barcodes: ["4607000000134"],
    unit: "l", pack: 1, min: 3, price: 420, role: "brake_fluid", marked: true },
];

function loganService(): PartLine[] {
  return [
    { itemId: "oil-5w30", qty: 4.8 },
    { itemId: "flt-renault", qty: 1 },
    { itemId: "washer", qty: 1 },
    { itemId: "air-renault", qty: 1 },
    { itemId: "cabin-renault", qty: 1 },
  ];
}

/** Приходы за прошлые две недели и списание по готовой заявке №1042 —
 *  чтобы журнал движения был не пустым и остаток объяснялся из него. */
const RECEIPTS: [string, number, number][] = [
  // позиция, сколько, дней назад
  ["oil-5w30", 16, 12], ["oil-5w40", 208, 20], ["flt-kia", 2, 12], ["flt-vag", 4, 12],
  ["flt-lada", 6, 9], ["flt-renault", 3, 9], ["flt-toyota", 2, 9], ["washer", 50, 20],
  ["air-kia", 3, 12], ["cabin-kia", 1, 12], ["air-renault", 2, 9], ["cabin-renault", 2, 9],
  ["pads-kia", 3, 5], ["antifreeze", 20, 20], ["brake-fluid", 6, 20],
];

export const seedMoves: StockMove[] = [
  ...RECEIPTS.map(([itemId, qty, days], i): StockMove => ({
    id: `m${i + 1}`,
    itemId,
    delta: qty,
    at: minutesAgo(60 * 24 * days),
    reason: { kind: "receipt" },
  })),
  ...loganService().map((l, i): StockMove => ({
    id: `m-w${i + 1}`,
    itemId: l.itemId,
    delta: -l.qty,
    at: minutesAgo(60 * 70),
    reason: { kind: "writeoff", requestId: "r1042" },
  })),
];
