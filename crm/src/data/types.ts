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
  /** Расход по заявке: что мастер потратил. Черновик, пока не списан. */
  parts?: PartLine[];
  /** Когда расход списан со склада. Списанный расход не правится — только
   *  «Вернуть на склад», чтобы движение по складу не расходилось с заявкой. */
  partsWrittenOffAt?: string;
}

/** Роль — данные, а не зашитый список: у каждого сервиса свои должности
 *  (шиномонтажник, кузовщик, мойщик). Стандартные четыре — только посев. */
export interface RoleDef {
  id: string;
  name: string;
}

export interface Employee {
  id: string;
  name: string;
  roleId: string;
  phone: string;
  /** Дни на смене, `ГГГГ-ММ-ДД`. «На смене» — отметка сегодняшнего дня
   *  здесь же, а не отдельный флаг: два источника правды разошлись бы. */
  workDays: string[];
  /** Деактивирован: ушёл из сервиса. Не удаляем — на нём закрытые заявки,
   *  без записи они потеряли бы имя исполнителя. */
  deactivatedAt?: string;
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


/** Открытые статусы — те, что ещё занимают сотрудника. */
export const OPEN_STATUSES: readonly RequestStatus[] = ["new", "in_progress", "waiting_parts"];

// --------------------------------------------------------------------- Склад

/** Единица учёта. Масло и жидкости — литрами: из бочки отпускают на розлив,
 *  и даже канистра на машину уходит не целиком. */
export type Unit = "pcs" | "l";

export const UNIT_LABEL: Record<Unit, string> = { pcs: "шт", l: "л" };

/** Роль расходника в шаблоне работ: «масло», «масляный фильтр». По ней
 *  шаблон «Замена масла» находит, что именно положить в расход. */
export type StockRole =
  | "engine_oil"
  | "oil_filter"
  | "drain_washer"
  | "air_filter"
  | "cabin_filter"
  | "brake_pads_front"
  | "antifreeze"
  | "brake_fluid";

export interface StockItem {
  id: string;
  name: string;
  /** Артикул производителя — по нему ищут и по нему же заказывают. */
  sku: string;
  /** Штрихкоды упаковки (EAN-13 и т. п.). У одной детали от разных
   *  поставщиков бывают разные коды, поэтому список. */
  barcodes: string[];
  unit: Unit;
  /** Сколько единиц в упаковке: канистра 4 л. Скан упаковки при приходе
   *  добавляет её целиком. Нет — упаковка равна единице. */
  pack?: number;
  /** Порог «заканчивается». */
  min: number;
  /** Закупочная цена за единицу, ₽. */
  price: number;
  role?: StockRole;
  /** Для каких машин подходит — слова из названия машины. Пусто — для всех
   *  (шайба, жидкости). Фильтры у каждой марки свои. */
  fits?: string[];
  /** Товар с обязательной маркировкой «Честный знак» (масла, антифриз,
   *  тормозная жидкость — поштучный учёт с 1 апреля 2026). */
  marked?: boolean;
}

/** Почему изменился остаток. Остаток не хранится — он сумма движений:
 *  одно место правды, и журнал объясняет любое число на складе. */
export type MoveReason =
  | { kind: "receipt" }
  | { kind: "writeoff"; requestId: string }
  | { kind: "return"; requestId: string }
  | { kind: "count" };

export interface StockMove {
  id: string;
  itemId: string;
  /** В единицах позиции; расход — отрицательный. */
  delta: number;
  at: string;
  reason: MoveReason;
}

export interface PartLine {
  itemId: string;
  qty: number;
}
