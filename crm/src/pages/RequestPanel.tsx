import { useEffect, useRef, type ReactNode } from "react";
import { CalendarClock, Globe, Phone, Smartphone, X } from "lucide-react";
import { Button } from "@/components/ui/button";
import {
  Combobox,
  ComboboxContent,
  ComboboxEmpty,
  ComboboxInput,
  ComboboxItem,
  ComboboxList,
} from "@/components/ui/combobox";
import { Select, SelectContent, SelectItem, SelectTrigger } from "@/components/ui/select";
import { Meter, StatusBadge } from "@/components/bits";
import { ago, dateTime, km, percent, tel } from "@/data/format";
import { isActive, isOnShift } from "@/data/staff";
import { roleName } from "@/data/stats";
import { useStore } from "@/data/store";
import { STATUS_LABEL, type RequestStatus, type ServiceRequest } from "@/data/types";
import { PartsSection } from "@/pages/Parts";

const STATUSES = Object.keys(STATUS_LABEL) as RequestStatus[];

/** Заявка целиком — панелью справа поверх списка. Раньше она раскрывалась
 *  аккордеоном прямо в строке, и пользователь терял, где кончается одна
 *  заявка и начинается следующая (замечание 28.09.2026). Панель читается
 *  сверху вниз как порядок работы: кто и на чём приехал → с чем → что
 *  потратили → следующий шаг внизу. */
export function RequestPanel({ request: r, onClose }: { request: ServiceRequest; onClose: () => void }) {
  const closeRef = useRef<HTMLButtonElement>(null);

  useEffect(() => {
    closeRef.current?.focus();
    const prev = document.body.style.overflow;
    document.body.style.overflow = "hidden";
    function onKey(e: KeyboardEvent) {
      // Esc из открытого списка выбора закрывает сам список — его обработчик
      // успевает раньше и гасит событие.
      if (e.key === "Escape" && !e.defaultPrevented) onClose();
    }
    window.addEventListener("keydown", onKey);
    return () => {
      document.body.style.overflow = prev;
      window.removeEventListener("keydown", onKey);
    };
  }, [onClose]);

  const SourceIcon = r.payload.source === "app" ? Smartphone : Globe;

  return (
    <div className="fixed inset-0 z-40" role="dialog" aria-modal="true" aria-labelledby="request-title">
      <div className="absolute inset-0 bg-black/50 animate-in fade-in-0" onClick={onClose} aria-hidden />
      <div className="absolute inset-y-0 right-0 flex w-full flex-col border-l border-border bg-background shadow-2xl animate-in slide-in-from-right-8 duration-200 sm:w-[620px]">
        {/* Шапка: номер и статус — то, по чему заявку ищут и называют вслух. */}
        <header className="flex items-start gap-3 border-b border-border px-5 py-4">
          <div className="flex min-w-0 flex-1 flex-col gap-1">
            <div className="flex items-center gap-2.5">
              <h2 id="request-title" className="text-[18px] font-semibold tabular-nums">
                Заявка №{r.number}
              </h2>
              <StatusBadge status={r.status} />
            </div>
            <p className="flex items-center gap-1.5 text-[12px] text-muted-foreground">
              <SourceIcon className="size-3.5" aria-hidden />
              {r.payload.source === "app" ? "Из приложения Beepy" : "С сайта-визитки"} · пришла {ago(r.createdAt)}
            </p>
          </div>
          <Button ref={closeRef} variant="ghost" size="icon-compact" aria-label="Закрыть" onClick={onClose}>
            <X />
          </Button>
        </header>

        <div className="flex-1 overflow-y-auto">
          <Facts request={r} />

          <Section
            step={1}
            title="С чем приехал клиент"
            hint={
              r.payload.source === "app"
                ? "Beepy послушал мотор до записи. Это подсказка, а не диагноз — проверьте на месте."
                : "Клиент оставил запись на сайте-визитке."
            }
          >
            <p className="text-[14px] font-medium">{r.summary}</p>
            {r.payload.source === "app" ? (
              <ul className="flex flex-col divide-y divide-border rounded-lg border border-border">
                {r.payload.findings.map((f) => (
                  <li key={f.title} className="flex flex-col gap-1.5 px-3 py-2.5">
                    <div className="flex items-baseline justify-between gap-3">
                      <span className="text-[13px] font-medium">
                        {f.title}
                        <span className="font-normal text-muted-foreground"> · {f.system}</span>
                      </span>
                      <span className="shrink-0 text-[12px] tabular-nums text-muted-foreground">
                        уверенность {percent(f.confidence)}
                      </span>
                    </div>
                    <Meter share={f.confidence} tone={f.confidence >= 0.7 ? "bg-amber-500" : "bg-muted-foreground"} />
                    <p className="text-[12px] text-muted-foreground">Что проверить: {f.advice}</p>
                  </li>
                ))}
              </ul>
            ) : (
              <div className="flex flex-col gap-2 rounded-lg border border-border px-3 py-2.5">
                <p className="text-[13px] leading-relaxed">«{r.payload.comment}»</p>
                {r.payload.preferredAt && (
                  <p className="flex items-center gap-1.5 text-[12px] text-muted-foreground">
                    <CalendarClock className="size-3.5" aria-hidden />
                    Удобно приехать: {dateTime(r.payload.preferredAt)}
                  </p>
                )}
              </div>
            )}
          </Section>

          <Section
            step={2}
            title="Запчасти и материалы"
            hint={`Выберите работу — масло по норме для ${r.car.name} и подходящий фильтр подставятся сами. Проверьте количество и спишите со склада.`}
          >
            <PartsSection request={r} />
          </Section>
        </div>

        <NextStep request={r} />
      </div>
    </div>
  );
}

function Section({ step, title, hint, children }: { step: number; title: string; hint: string; children: ReactNode }) {
  return (
    <section className="flex flex-col gap-3 border-b border-border px-5 py-5">
      <div className="flex gap-3">
        <span className="flex size-5 shrink-0 items-center justify-center rounded-full border border-border text-[11px] font-medium tabular-nums text-muted-foreground">
          {step}
        </span>
        <div className="flex flex-col gap-0.5">
          <h3 className="text-[14px] font-semibold">{title}</h3>
          <p className="text-[12px] text-muted-foreground">{hint}</p>
        </div>
      </div>
      <div className="flex flex-col gap-3 pl-8">{children}</div>
    </section>
  );
}

/** Четыре клетки с границами: клиент, машина, исполнитель, статус. Поля,
 *  которые правят, — рядом с полями, которые читают, а не в другой колонке. */
function Facts({ request: r }: { request: ServiceRequest }) {
  const { state, dispatch } = useStore();
  // Деактивированных не назначают; но если он исполнитель этой заявки,
  // строка остаётся — иначе поле показало бы пустоту вместо имени.
  const people = state.employees
    .filter((e) => isActive(e) || e.id === r.assigneeId)
    .sort((a, b) => Number(isOnShift(b)) - Number(isOnShift(a)));
  const items = people.map((e) => ({
    value: e.id,
    label: `${e.name} — ${roleName(state.roles, e.roleId)}${
      !isActive(e) ? " (деактивирован)" : isOnShift(e) ? "" : " (не на смене)"
    }`,
  }));
  const car = [r.car.plate, r.car.mileage ? km(r.car.mileage) : undefined].filter(Boolean).join(" · ");

  return (
    <dl className="grid grid-cols-1 border-b border-border sm:grid-cols-2 [&>div]:border-border [&>div]:px-5 [&>div]:py-3.5 sm:[&>div:nth-child(odd)]:border-r [&>div:nth-child(-n+2)]:border-b max-sm:[&>div]:border-b">
      <div className="flex flex-col gap-1">
        <dt className="text-[11px] font-medium uppercase tracking-wide text-muted-foreground">Клиент</dt>
        <dd className="text-[13px] font-medium">{r.client.name}</dd>
        <dd>
          <a href={tel(r.client.phone)} className="inline-flex items-center gap-1.5 text-[13px] text-primary hover:underline">
            <Phone className="size-3.5" aria-hidden />
            {r.client.phone}
          </a>
        </dd>
      </div>
      <div className="flex flex-col gap-1">
        <dt className="text-[11px] font-medium uppercase tracking-wide text-muted-foreground">Машина</dt>
        <dd className="text-[13px] font-medium">{r.car.name}</dd>
        <dd className="text-[12px] text-muted-foreground">{car || "Номер и пробег не указаны"}</dd>
      </div>
      <div className="flex flex-col gap-1.5">
        <dt className="text-[11px] font-medium uppercase tracking-wide text-muted-foreground">Исполнитель</dt>
        <dd>
          <Combobox
            items={items}
            value={r.assigneeId ?? ""}
            onValueChange={(v) => dispatch({ type: "assign", id: r.id, employeeId: v || undefined })}
            size="compact"
          >
            <ComboboxInput placeholder="Назначить сотрудника" clearable />
            <ComboboxContent>
              <ComboboxList>
                {(item) =>
                  typeof item === "string" ? null : (
                    <ComboboxItem key={item.value} value={item.value}>
                      {item.label}
                    </ComboboxItem>
                  )
                }
              </ComboboxList>
              <ComboboxEmpty>Никого не нашли</ComboboxEmpty>
            </ComboboxContent>
          </Combobox>
        </dd>
      </div>
      <div className="flex flex-col gap-1.5">
        <dt className="text-[11px] font-medium uppercase tracking-wide text-muted-foreground">Статус</dt>
        <dd>
          <Select
            value={r.status}
            onValueChange={(v) => dispatch({ type: "setStatus", id: r.id, status: v as RequestStatus })}
            size="compact"
          >
            <SelectTrigger />
            <SelectContent>
              {STATUSES.map((s, i) => (
                <SelectItem key={s} index={i} value={s}>
                  {STATUS_LABEL[s]}
                </SelectItem>
              ))}
            </SelectContent>
          </Select>
        </dd>
      </div>
    </dl>
  );
}

/** Подвал — одна главная кнопка «что дальше» по статусу. Человеку не нужно
 *  помнить порядок: взять в работу → готово; если расход не списан,
 *  закрытие само предлагает его списать. */
function NextStep({ request: r }: { request: ServiceRequest }) {
  const { dispatch } = useStore();
  const set = (status: RequestStatus) => dispatch({ type: "setStatus", id: r.id, status });
  const unwritten = Boolean(r.parts?.length) && !r.partsWrittenOffAt;

  let note: string | null = null;
  let actions: ReactNode = null;

  switch (r.status) {
    case "new":
      // Назначение само переводит новую заявку в работу (правило хранилища),
      // поэтому подсказка про него, а кнопка — только если статус вернули
      // в «Новую» вручную при уже назначенном исполнителе.
      note = r.assigneeId ? "Исполнитель назначен — можно начинать." : "Назначьте исполнителя выше — заявка сразу уйдёт в работу.";
      actions = (
        <>
          <Button variant="ghost" onClick={() => set("cancelled")}>
            Отменить заявку
          </Button>
          {r.assigneeId && <Button onClick={() => set("in_progress")}>Взять в работу</Button>}
        </>
      );
      break;
    case "in_progress":
      note = unwritten ? "Расход не списан — при закрытии спишем его со склада." : null;
      actions = (
        <>
          <Button variant="ghost" onClick={() => set("waiting_parts")}>
            Ждём запчасти
          </Button>
          <Button
            onClick={() => {
              if (unwritten) dispatch({ type: "writeOff", requestId: r.id });
              set("done");
            }}
          >
            {unwritten ? "Списать расход и закрыть" : "Готово, закрыть заявку"}
          </Button>
        </>
      );
      break;
    case "waiting_parts":
      note = "Заявка ждёт запчасти.";
      actions = <Button onClick={() => set("in_progress")}>Запчасти пришли — в работу</Button>;
      break;
    case "done":
    case "cancelled":
      note = r.status === "done" ? "Заявка закрыта." : "Заявка отменена.";
      actions = (
        <Button variant="ghost" onClick={() => set("in_progress")}>
          Вернуть в работу
        </Button>
      );
      break;
  }

  return (
    <footer className="flex flex-wrap items-center gap-3 border-t border-border bg-card px-5 py-3">
      {note && <p className="min-w-0 flex-1 text-[12px] text-muted-foreground">{note}</p>}
      <div className="ml-auto flex items-center gap-2">{actions}</div>
    </footer>
  );
}
