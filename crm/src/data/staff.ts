import { grouped } from "./format";
import type { Employee } from "./types";

// Сотрудники: смена сегодня и «работает ли вообще». Табеля и расчёта оплаты
// нет (убраны 27.09.2026): на большинстве СТО платят сдельно плюс фикс, а
// выработку по нормо-часам брать неоткуда — без неё табель считал бы то,
// чего сервис не платит.

const NBSP = " ";

/** `ГГГГ-ММ-ДД` по местному времени — ключ дня. Не `toISOString`: та берёт
 *  UTC, и у Москвы после 21:00 «сегодня» уезжало бы на завтра. */
export function dayKey(date: Date): string {
  const m = String(date.getMonth() + 1).padStart(2, "0");
  const d = String(date.getDate()).padStart(2, "0");
  return `${date.getFullYear()}-${m}-${d}`;
}

export function todayKey(now = new Date()): string {
  return dayKey(now);
}

/** «На смене» — отметка сегодняшнего дня. По ней в назначении заявки
 *  сначала идут те, кто сегодня на месте. */
export function isOnShift(e: Employee, now = new Date()): boolean {
  return e.workDays.includes(todayKey(now));
}

/** Работает ли человек в сервисе сейчас (не деактивирован). */
export function isActive(e: Employee): boolean {
  return !e.deactivatedAt;
}

export function rub(value: number): string {
  return `${grouped(value)}${NBSP}₽`;
}
