import { useEffect, useState } from "react";
import { PageHeader } from "@/components/bits";
import { dateTime } from "@/data/format";
import { api, shortId, type AuditEntry } from "./api";

const ACTION_LABEL: Record<string, string> = {
  "admin.login": "Вход в админку",
  "admin.login_failed": "Неудачный вход",
  "accounts.list": "Список аккаунтов",
  "account.view": "Просмотр аккаунта",
  "account.delete": "Удаление аккаунта",
  "device.revoke": "Отзыв устройства",
};

/** Журнал доступа к персональным данным (152-ФЗ): кто, когда и что
 *  смотрел или менял. Удаление аккаунта самим человеком из приложения тоже
 *  здесь — автор «приложение». Последние 100 записей. */
export function AuditPage({ onOpenAccount }: { onOpenAccount: (id: string) => void }) {
  const [entries, setEntries] = useState<AuditEntry[] | null>(null);

  useEffect(() => {
    api
      .audit()
      .then((r) => setEntries(r.entries))
      .catch(() => setEntries([]));
  }, []);

  const cell = "border-r border-border px-3 last:border-r-0";

  return (
    <div className="flex flex-col gap-5">
      <PageHeader title="Журнал доступа" subtitle="Кто смотрел и менял персональные данные" />
      {entries && entries.length === 0 ? (
        <p className="py-16 text-center text-[13px] text-muted-foreground">Записей нет</p>
      ) : (
        <div className="overflow-x-auto rounded-lg border border-border">
          <table className="w-full min-w-[720px] border-collapse text-[13px]">
            <thead>
              <tr className="border-b border-border bg-muted/60">
                {["Когда", "Кто", "Что", "Аккаунт", "Подробности"].map((title) => (
                  <th key={title} scope="col" className={`${cell} h-9 text-left text-[12px] font-medium text-muted-foreground`}>
                    {title}
                  </th>
                ))}
              </tr>
            </thead>
            <tbody>
              {(entries ?? []).map((e) => (
                <tr key={e.id} className="h-10 border-b border-border last:border-b-0">
                  <td className={`${cell} whitespace-nowrap text-[12px] text-muted-foreground`}>{dateTime(e.at)}</td>
                  <td className={cell}>{e.actor === "app" ? "Приложение" : e.actor}</td>
                  <td className={cell}>
                    <span className={e.action === "admin.login_failed" ? "text-amber-600 dark:text-amber-400" : undefined}>
                      {ACTION_LABEL[e.action] ?? e.action}
                    </span>
                  </td>
                  <td className={cell}>
                    {e.account_id ? (
                      <button
                        type="button"
                        className="font-mono text-[12px] underline-offset-2 hover:underline"
                        onClick={() => onOpenAccount(e.account_id!)}
                      >
                        {shortId(e.account_id)}
                      </button>
                    ) : (
                      <span className="text-muted-foreground">—</span>
                    )}
                  </td>
                  <td className={`${cell} text-[12px] text-muted-foreground`}>
                    {Object.entries(e.details)
                      .filter(([, v]) => v !== "" && v !== undefined)
                      .map(([k, v]) => `${k}: ${k === "device" ? shortId(String(v)) : String(v)}`)
                      .join(" · ")}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </div>
  );
}
