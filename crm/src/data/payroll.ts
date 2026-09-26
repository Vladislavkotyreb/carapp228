import { grouped } from "./format";
import type { Employee, Pay } from "./types";

// Табель и оплата — чистые функции над датами. Вью только рисует.

const NBSP = " ";

/** `ГГГГ-ММ-ДД` по местному времени — ключ дня в табеле. Не `toISOString`:
 *  та берёт UTC, и у Москвы после 21:00 «сегодня» уезжало бы на завтра. */
export function dayKey(date: Date): string {
  const m = String(date.getMonth() + 1).padStart(2, "0");
  const d = String(date.getDate()).padStart(2, "0");
  return `${date.getFullYear()}-${m}-${d}`;
}

export function todayKey(now = new Date()): string {
  return dayKey(now);
}

/** Месяц табеля: год и номер месяца с нуля, как у `Date`. */
export interface Month {
  year: number;
  month: number;
}

export function monthOf(date: Date): Month {
  return { year: date.getFullYear(), month: date.getMonth() };
}

export function shiftMonth(m: Month, delta: number): Month {
  const d = new Date(m.year, m.month + delta, 1);
  return monthOf(d);
}

/** «сентябрь 2026». */
export function monthTitle(m: Month): string {
  return new Date(m.year, m.month, 1).toLocaleDateString("ru-RU", { month: "long", year: "numeric" }).replace(" г.", "");
}

export interface Day {
  key: string;
  date: number;
  /** Суббота или воскресенье. */
  weekend: boolean;
}

export function daysOf(m: Month): Day[] {
  const count = new Date(m.year, m.month + 1, 0).getDate();
  return Array.from({ length: count }, (_, i) => {
    const date = new Date(m.year, m.month, i + 1);
    const wd = date.getDay();
    return { key: dayKey(date), date: i + 1, weekend: wd === 0 || wd === 6 };
  });
}

/** Норма рабочих дней месяца — будни пн–пт. Упрощение: праздники
 *  производственного календаря не вычитаются, и это подписано в интерфейсе. */
export function workdayNorm(m: Month): number {
  return daysOf(m).filter((d) => !d.weekend).length;
}

export function workedIn(e: Employee, m: Month): number {
  const prefix = `${m.year}-${String(m.month + 1).padStart(2, "0")}-`;
  return e.workDays.filter((d) => d.startsWith(prefix)).length;
}

export function isOnShift(e: Employee, now = new Date()): boolean {
  return e.workDays.includes(todayKey(now));
}

export interface Payout {
  days: number;
  norm: number;
  amount: number;
  /** Как посчитано — одной строкой, чтобы бухгалтер сверил без калькулятора. */
  formula: string;
}

/** К выплате за месяц.
 *  - Ставка: смены × ставка.
 *  - Оклад: пропорционально отработанным дням от нормы, не больше оклада —
 *    переработку и выходные по двойному тарифу набросок не считает. */
export function payout(e: Employee, m: Month): Payout {
  const days = workedIn(e, m);
  const norm = workdayNorm(m);
  if (e.pay.kind === "daily") {
    const amount = days * e.pay.rate;
    return { days, norm, amount, formula: `${days} × ${rub(e.pay.rate)}` };
  }
  const share = norm === 0 ? 0 : Math.min(days, norm) / norm;
  const amount = Math.round(e.pay.salary * share);
  return { days, norm, amount, formula: `${rub(e.pay.salary)} × ${Math.min(days, norm)}/${norm}` };
}

export function rub(value: number): string {
  return `${grouped(value)}${NBSP}₽`;
}

/** «2 500 ₽ за смену», «60 000 ₽ в месяц». */
export function payLabel(pay: Pay): string {
  return pay.kind === "daily" ? `${rub(pay.rate)} за смену` : `${rub(pay.salary)} в месяц`;
}
