import { dayKey } from "./payroll";
import type { Employee, RoleDef, ServiceRequest } from "./types";

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

/** Табель с начала месяца по сегодня: будни — пятидневка, `shift` — график
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
    pay: { kind: "monthly", salary: 65_000 }, workDays: workDays("5/2") },
  { id: "e2", name: "Артём Кузнецов", roleId: "diagnost", phone: "+7 925 330-47-12",
    pay: { kind: "monthly", salary: 80_000 }, workDays: workDays("5/2") },
  { id: "e3", name: "Игорь Павлов", roleId: "mechanic", phone: "+7 903 118-90-05",
    pay: { kind: "daily", rate: 3_500 }, workDays: workDays("2/2", 0) },
  { id: "e4", name: "Руслан Галиев", roleId: "mechanic", phone: "+7 977 562-38-44",
    pay: { kind: "daily", rate: 3_200 }, workDays: workDays("2/2", 2, true) },
  { id: "e5", name: "Денис Орлов", roleId: "electrician", phone: "+7 999 741-02-67",
    pay: { kind: "daily", rate: 4_000 }, workDays: workDays("5/2") },
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
