import { z } from "zod";
import type { Queryable } from "./db.ts";

/** Синхронизация поездок и машин одного аккаунта.
 *
 *  Телефон присылает свои изменения и курсор — номер последнего изменения,
 *  которое он уже видел. Сервер применяет присланное и отдаёт всё, что
 *  изменилось после курсора: правки с других устройств аккаунта.
 *
 *  Кто прав при конфликте: новее по часам телефона (`updatedAt`). Удаление
 *  окончательно — удалённую поездку правка с другого телефона не воскресит,
 *  а удаление перебивает любую правку. Отвергнутая правка возвращается
 *  телефону серверной версией, чтобы он не разошёлся с сервером. */

/** Дальше часы телефона не убегают: правка «из будущего» иначе выигрывала бы
 *  все конфликты навсегда. */
const MAX_CLOCK_LEAD_MS = 24 * 3600 * 1000;
/** Одна поездка — не длиннее 2000 км (как `TripMath.maxTripKm` в приложении). */
const MAX_TRIP_METERS = 2_000_000;
export const PAGE = 500;
/** Поле пробега в приложении берёт до девяти цифр (`NumberFormat`), сверху
 *  набегают поездки; integer в Postgres — до 2^31. */
const ODOMETER_MAX = 1_999_999_999;

const isoDate = z
  .string()
  .datetime({ offset: true })
  .refine((v) => Date.parse(v) <= Date.now() + MAX_CLOCK_LEAD_MS, "date in the future");

export const carIn = z.object({
  id: z.string().uuid(),
  name: z.string().trim().min(1).max(120),
  odometer: z.number().int().min(0).max(ODOMETER_MAX),
  trackedKm: z.number().int().min(0).max(ODOMETER_MAX),
  updatedAt: isoDate,
  deleted: z.boolean(),
});

export const tripIn = z
  .object({
    id: z.string().uuid(),
    // Нет поля — то же, что null: поездка без машины.
    carId: z.string().uuid().nullish().transform((v) => v ?? null),
    startedAt: isoDate,
    endedAt: isoDate,
    meters: z.number().min(0).max(MAX_TRIP_METERS),
    auto: z.boolean(),
    updatedAt: isoDate,
    deleted: z.boolean(),
  })
  .refine((t) => Date.parse(t.endedAt) >= Date.parse(t.startedAt), "ends before it starts");

export const syncRequest = z.object({
  cursor: z.string().regex(/^\d{1,15}$/).nullable(),
  cars: z.array(carIn).max(100),
  trips: z.array(tripIn).max(PAGE),
});

export type CarIn = z.infer<typeof carIn>;
export type TripIn = z.infer<typeof tripIn>;
export type SyncRequest = z.infer<typeof syncRequest>;

export type CarOut = CarIn;
export type TripOut = z.infer<typeof tripIn>;
export type SyncResponse = { cursor: string; more: boolean; cars: CarOut[]; trips: TripOut[] };

type CarRow = {
  id: string;
  name: string;
  odometer: number;
  tracked_km: number;
  updated_at: Date;
  deleted: boolean;
  seq: number | string;
};
type TripRow = {
  id: string;
  car_id: string | null;
  started_at: Date;
  ended_at: Date;
  meters: number;
  auto: boolean;
  updated_at: Date;
  deleted: boolean;
  seq: number | string;
};

const iso = (d: Date) => d.toISOString();
const carOut = (r: CarRow): CarOut => ({
  id: r.id,
  name: r.name,
  odometer: r.odometer,
  trackedKm: r.tracked_km,
  updatedAt: iso(r.updated_at),
  deleted: r.deleted,
});
const tripOut = (r: TripRow): TripOut => ({
  id: r.id,
  carId: r.car_id,
  startedAt: iso(r.started_at),
  endedAt: iso(r.ended_at),
  meters: r.meters,
  auto: r.auto,
  updatedAt: iso(r.updated_at),
  deleted: r.deleted,
});

// Правило конфликта в одном месте: обновить, если запись не удалена и
// пришедшее — удаление или правка новее.
const WINS = (table: string) => `not ${table}.deleted and (excluded.deleted or excluded.updated_at > ${table}.updated_at)`;

/** Применить изменения телефона и собрать ответ. Зовётся в транзакции. */
export async function sync(q: Queryable, accountId: string, req: SyncRequest): Promise<SyncResponse> {
  // Синхронизации одного аккаунта идут по очереди: иначе изменение с
  // номером меньше курсора могло бы записаться позже и потеряться для того,
  // кто курсор уже передвинул.
  await q.query("select id from accounts where id = $1 for update", [accountId]);

  const appliedCars = new Set<string>();
  for (const car of req.cars) {
    const rows = await q.query<{ id: string }>(
      `insert into cars (account_id, id, name, odometer, tracked_km, updated_at, deleted, seq)
       values ($1, $2, $3, $4, $5, $6, $7, nextval('change_seq'))
       on conflict (account_id, id) do update set
         name = excluded.name, odometer = excluded.odometer, tracked_km = excluded.tracked_km,
         updated_at = excluded.updated_at, deleted = excluded.deleted, seq = excluded.seq
       where ${WINS("cars")}
       returning id`,
      [accountId, car.id, car.name, car.odometer, car.trackedKm, car.updatedAt, car.deleted],
    );
    if (rows.length) appliedCars.add(car.id);
  }

  const appliedTrips = new Set<string>();
  for (const trip of req.trips) {
    const rows = await q.query<{ id: string }>(
      `insert into trips (account_id, id, car_id, started_at, ended_at, meters, auto, updated_at, deleted, seq)
       values ($1, $2, $3, $4, $5, $6, $7, $8, $9, nextval('change_seq'))
       on conflict (account_id, id) do update set
         car_id = excluded.car_id, started_at = excluded.started_at, ended_at = excluded.ended_at,
         meters = excluded.meters, auto = excluded.auto, updated_at = excluded.updated_at,
         deleted = excluded.deleted, seq = excluded.seq
       where ${WINS("trips")}
       returning id`,
      [accountId, trip.id, trip.carId, trip.startedAt, trip.endedAt, trip.meters, trip.auto, trip.updatedAt, trip.deleted],
    );
    if (rows.length) appliedTrips.add(trip.id);
  }

  const cursor = Number(req.cursor ?? 0);
  const cars = await q.query<CarRow>(
    "select id, name, odometer, tracked_km, updated_at, deleted, seq from cars where account_id = $1 and seq > $2 order by seq limit $3",
    [accountId, cursor, PAGE + 1],
  );
  const trips = await q.query<TripRow>(
    `select id, car_id, started_at, ended_at, meters, auto, updated_at, deleted, seq
     from trips where account_id = $1 and seq > $2 order by seq limit $3`,
    [accountId, cursor, PAGE + 1],
  );

  // Страница: не больше PAGE записей каждого вида; курсор — по последней
  // отданной, чтобы следующий запрос продолжил с неё.
  const more = cars.length > PAGE || trips.length > PAGE;
  const pageCars = cars.slice(0, PAGE);
  const pageTrips = trips.slice(0, PAGE);
  let next = cursor;
  if (more) {
    const lastCar = cars.length > PAGE ? Number(pageCars.at(-1)!.seq) : Infinity;
    const lastTrip = trips.length > PAGE ? Number(pageTrips.at(-1)!.seq) : Infinity;
    next = Math.min(lastCar, lastTrip);
  } else {
    for (const r of [...pageCars, ...pageTrips]) next = Math.max(next, Number(r.seq));
  }
  const within = (r: { seq: number | string }) => Number(r.seq) <= next;

  // Своё эхо телефону не нужно; отвергнутое — нужно, даже если оно старше
  // курсора: иначе телефон останется при своей версии.
  const outCars = pageCars.filter((r) => within(r) && !appliedCars.has(r.id)).map(carOut);
  const outTrips = pageTrips.filter((r) => within(r) && !appliedTrips.has(r.id)).map(tripOut);
  const seenCars = new Set(outCars.map((c) => c.id));
  const seenTrips = new Set(outTrips.map((t) => t.id));
  const rejectedCars = req.cars.map((c) => c.id).filter((id) => !appliedCars.has(id) && !seenCars.has(id));
  const rejectedTrips = req.trips.map((t) => t.id).filter((id) => !appliedTrips.has(id) && !seenTrips.has(id));
  if (rejectedCars.length) {
    const rows = await q.query<CarRow>(
      "select id, name, odometer, tracked_km, updated_at, deleted, seq from cars where account_id = $1 and id = any($2::uuid[])",
      [accountId, rejectedCars],
    );
    outCars.push(...rows.map(carOut));
  }
  if (rejectedTrips.length) {
    const rows = await q.query<TripRow>(
      `select id, car_id, started_at, ended_at, meters, auto, updated_at, deleted, seq
       from trips where account_id = $1 and id = any($2::uuid[])`,
      [accountId, rejectedTrips],
    );
    outTrips.push(...rows.map(tripOut));
  }

  await q.query("update accounts set last_sync_at = now() where id = $1", [accountId]);
  return { cursor: String(next), more, cars: outCars, trips: outTrips };
}
