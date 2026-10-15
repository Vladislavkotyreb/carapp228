import { useState } from "react";
import { Phone, Plus, RotateCcw, Trash2, User, UserX } from "lucide-react";
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
import { count, date, tel } from "@/data/format";
import { isActive, isOnShift } from "@/data/staff";
import { isOpen } from "@/data/stats";
import { useStore } from "@/data/store";
import { roleName } from "@/data/stats";
import type { Employee } from "@/data/types";

type Tab = "people" | "roles";

export function EmployeesPage() {
  const { state } = useStore();
  const [tab, setTab] = useState<Tab>("people");
  const [adding, setAdding] = useState(false);
  const [editing, setEditing] = useState<Employee | null>(null);
  const active = state.employees.filter(isActive);
  const onShift = active.filter((e) => isOnShift(e)).length;

  return (
    <div className="flex flex-col gap-5">
      <PageHeader
        title="Сотрудники"
        subtitle={`${count(active.length, "человек", "человека", "человек")}, на смене ${onShift}`}
        actions={
          <Button leadingIcon={Plus} onClick={() => setAdding(true)} disabled={state.roles.length === 0}>
            Добавить
          </Button>
        }
      />

      <Tabs value={tab} onValueChange={(v) => setTab(v as Tab)}>
        <TabsList>
          <TabItem value="people" label="Сотрудники" />
          <TabItem value="roles" label="Роли" />
        </TabsList>
        <TabPanel value="people" className="pt-4">
          <PeopleTable onEdit={setEditing} />
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
  const [show, setShow] = useState<"active" | "inactive">("active");
  const inactive = state.employees.filter((e) => !isActive(e));
  const shown = state.employees.filter((e) => (show === "active" ? isActive(e) : !isActive(e)));

  return (
    <div className="flex flex-col gap-3">
    {/* Деактивированных не видно, пока их нет: вкладка для пустого списка —
        лишний вопрос. */}
    {inactive.length > 0 && (
      <Tabs value={show} onValueChange={(v) => setShow(v as "active" | "inactive")}>
        <TabsList>
          <TabItem value="active" label={`Работают · ${state.employees.length - inactive.length}`} />
          <TabItem value="inactive" label={`Деактивированы · ${inactive.length}`} />
        </TabsList>
      </Tabs>
    )}
    {show === "inactive" ? (
      <ul className="flex flex-col divide-y divide-border rounded-xl border border-border">
        {shown.map((e) => (
          <li key={e.id} className="flex flex-wrap items-center gap-3 px-4 py-2.5">
            <Avatar name={e.name} muted />
            <span className="flex min-w-0 flex-1 flex-col">
              <span className="text-[13px] font-medium text-muted-foreground">{e.name}</span>
              <span className="text-[12px] text-muted-foreground">
                {roleName(state.roles, e.roleId)} · деактивирован {date(e.deactivatedAt!)}
              </span>
            </span>
            <Button
              variant="ghost"
              size="compact"
              leadingIcon={RotateCcw}
              onClick={() => dispatch({ type: "reactivate", id: e.id })}
            >
              Вернуть
            </Button>
          </li>
        ))}
      </ul>
    ) : (
    <Table>
      <TableHeader>
        <TableRow>
          <TableHead>Сотрудник</TableHead>
          <TableHead>Роль</TableHead>
          <TableHead>Телефон</TableHead>
          <TableHead className="text-right">Открытые заявки</TableHead>
          <TableHead className="text-right">На смене</TableHead>
        </TableRow>
      </TableHeader>
      <TableBody>
        {shown.map((e, i) => {
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
              <TableCell>
                <a href={tel(e.phone)} className="hover:underline">
                  {e.phone}
                </a>
              </TableCell>
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
    )}
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
  const [tried, setTried] = useState(false);
  const [loadedFor, setLoadedFor] = useState<string | null>(null);
  /** Второй шаг — подтверждение деактивации в том же окне. */
  const [confirming, setConfirming] = useState(false);

  // Открыли правку другого сотрудника — подставляем его значения. Так, а не
  // эффектом: значения нужны в том же кадре, в котором открылся диалог.
  const key = open ? (employee?.id ?? "new") : null;
  if (key !== loadedFor) {
    setLoadedFor(key);
    setName(employee?.name ?? "");
    setPhone(employee?.phone ?? "");
    setRoleId(employee?.roleId ?? state.roles[0]?.id ?? "");
    setTried(false);
    setConfirming(false);
  }

  const openAssigned = editing
    ? state.requests.filter((r) => isOpen(r) && r.assigneeId === employee.id).length
    : 0;

  const nameError = !editing && tried && !name.trim() ? "Нужно имя" : undefined;
  const phoneError = !editing && tried && phone.replace(/\D/g, "").length < 10 ? "Нужен телефон" : undefined;

  function submit() {
    setTried(true);
    if (!roleId) return;
    if (editing) {
      dispatch({ type: "updateEmployee", id: employee.id, roleId });
    } else {
      if (!name.trim() || phone.replace(/\D/g, "").length < 10) return;
      dispatch({ type: "addEmployee", name: name.trim(), phone: phone.trim(), roleId });
    }
    onOpenChange(false);
  }

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent size="sm">
        <DialogHeader>
          <DialogTitle>{editing ? employee.name : "Новый сотрудник"}</DialogTitle>
          <DialogDescription>
            {editing ? "Роль в сервисе." : "Появится в исполнителях заявок, сегодня — на смене."}
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
        </div>
        {confirming && editing ? (
          <div className="flex flex-col gap-2 rounded-lg border border-red-500/30 bg-red-500/5 p-3 text-[13px]">
            <span className="font-medium">Деактивировать сотрудника?</span>
            <span className="text-muted-foreground">
              Пропадёт из исполнителей, канбана и загрузки. Закрытые заявки останутся под этим именем.
              Вернуть можно в любой момент.
              {openAssigned > 0 &&
                ` ${count(openAssigned, "открытая заявка останется", "открытые заявки останутся", "открытых заявок останутся")} без исполнителя.`}
            </span>
          </div>
        ) : null}
        <DialogFooter>
          {editing && !confirming && (
            <Button variant="ghost" leadingIcon={UserX} className="mr-auto text-red-500" onClick={() => setConfirming(true)}>
              Деактивировать
            </Button>
          )}
          <Button variant="ghost" onClick={() => (confirming ? setConfirming(false) : onOpenChange(false))}>
            Отмена
          </Button>
          {confirming && editing ? (
            <Button
              className="[--primary:#dc2626]"
              onClick={() => {
                dispatch({ type: "deactivate", id: employee.id });
                onOpenChange(false);
              }}
            >
              Деактивировать
            </Button>
          ) : (
            <Button onClick={submit}>{editing ? "Сохранить" : "Добавить"}</Button>
          )}
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
