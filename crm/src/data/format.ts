// Форматирование по правилам Beepy: между числом и единицей — неразрывный
// пробел, разряды тоже через него. Иначе «56 800 км» рвётся переносом.

const NBSP = " ";

export function grouped(value: number): string {
  return Math.round(value).toString().replace(/\B(?=(\d{3})+(?!\d))/g, NBSP);
}

export function km(value: number): string {
  return `${grouped(value)}${NBSP}км`;
}

export function percent(share: number): string {
  return `${Math.round(share * 100)}${NBSP}%`;
}

/** «1 заявка», «2 заявки», «5 заявок». */
export function plural(n: number, one: string, few: string, many: string): string {
  const mod10 = n % 10;
  const mod100 = n % 100;
  if (mod10 === 1 && mod100 !== 11) return one;
  if (mod10 >= 2 && mod10 <= 4 && (mod100 < 12 || mod100 > 14)) return few;
  return many;
}

export function count(n: number, one: string, few: string, many: string): string {
  return `${n}${NBSP}${plural(n, one, few, many)}`;
}

/** «только что», «12 мин назад», «3 ч назад», «вчера», дальше — дата. */
export function ago(iso: string, now: Date = new Date()): string {
  const minutes = Math.floor((now.getTime() - new Date(iso).getTime()) / 60_000);
  if (minutes < 1) return "только что";
  if (minutes < 60) return `${minutes}${NBSP}мин назад`;
  const hours = Math.floor(minutes / 60);
  if (hours < 24) return `${hours}${NBSP}ч назад`;
  if (hours < 48) return "вчера";
  return date(iso);
}

export function date(iso: string): string {
  return new Date(iso).toLocaleDateString("ru-RU", { day: "numeric", month: "long" });
}

export function dateTime(iso: string): string {
  const d = new Date(iso);
  return `${date(iso)}, ${d.toLocaleTimeString("ru-RU", { hour: "2-digit", minute: "2-digit" })}`;
}

/** Ссылка для звонка: только цифры и ведущий плюс. */
export function tel(phone: string): string {
  const digits = phone.replace(/\D/g, "");
  return phone.trim().startsWith("+") ? `tel:+${digits}` : `tel:${digits}`;
}

export function initials(name: string): string {
  return name
    .split(/\s+/)
    .slice(0, 2)
    .map((part) => part[0] ?? "")
    .join("")
    .toUpperCase();
}
