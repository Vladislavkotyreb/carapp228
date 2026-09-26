import { useState } from "react";
import { ChevronLeft, ChevronRight, Phone, Plus, Trash2, User, Wallet } from "lucide-react";
import { Button } from "@/components/ui/button";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import { InputField, InputGroup } from "@/components/ui/input-group";
import { Select, SelectContent, SelectItem, SelectTrigger } from "@/components/ui/select";
import { Switch } from "@/components/ui/switch";
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table";
import { TabItem, TabPanel, Tabs, TabsList } from "@/components/ui/tabs";
import { Tooltip } from "@/components/ui/tooltip";
import { Avatar, PageHeader } from "@/components/bits";
import { count, tel } from "@/data/format";
import {
  daysOf,
  isOnShift,
  monthOf,
  monthTitle,
  payLabel,
  payout,
  rub,
  shiftMonth,
  todayKey,
  workdayNorm,
  workedIn,
  type Month,
} from "@/data/payroll";
import { isOpen } from "@/data/stats";
import { useStore } from "@/data/store";
import { roleName } from "@/data/stats";
import { PAY_KIND_LABEL, type Employee, type Pay } from "@/data/types";

type Tab = "people" | "timesheet" | "roles";

export function EmployeesPage() {
  const { state } = useStore();
  const [tab, setTab] = useState<Tab>("people");
  const [adding, setAdding] = useState(false);
  const [editing, setEditing] = useState<Employee | null>(null);
  const onShift = state.employees.filter((e) => isOnShift(e)).length;

  return (
    <div className="flex flex-col gap-5">
      <PageHeader
        title="Сотрудники"
        subtitle={`${count(state.employees.length, "человек", "человека", "человек")}, на смене ${onShift}`}
        actions={
          <Button leadingIcon={Plus} onClick={() => setAdding(true)} disabled={state.roles.length === 0}>
            Добавить
          </Button>
        }
      />

      <Tabs value={tab} onValueChange={(v) => setTab(v as Tab)}>
        <TabsList>
          <TabItem value="people" label="Сотрудники" />
          <TabItem value="timesheet" label="Табель и оплата" />
          <TabItem value="roles" label="Роли" />
        </TabsList>
        <TabPanel value="people" className="pt-4">
          <PeopleTable onEdit={setEditing} />
        </TabPanel>
        <TabPanel value="timesheet" className="pt-4">
          <Timesheet />
        </TabPanel>
        <TabPanel value="roles" className="pt-4">
          <Roles />
        </TabPanel>
      </Tabs>

      <EmployeeDialog open={adding} onOpenChange={setAdding} />
      <EmployeeDialog
        open={editing !== null}
        onOpenChange={(open) => !open && setEditing(null)}
        employee={editing ?? undefined}
      />
    </div>
  );
}

// MARK: - Список

function PeopleTable({ onEdit }: { onEdit: (e: Employee) => void }) {
  const { state, dispatch } = useStore();
  const month = monthOf(new Date());

  return (
    <Table>
      <TableHeader>
        <TableRow>
          <TableHead>Сотрудник</TableHead>
          <TableHead>Роль</TableHead>
          <TableHead>Оплата</TableHead>
          <TableHead>Телефон</TableHead>
          <TableHead className="text-right">Смен в месяце</TableHead>
          <TableHead className="text-right">Открытые заявки</TableHead>
          <TableHead className="text-right">На смене</TableHead>
        </TableRow>
      </TableHeader>
      <TableBody>
        {state.employees.map((e, i) => {
          const open = state.requests.filter((r) => isOpen(r) && r.assigneeId === e.id).length;
          return (
            <TableRow key={e.id} index={i}>
              <TableCell>
                {/* Имя — кнопка правки: вся строка кликом не открывается, в
                    ней живут ссылка на телефон и переключатель смены. */}
                <button
                  type="button"
                  onClick={() => onEdit(e)}
                  className="flex items-center gap-2.5 text-left hover:underline"
                >
                  <Avatar name={e.name} muted={!isOnShift(e)} />
                  <span className="font-medium">{e.name}</span>
                </button>
              </TableCell>
              <TableCell className="text-muted-foreground">{roleName(state.roles, e.roleId)}</TableCell>
              <TableCell className="tabular-nums">{payLabel(e.pay)}</TableCell>
              <TableCell>
                <a href={tel(e.phone)} className="hover:underline">
                  {e.phone}
                </a>
              </TableCell>
              <TableCell className="text-right tabular-nums">{workedIn(e, month)}</TableCell>
              <TableCell className="text-right tabular-nums">{open}</TableCell>
              <TableCell>
                <span className="flex justify-end">
                  <Switch
                    label={`${e.name} на смене`}
                    checked={isOnShift(e)}
                    onToggle={() => dispatch({ type: "toggleShift", id: e.id })}
                    size="compact"
                    // Подпись нужна скринридеру (на неё ссылается
                    // aria-labelledby), а в таблице колонка и так названа.
                    className="[&>span:last-child]:sr-only"
                  />
                </span>
              </TableCell>
            </TableRow>
          );
        })}
      </TableBody>
    </Table>
  );
}

// MARK: - Табель

/** Табель месяца: строка — человек, клетка — день. Клик отмечает смену.
 *  Будущие дни закрыты: табель — факт, а не график. */
function Timesheet() {
  const { state, dispatch } = useStore();
  const [month, setMonth] = useState<Month>(() => monthOf(new Date()));
  const days = daysOf(month);
  const today = todayKey();
  const current = monthOf(new Date());
  const isCurrent = month.year === current.year && month.month === current.month;
  const total = state.employees.reduce((sum, e) => sum + payout(e, month).amount, 0);

  return (
    <div className="flex flex-col gap-4">
      <div className="flex flex-wrap items-center gap-3">
        <div className="flex items-center gap-1">
          <Button variant="ghost" size="icon-compact" aria-label="Прошлый месяц" onClick={() => setMonth(shiftMonth(month, -1))}>
            <ChevronLeft className="size-4" />
          </Button>
          <span className="w-36 text-center text-[14px] font-medium capitalize">{monthTitle(month)}</span>
          <Button
            variant="ghost"
            size="icon-compact"
            aria-label="Следующий месяц"
            disabled={isCurrent}
            onClick={() => setMonth(shiftMonth(month, 1))}
          >
            <ChevronRight className="size-4" />
          </Button>
        </div>
        <span className="text-[12px] text-muted-foreground">
          Норма — {count(workdayNorm(month), "рабочий день", "рабочих дня", "рабочих дней")} (будни, без праздников)
        </span>
        <span className="ml-auto flex items-center gap-2 text-[13px]">
          <Wallet className="size-4 text-muted-foreground" aria-hidden />
          Фонд оплаты: <span className="font-semibold tabular-nums">{rub(total)}</span>
        </span>
      </div>

      <div className="-mx-6 overflow-x-auto px-6">
        <table className="w-max border-separate border-spacing-0 text-[12px]">
          <thead>
            <tr>
              <th className="sticky left-0 z-10 bg-background px-2 py-1.5 text-left font-medium text-muted-foreground">
                Сотрудник
              </th>
              {days.map((d) => (
                <th
                  key={d.key}
                  className={
                    "w-6 px-0 py-1.5 text-center font-medium tabular-nums " +
                    (d.key === today ? "text-foreground" : d.weekend ? "text-red-400/80" : "text-muted-foreground")
                  }
                >
                  {d.date}
                </th>
              ))}
              {/* Итоги прибиты к правому краю: на узком экране дни уезжают в
                  прокрутку, а сумма к выплате должна оставаться на виду. */}
              <th className="sticky right-[144px] z-10 bg-background px-2 py-1.5 text-right font-medium text-muted-foreground">Смен</th>
              <th className="sticky right-0 z-10 w-36 bg-background px-3 py-1.5 text-right font-medium text-muted-foreground">К выплате</th>
            </tr>
          </thead>
          <tbody>
            {state.employees.map((e) => {
              const p = payout(e, month);
              return (
                <tr key={e.id}>
                  <td className="sticky left-0 z-10 bg-background px-2 py-1">
                    <span className="flex items-center gap-2 whitespace-nowrap">
                      <Avatar name={e.name} size={20} />
                      <span className="text-[13px]">{e.name}</span>
                    </span>
                  </td>
                  {days.map((d) => {
                    const worked = e.workDays.includes(d.key);
                    const future = d.key > today;
                    return (
                      <td key={d.key} className={"p-0.5 text-center " + (d.weekend ? "bg-muted/30" : "")}>
                        <button
                          type="button"
                          disabled={future}
                          aria-pressed={worked}
                          aria-label={`${e.name}, ${d.date}: ${worked ? "работал" : "не работал"}`}
                          onClick={() => dispatch({ type: "toggleDay", id: e.id, day: d.key })}
                          className={
                            "size-5 rounded-[5px] transition-colors disabled:cursor-not-allowed disabled:opacity-30 " +
                            (worked
                              ? "bg-emerald-500 hover:bg-emerald-400"
                              : "bg-muted/60 hover:bg-muted") +
                            (d.key === today ? " ring-2 ring-[#6B97FF]/70" : "")
                          }
                        />
                      </td>
                    );
                  })}
                  <td className="sticky right-[144px] z-10 bg-background px-2 py-1 text-right tabular-nums">{p.days}</td>
                  <td className="sticky right-0 z-10 w-36 bg-background px-3 py-1 text-right">
                    <Tooltip content={p.formula}>
                      <span className="cursor-help font-medium tabular-nums">{rub(p.amount)}</span>
                    </Tooltip>
                    <div className="whitespace-nowrap text-[11px] text-muted-foreground">{payLabel(e.pay)}</div>
                  </td>
                </tr>
              );
            })}
          </tbody>
        </table>
      </div>

      <p className="text-[12px] text-muted-foreground">
        Ставка: смены × ставка. Оклад: пропорционально отработанным дням от нормы, не больше оклада — переработка и
        выходные по двойному тарифу в наброске не считаются. Наведите на сумму, чтобы увидеть расчёт.
      </p>
    </div>
  );
}

// MARK: - Роли

function Roles() {
  const { state, dispatch } = useStore();
  const [name, setName] = useState("");
  const [tried, setTried] = useState(false);
  const taken = state.roles.some((r) => r.name.toLowerCase() === name.trim().toLowerCase());
  const error = tried && !name.trim() ? "Нужно название" : taken ? "Такая роль уже есть" : undefined;

  function add() {
    setTried(true);
    if (!name.trim() || taken) return;
    dispatch({ type: "addRole", name });
    setName("");
    setTried(false);
  }

  return (
    <div className="flex max-w-xl flex-col gap-4">
      <form
        className="flex items-start gap-2"
        onSubmit={(e) => {
          e.preventDefault();
          add();
        }}
      >
        <InputGroup className="flex-1">
          <InputField index={0} label="Новая роль" placeholder="Например, шиномонтажник" value={name} onChange={setName} error={error} />
        </InputGroup>
        <Button type="submit" leadingIcon={Plus} className="mt-6">
          Добавить
        </Button>
      </form>

      <ul className="flex flex-col divide-y divide-border rounded-xl border border-border">
        {state.roles.map((r) => {
          const people = state.employees.filter((e) => e.roleId === r.id).length;
          return (
            <li key={r.id} className="flex items-center gap-3 px-4 py-2">
              <RoleName id={r.id} name={r.name} />
              <span className="w-24 text-right text-[12px] text-muted-foreground">
                {people ? count(people, "человек", "человека", "человек") : "никого"}
              </span>
              {/* Удалить можно только пустую роль: у сотрудника роль обязательна,
                  а молча оставить его «без роли» — потерять данные. */}
              <Tooltip content={people ? "Сначала переведите сотрудников на другую роль" : "Удалить роль"}>
                <span>
                  <Button
                    variant="ghost"
                    size="icon-compact"
                    aria-label={`Удалить роль ${r.name}`}
                    disabled={people > 0}
                    onClick={() => dispatch({ type: "deleteRole", id: r.id })}
                  >
                    <Trash2 className="size-4" />
                  </Button>
                </span>
              </Tooltip>
            </li>
          );
        })}
      </ul>
    </div>
  );
}

/** Название роли правится на месте: клик — поле, Enter или уход фокуса —
 *  сохранить, Escape — отменить. */
function RoleName({ id, name }: { id: string; name: string }) {
  const { dispatch } = useStore();
  const [draft, setDraft] = useState<string | null>(null);

  if (draft === null) {
    return (
      <button type="button" onClick={() => setDraft(name)} className="flex-1 text-left text-[13px] hover:underline" title="Переименовать">
        {name}
      </button>
    );
  }
  const commit = () => {
    if (draft.trim() && draft.trim() !== name) dispatch({ type: "renameRole", id, name: draft });
    setDraft(null);
  };
  return (
    <input
      autoFocus
      value={draft}
      onChange={(e) => setDraft(e.target.value)}
      onBlur={commit}
      onKeyDown={(e) => {
        if (e.key === "Enter") commit();
        if (e.key === "Escape") setDraft(null);
      }}
      aria-label="Название роли"
      className="flex-1 rounded-md border border-border bg-transparent px-2 py-1 text-[13px] outline-none focus:border-[#6B97FF]"
    />
  );
}

// MARK: - Добавление и правка

/** Одна форма на добавление и правку. У правки имя и телефон не меняются —
 *  это разговор о том, как человек работает, а не кто он. */
function EmployeeDialog({
  open,
  onOpenChange,
  employee,
}: {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  employee?: Employee;
}) {
  const { state, dispatch } = useStore();
  const editing = employee !== undefined;
  const [name, setName] = useState("");
  const [phone, setPhone] = useState("");
  const [roleId, setRoleId] = useState("");
  const [kind, setKind] = useState<Pay["kind"]>("daily");
  const [amount, setAmount] = useState("");
  const [tried, setTried] = useState(false);
  const [loadedFor, setLoadedFor] = useState<string | null>(null);

  // Открыли правку другого сотрудника — подставляем его значения. Так, а не
  // эффектом: значения нужны в том же кадре, в котором открылся диалог.
  const key = open ? (employee?.id ?? "new") : null;
  if (key !== loadedFor) {
    setLoadedFor(key);
    setName(employee?.name ?? "");
    setPhone(employee?.phone ?? "");
    setRoleId(employee?.roleId ?? state.roles[0]?.id ?? "");
    setKind(employee?.pay.kind ?? "daily");
    setAmount(employee ? String(employee.pay.kind === "daily" ? employee.pay.rate : employee.pay.salary) : "");
    setTried(false);
  }

  const value = Number(amount.replace(/\D/g, ""));
  const nameError = !editing && tried && !name.trim() ? "Нужно имя" : undefined;
  const phoneError = !editing && tried && phone.replace(/\D/g, "").length < 10 ? "Нужен телефон" : undefined;
  const amountError = tried && !(value > 0) ? "Нужна сумма" : undefined;

  function submit() {
    setTried(true);
    if (!(value > 0) || !roleId) return;
    const pay: Pay = kind === "daily" ? { kind, rate: value } : { kind, salary: value };
    if (editing) {
      dispatch({ type: "updateEmployee", id: employee.id, roleId, pay });
    } else {
      if (!name.trim() || phone.replace(/\D/g, "").length < 10) return;
      dispatch({ type: "addEmployee", name: name.trim(), phone: phone.trim(), roleId, pay });
    }
    onOpenChange(false);
  }

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent size="sm">
        <DialogHeader>
          <DialogTitle>{editing ? employee.name : "Новый сотрудник"}</DialogTitle>
          <DialogDescription>
            {editing ? "Роль и оплата. Смены отмечаются в табеле." : "Появится в исполнителях заявок и в табеле, сегодня — на смене."}
          </DialogDescription>
        </DialogHeader>
        <div className="flex flex-col gap-3">
          {!editing && (
            <InputGroup>
              <InputField index={0} label="Имя и фамилия" icon={User} value={name} onChange={setName} error={nameError} />
              <InputField
                index={1}
                label="Телефон"
                icon={Phone}
                placeholder="+7 900 000-00-00"
                value={phone}
                onChange={setPhone}
                error={phoneError}
                type="tel"
              />
            </InputGroup>
          )}
          <Select value={roleId} onValueChange={setRoleId}>
            <SelectTrigger placeholder="Роль" />
            <SelectContent>
              {state.roles.map((r, i) => (
                <SelectItem key={r.id} index={i} value={r.id}>
                  {r.name}
                </SelectItem>
              ))}
            </SelectContent>
          </Select>
          <Select value={kind} onValueChange={(v) => setKind(v as Pay["kind"])}>
            <SelectTrigger placeholder="Оплата" />
            <SelectContent>
              <SelectItem index={0} value="daily">{PAY_KIND_LABEL.daily}</SelectItem>
              <SelectItem index={1} value="monthly">{PAY_KIND_LABEL.monthly}</SelectItem>
            </SelectContent>
          </Select>
          <InputGroup>
            <InputField
              index={0}
              label={kind === "daily" ? "Ставка за смену, ₽" : "Оклад в месяц, ₽"}
              icon={Wallet}
              placeholder={kind === "daily" ? "3 500" : "70 000"}
              value={amount}
              onChange={(v) => setAmount(v.replace(/[^\d\s]/g, ""))}
              error={amountError}
              inputMode="numeric"
            />
          </InputGroup>
        </div>
        <DialogFooter>
          <Button variant="ghost" onClick={() => onOpenChange(false)}>
            Отмена
          </Button>
          <Button onClick={submit}>{editing ? "Сохранить" : "Добавить"}</Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
