import { useEffect, useState, type FormEvent } from "react";
import { LayoutDashboard, LogOut, ScrollText, Users } from "lucide-react";
import { Button } from "@/components/ui/button";
import { InputField, InputGroup } from "@/components/ui/input-group";
import {
  Sidebar,
  SidebarContent,
  SidebarFooter,
  SidebarGroup,
  SidebarGroupLabel,
  SidebarHeader,
  SidebarInset,
  SidebarMenu,
  SidebarMenuButton,
  SidebarMenuItem,
  SidebarProvider,
  SidebarTrigger,
} from "@/components/ui/sidebar";
import { Switch } from "@/components/ui/switch";
import { ApiError, api } from "./api";
import { AccountsPage } from "./Accounts";
import { AuditPage } from "./Audit";
import { OverviewPage } from "./Overview";

/** Админка Beepy — для команды, не для автосервисов: аккаунты приложения,
 *  их машины и поездки, журнал доступа. Живёт в проекте CRM ради общего
 *  кита компонентов, собирается отдельно (`npm run admin:build`) и
 *  отдаётся сервером по `/admin`. */

type Page = "overview" | "accounts" | "audit";

const THEME_KEY = "beepy-admin-theme";

function readDark(): boolean {
  try {
    return localStorage.getItem(THEME_KEY) !== "light";
  } catch {
    return true;
  }
}

export default function AdminApp() {
  const [login, setLogin] = useState<string | null | undefined>(undefined);
  const [dark, setDark] = useState(readDark);

  useEffect(() => {
    document.documentElement.classList.toggle("dark", dark);
    try {
      localStorage.setItem(THEME_KEY, dark ? "dark" : "light");
    } catch {
      // Без хранилища тема просто не запомнится.
    }
  }, [dark]);

  useEffect(() => {
    api
      .me()
      .then((me) => setLogin(me.login))
      .catch(() => setLogin(null));
  }, []);

  if (login === undefined) return null;
  if (login === null) return <LoginScreen onDone={setLogin} />;
  return <Shell login={login} dark={dark} onTheme={() => setDark((d) => !d)} onLogout={() => setLogin(null)} />;
}

const LOGIN_ERRORS: Record<string, string> = {
  wrong_credentials: "Неверный логин или пароль",
  rate_limited: "Слишком много попыток. Подождите 15 минут.",
  admin_disabled: "Админка выключена на сервере: не задан пароль",
};

function LoginScreen({ onDone }: { onDone: (login: string) => void }) {
  const [name, setName] = useState("");
  const [password, setPassword] = useState("");
  const [error, setError] = useState("");
  const [busy, setBusy] = useState(false);

  async function submit(e: FormEvent) {
    e.preventDefault();
    setBusy(true);
    setError("");
    try {
      onDone((await api.login(name, password)).login);
    } catch (err) {
      setError(LOGIN_ERRORS[err instanceof ApiError ? err.code : ""] ?? "Сервер не ответил");
    } finally {
      setBusy(false);
    }
  }

  return (
    <main className="flex min-h-svh items-center justify-center px-4">
      <form onSubmit={submit} className="flex w-full max-w-[340px] flex-col gap-5">
        <div className="flex items-center gap-2.5">
          <span className="flex size-8 items-center justify-center rounded-lg bg-amber-400 text-[14px] font-bold text-black">
            B
          </span>
          <div className="flex flex-col leading-tight">
            <h1 className="text-[17px] font-semibold">Beepy</h1>
            <p className="text-[12px] text-muted-foreground">Админка</p>
          </div>
        </div>
        <InputGroup>
          <InputField index={0} label="Логин" value={name} onChange={setName} autoComplete="username" />
          <InputField
            index={1}
            label="Пароль"
            type="password"
            value={password}
            onChange={setPassword}
            autoComplete="current-password"
          />
        </InputGroup>
        {error && <p className="text-[13px] text-red-500">{error}</p>}
        <Button type="submit" loading={busy} disabled={!name || !password}>
          Войти
        </Button>
      </form>
    </main>
  );
}

function Shell({
  login,
  dark,
  onTheme,
  onLogout,
}: {
  login: string;
  dark: boolean;
  onTheme: () => void;
  onLogout: () => void;
}) {
  const [page, setPage] = useState<Page>("overview");
  const [openAccount, setOpenAccount] = useState<string | null>(null);

  const nav: { id: Page; label: string; icon: typeof Users }[] = [
    { id: "overview", label: "Сводка", icon: LayoutDashboard },
    { id: "accounts", label: "Аккаунты", icon: Users },
    { id: "audit", label: "Журнал доступа", icon: ScrollText },
  ];

  async function logout() {
    await api.logout().catch(() => undefined);
    onLogout();
  }

  return (
    <SidebarProvider>
      <Sidebar variant="inset">
        <SidebarHeader>
          <div className="flex items-center gap-2 px-2 py-1">
            <span className="flex size-6 items-center justify-center rounded-md bg-amber-400 text-[12px] font-bold text-black">
              B
            </span>
            <span className="flex flex-col leading-tight">
              <span className="text-[13px] font-semibold">Beepy</span>
              <span className="text-[11px] text-muted-foreground">Админка</span>
            </span>
          </div>
        </SidebarHeader>
        <SidebarContent>
          <SidebarGroup>
            <SidebarGroupLabel>Синхронизация</SidebarGroupLabel>
            <SidebarMenu>
              {nav.map((item) => (
                <SidebarMenuItem key={item.id}>
                  <SidebarMenuButton icon={item.icon} isActive={page === item.id} onClick={() => setPage(item.id)}>
                    {item.label}
                  </SidebarMenuButton>
                </SidebarMenuItem>
              ))}
            </SidebarMenu>
          </SidebarGroup>
        </SidebarContent>
        <SidebarFooter>
          <div className="flex flex-col gap-2 px-2 py-1">
            <Switch label="Тёмная тема" checked={dark} onToggle={onTheme} size="compact" />
            <div className="flex items-center justify-between gap-2">
              <span className="truncate text-[12px] text-muted-foreground">{login}</span>
              <Button variant="ghost" size="compact" leadingIcon={LogOut} onClick={logout}>
                Выйти
              </Button>
            </div>
          </div>
        </SidebarFooter>
      </Sidebar>
      <SidebarInset>
        <div className="flex h-12 items-center gap-2 px-4">
          <SidebarTrigger />
        </div>
        <main className="mx-auto flex w-full max-w-6xl flex-1 flex-col px-4 pb-10 pt-2 md:px-6">
          {page === "overview" && <OverviewPage />}
          {page === "accounts" && <AccountsPage openId={openAccount} onOpen={setOpenAccount} />}
          {page === "audit" && (
            <AuditPage
              onOpenAccount={(id) => {
                setOpenAccount(id);
                setPage("accounts");
              }}
            />
          )}
        </main>
      </SidebarInset>
    </SidebarProvider>
  );
}
