import { useState } from "react";
import { Phone, Plus, User } from "lucide-react";
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
import { Avatar, PageHeader } from "@/components/bits";
import { count, tel } from "@/data/format";
import { useStore } from "@/data/store";
import { isOpen } from "@/data/stats";
import { ROLE_LABEL, type Role } from "@/data/types";

const ROLES = Object.keys(ROLE_LABEL) as Role[];

export function EmployeesPage() {
  const { state, dispatch } = useStore();
  const [adding, setAdding] = useState(false);
  const onShift = state.employees.filter((e) => e.onShift).length;

  return (
    <div className="flex flex-col gap-5">
      <PageHeader
        title="Сотрудники"
        subtitle={`${count(state.employees.length, "человек", "человека", "человек")}, на смене ${onShift}`}
        actions={
          <Button leadingIcon={Plus} onClick={() => setAdding(true)}>
            Добавить
          </Button>
        }
      />

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
          {state.employees.map((e, i) => {
            const open = state.requests.filter((r) => isOpen(r) && r.assigneeId === e.id).length;
            return (
              <TableRow key={e.id} index={i}>
                <TableCell>
                  <span className="flex items-center gap-2.5">
                    <Avatar name={e.name} muted={!e.onShift} />
                    <span className="font-medium">{e.name}</span>
                  </span>
                </TableCell>
                <TableCell className="text-muted-foreground">{ROLE_LABEL[e.role]}</TableCell>
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
                      checked={e.onShift}
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

      <AddEmployeeDialog open={adding} onOpenChange={setAdding} />
    </div>
  );
}

function AddEmployeeDialog({ open, onOpenChange }: { open: boolean; onOpenChange: (open: boolean) => void }) {
  const { dispatch } = useStore();
  const [name, setName] = useState("");
  const [phone, setPhone] = useState("");
  const [role, setRole] = useState<Role>("mechanic");
  const [tried, setTried] = useState(false);

  const nameError = tried && !name.trim() ? "Нужно имя" : undefined;
  const phoneError = tried && phone.replace(/\D/g, "").length < 10 ? "Нужен телефон" : undefined;

  function close(next: boolean) {
    onOpenChange(next);
    if (!next) {
      setName("");
      setPhone("");
      setRole("mechanic");
      setTried(false);
    }
  }

  function submit() {
    setTried(true);
    if (!name.trim() || phone.replace(/\D/g, "").length < 10) return;
    dispatch({ type: "addEmployee", name: name.trim(), phone: phone.trim(), role });
    close(false);
  }

  return (
    <Dialog open={open} onOpenChange={close}>
      <DialogContent size="sm">
        <DialogHeader>
          <DialogTitle>Новый сотрудник</DialogTitle>
          <DialogDescription>Появится в списке исполнителей заявок сразу, отмеченным на смене.</DialogDescription>
        </DialogHeader>
        <div className="flex flex-col gap-3">
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
          <Select value={role} onValueChange={(v) => setRole(v as Role)}>
            <SelectTrigger placeholder="Роль" />
            <SelectContent>
              {ROLES.map((r, i) => (
                <SelectItem key={r} index={i} value={r}>
                  {ROLE_LABEL[r]}
                </SelectItem>
              ))}
            </SelectContent>
          </Select>
        </div>
        <DialogFooter>
          <Button variant="ghost" onClick={() => close(false)}>
            Отмена
          </Button>
          <Button onClick={submit}>Добавить</Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
