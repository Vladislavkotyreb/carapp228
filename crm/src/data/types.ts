// Модель CRM Beepy для сервисов. Типы первыми: что нельзя выразить, то не
// нужно проверять.

/** Откуда пришла заявка. Других путей у сервиса нет: либо человек дослушал
 *  мотор в приложении и нажал «Записаться», либо оставил запись на сайте-
 *  визитке, который стоит в карточке организации в Яндекс Картах. */
export type RequestSource = "app" | "site";

/** Жизнь заявки. «Отменена» — отдельный конец, а не «готово»: в отчётах
 *  они считаются по-разному. */
export type RequestStatus = "new" | "in_progress" | "waiting_parts" | "done" | "cancelled";

/** Находка из прослушивания — ровно то, что приложение показывает водителю
 *  в шторке «Вот что мы нашли». */
export interface Finding {
  title: string;
  system: string;
  /** 0…1 — уверенность модели. */
  confidence: number;
  advice: string;
}

/** Что пришло вместе с заявкой. Разные источники несут разное, поэтому это
 *  сумма типов, а не объект с кучей необязательных полей: у заявки с сайта
 *  не бывает находок, у заявки из приложения — комментария из формы. */
export type RequestPayload =
  | { source: "app"; findings: Finding[] }
  | { source: "site"; comment: string; preferredAt?: string };

export interface Car {
  name: string;
  plate?: string;
  mileage?: number;
}

export interface Client {
  name: string;
  phone: string;
}

export interface ServiceRequest {
  id: string;
  number: number;
  createdAt: string;
  client: Client;
  car: Car;
  /** Кратко, одной строкой: с чем человек пришёл. */
  summary: string;
  payload: RequestPayload;
  status: RequestStatus;
  assigneeId?: string;
}

/** Роль — данные, а не зашитый список: у каждого сервиса свои должности
 *  (шиномонтажник, кузовщик, мойщик). Стандартные четыре — только посев. */
export interface RoleDef {
  id: string;
  name: string;
}

/** Как платим. Сумма типов, а не два необязательных поля: у сотрудника
 *  либо ставка за смену, либо оклад — «и то и другое» выразить нельзя. */
export type Pay =
  | { kind: "daily"; rate: number }
  | { kind: "monthly"; salary: number };

export interface Employee {
  id: string;
  name: string;
  roleId: string;
  phone: string;
  pay: Pay;
  /** Табель: отработанные дни, `ГГГГ-ММ-ДД`. «На смене» — это отметка
   *  сегодняшнего дня здесь же, а не отдельный флаг: два источника правды
   *  о том, работает ли человек сегодня, разошлись бы. */
  workDays: string[];
}

export const STATUS_LABEL: Record<RequestStatus, string> = {
  new: "Новая",
  in_progress: "В работе",
  waiting_parts: "Ждёт запчасти",
  done: "Готово",
  cancelled: "Отменена",
};

export const STATUS_COLOR = {
  new: "blue",
  in_progress: "amber",
  waiting_parts: "orange",
  done: "green",
  cancelled: "gray",
} as const satisfies Record<RequestStatus, string>;

export const SOURCE_LABEL: Record<RequestSource, string> = {
  app: "Приложение",
  site: "Сайт",
};

export const PAY_KIND_LABEL: Record<Pay["kind"], string> = {
  daily: "Ставка за смену",
  monthly: "Месячный оклад",
};

/** Открытые статусы — те, что ещё занимают сотрудника. */
export const OPEN_STATUSES: readonly RequestStatus[] = ["new", "in_progress", "waiting_parts"];
