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

export type Role = "master" | "diagnost" | "mechanic" | "electrician";

export interface Employee {
  id: string;
  name: string;
  role: Role;
  phone: string;
  /** На смене сейчас — на такого и назначают. */
  onShift: boolean;
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

export const ROLE_LABEL: Record<Role, string> = {
  master: "Мастер-приёмщик",
  diagnost: "Диагност",
  mechanic: "Механик",
  electrician: "Автоэлектрик",
};

/** Открытые статусы — те, что ещё занимают сотрудника. */
export const OPEN_STATUSES: readonly RequestStatus[] = ["new", "in_progress", "waiting_parts"];
