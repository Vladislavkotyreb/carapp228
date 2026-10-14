import { useCallback, useEffect, useRef, useState, type ReactNode } from "react";
import { Search, Smartphone, X } from "lucide-react";
import { Badge } from "@/components/ui/badge";
import { Button } from "@/components/ui/button";
import { InputField, InputGroup } from "@/components/ui/input-group";
import { PageHeader } from "@/components/bits";
import { ago, count, dateTime, grouped, km } from "@/data/format";
import { api, shortId, type AccountDetail, type AccountRow } from "./api";

const COLS = [
  { title: "Аккаунт", className: "w-[200px]" },
  { title: "Машины", className: "w-[90px] text-right" },
  { title: "Поездки", className: "w-[100px] text-right" },
  { title: "Проехали", className: "w-[130px] text-right" },
  { title: "Устройства", className: "w-[110px] text-right" },
  { title: "Синхронизация", className: "w-[150px] text-right" },
];

/** Аккаунты приложения. Имени и телефона у аккаунта нет — он анонимный, и
 *  искать можно только по идентификатору. Открытие аккаунта и сам список
 *  пишутся в журнал доступа. */
export function AccountsPage({ openId, onOpen }: { openId: string | null; onOpen: (id: string | null) => void }) {
  const [query, setQuery] = useState("");
  const [rows, setRows] = useState<AccountRow[] | null>(null);
  const [total, setTotal] = useState(0);

  const load = useCallback(() => {
    api
      .accounts(query.trim())
      .then((r) => {
        setRows(r.accounts);
        setTotal(r.total);
      })
      .catch(() => setRows([]));
  }, [query]);

  useEffect(() => {
    const timer = setTimeout(load, 250);
    return () => clearTimeout(timer);
  }, [load]);

  const cell = "border-r border-border px-3 last:border-r-0";

  return (
    <div className="flex flex-col gap-5">
      <PageHeader
        title="Аккаунты"
        subtitle={rows ? count(total, "аккаунт", "аккаунта", "аккаунтов") : undefined}
        actions={
          <InputGroup size="compact" className="w-60">
            <InputField
              index={0}
              label="Поиск"
              labelHidden
              icon={Search}
              placeholder="Начало идентификатора"
              value={query}
              onChange={setQuery}
            />
          </InputGroup>
        }
      />

      {rows && rows.length === 0 ? (
        <p className="py-16 text-center text-[13px] text-muted-foreground">
          {query ? "Такого аккаунта нет" : "Пока никто не включил синхронизацию"}
        </p>
      ) : (
        <div className="overflow-x-auto rounded-lg border border-border">
          <table className="w-full min-w-[820px] border-collapse text-[13px]">
            <thead>
              <tr className="border-b border-border bg-muted/60">
                {COLS.map((c) => (
                  <th
                    key={c.title}
                    scope="col"
                    className={`${cell} ${c.className} h-9 text-left text-[12px] font-medium text-muted-foreground`}
                  >
                    {c.title}
                  </th>
                ))}
              </tr>
            </thead>
            <tbody>
              {(rows ?? []).map((a) => (
                <tr
                  key={a.id}
                  tabIndex={0}
                  aria-selected={a.id === openId}
                  onClick={() => onOpen(a.id)}
                  onKeyDown={(e) => {
                    if (e.key === "Enter" || e.key === " ") {
                      e.preventDefault();
                      onOpen(a.id);
                    }
                  }}
                  className={
                    "h-12 cursor-pointer border-b border-border outline-none transition-colors last:border-b-0 hover:bg-hover focus-visible:bg-hover " +
                    (a.id === openId ? "bg-primary/10 shadow-[inset_2px_0_0_var(--primary)]" : "")
                  }
                >
                  <td className={cell}>
                    <span className="flex flex-col">
                      <span className="font-mono text-[12px] font-medium">{shortId(a.id)}</span>
                      <span className="text-[12px] text-muted-foreground">создан {ago(a.created_at)}</span>
                    </span>
                  </td>
                  <td className={`${cell} text-right tabular-nums`}>{a.cars}</td>
                  <td className={`${cell} text-right tabular-nums`}>{grouped(a.trips)}</td>
                  <td className={`${cell} text-right tabular-nums`}>{km(a.meters / 1000)}</td>
                  <td className={`${cell} text-right tabular-nums`}>{a.devices}</td>
                  <td className={`${cell} text-right text-[12px] text-muted-foreground`}>
                    {a.last_sync_at ? ago(a.last_sync_at) : "не было"}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}

      {openId && (
        <AccountPanel
          id={openId}
          onClose={() => onOpen(null)}
          onDeleted={() => {
            onOpen(null);
            load();
          }}
        />
      )}
    </div>
  );
}

/** Аккаунт целиком — панелью справа, как заявка в CRM: устройства, машины,
 *  последние сто поездок. Внизу — удаление с подтверждением. */
function AccountPanel({ id, onClose, onDeleted }: { id: string; onClose: () => void; onDeleted: () => void }) {
  const [data, setData] = useState<AccountDetail | null>(null);
  const [missing, setMissing] = useState(false);
  const [confirming, setConfirming] = useState(false);
  const closeRef = useRef<HTMLButtonElement>(null);

  const load = useCallback(() => {
    api
      .account(id)
      .then(setData)
      .catch(() => setMissing(true));
  }, [id]);

  useEffect(load, [load]);

  useEffect(() => {
    closeRef.current?.focus();
    const prev = document.body.style.overflow;
    document.body.style.overflow = "hidden";
    const onKey = (e: KeyboardEvent) => {
      if (e.key === "Escape") onClose();
    };
    window.addEventListener("keydown", onKey);
    return () => {
      document.body.style.overflow = prev;
      window.removeEventListener("keydown", onKey);
    };
  }, [onClose]);

  async function revoke(deviceId: string) {
    await api.revokeDevice(deviceId);
    load();
  }

  async function remove() {
    await api.deleteAccount(id);
    onDeleted();
  }

  const carName = (carId: string | null, fallback: string | null) =>
    fallback ?? (carId ? `машина ${shortId(carId)}` : "без машины");

  return (
    <div className="fixed inset-0 z-40" role="dialog" aria-modal="true" aria-labelledby="account-title">
      <div className="absolute inset-0 bg-black/50 animate-in fade-in-0" onClick={onClose} aria-hidden />
      <div className="absolute inset-y-0 right-0 flex w-full flex-col border-l border-border bg-background shadow-2xl animate-in slide-in-from-right-8 duration-200 sm:w-[620px]">
        <header className="flex items-start gap-3 border-b border-border px-5 py-4">
          <div className="flex min-w-0 flex-1 flex-col gap-1">
            <h2 id="account-title" className="font-mono text-[15px] font-semibold">
              {id}
            </h2>
            {data && (
              <p className="text-[12px] text-muted-foreground">
                Создан {dateTime(data.account.created_at)} · согласие {data.account.consent_version}
                {data.account.last_sync_at ? ` · синхронизация ${ago(data.account.last_sync_at)}` : ""}
              </p>
            )}
          </div>
          <Button ref={closeRef} variant="ghost" size="icon-compact" aria-label="Закрыть" onClick={onClose}>
            <X />
          </Button>
        </header>

        <div className="flex-1 overflow-y-auto">
          {missing && <p className="px-5 py-10 text-[13px] text-muted-foreground">Аккаунта больше нет</p>}
          {data && (
            <>
              <Section title="Устройства">
                <ul className="flex flex-col divide-y divide-border rounded-lg border border-border">
                  {data.devices.map((d) => (
                    <li key={d.id} className="flex items-center gap-3 px-3 py-2.5">
                      <Smartphone className="size-4 shrink-0 text-muted-foreground" aria-hidden />
                      <span className="flex min-w-0 flex-1 flex-col">
                        <span className="truncate text-[13px] font-medium">
                          {[d.model || "Устройство", d.os].filter(Boolean).join(" · ")}
                        </span>
                        <span className="text-[12px] text-muted-foreground">
                          {d.app_version ? `Beepy ${d.app_version} · ` : ""}
                          {d.last_seen_at ? `был ${ago(d.last_seen_at)}` : "ещё не синхронизировал"}
                        </span>
                      </span>
                      {d.revoked_at ? (
                        <Badge variant="dot" color="red" size="compact">
                          Отозвано
                        </Badge>
                      ) : (
                        <Button variant="tertiary" size="compact" onClick={() => revoke(d.id)}>
                          Отозвать
                        </Button>
                      )}
                    </li>
                  ))}
                </ul>
              </Section>

              <Section title={`Машины · ${data.cars.filter((c) => !c.deleted).length}`}>
                {data.cars.length === 0 ? (
                  <Empty>Машин нет</Empty>
                ) : (
                  <ul className="flex flex-col divide-y divide-border rounded-lg border border-border">
                    {data.cars.map((c) => (
                      <li key={c.id} className={"flex items-baseline justify-between gap-3 px-3 py-2.5 " + (c.deleted ? "opacity-50" : "")}>
                        <span className="min-w-0 truncate text-[13px] font-medium">
                          {c.name}
                          {c.deleted && <span className="font-normal text-muted-foreground"> · удалена</span>}
                        </span>
                        <span className="shrink-0 text-[12px] tabular-nums text-muted-foreground">
                          {km(c.odometer)} · {count(c.trips, "поездка", "поездки", "поездок")}
                        </span>
                      </li>
                    ))}
                  </ul>
                )}
              </Section>

              <Section title={`Поездки · последние ${data.trips.length}`}>
                {data.trips.length === 0 ? (
                  <Empty>Поездок нет</Empty>
                ) : (
                  <ul className="flex flex-col divide-y divide-border rounded-lg border border-border">
                    {data.trips.map((t) => (
                      <li key={t.id} className="flex items-baseline justify-between gap-3 px-3 py-2">
                        <span className="flex min-w-0 flex-col">
                          <span className="text-[13px]">{dateTime(t.started_at)}</span>
                          <span className="truncate text-[12px] text-muted-foreground">
                            {carName(t.car_id, t.car_name)} · {t.auto ? "сам" : "вручную"}
                          </span>
                        </span>
                        <span className="shrink-0 text-[13px] font-medium tabular-nums">{km(t.meters / 1000)}</span>
                      </li>
                    ))}
                  </ul>
                )}
              </Section>

              <Section title="Удаление">
                <p className="text-[12px] text-muted-foreground">
                  Уйдут машины, поездки и устройства. Телефон перестанет синхронизировать; его собственные данные
                  останутся на нём.
                </p>
                {confirming ? (
                  <div className="flex items-center gap-2">
                    <Button variant="primary" className="bg-red-600" onClick={remove}>
                      Удалить навсегда
                    </Button>
                    <Button variant="ghost" onClick={() => setConfirming(false)}>
                      Отмена
                    </Button>
                  </div>
                ) : (
                  <Button variant="tertiary" className="self-start text-red-500" onClick={() => setConfirming(true)}>
                    Удалить аккаунт
                  </Button>
                )}
              </Section>
            </>
          )}
        </div>

        <footer className="border-t border-border px-5 py-2.5 text-[11px] text-muted-foreground">
          Просмотр записан в журнал доступа
        </footer>
      </div>
    </div>
  );
}

function Section({ title, children }: { title: string; children: ReactNode }) {
  return (
    <section className="flex flex-col gap-2.5 border-b border-border px-5 py-4 last:border-b-0">
      <h3 className="text-[13px] font-medium text-muted-foreground">{title}</h3>
      {children}
    </section>
  );
}

function Empty({ children }: { children: ReactNode }) {
  return <p className="text-[13px] text-muted-foreground">{children}</p>;
}
