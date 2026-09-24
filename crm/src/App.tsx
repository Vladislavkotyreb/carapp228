import { useEffect, useState } from "react";
import { ClipboardList, LayoutDashboard, Users } from "lucide-react";
import {
  Sidebar,
  SidebarContent,
  SidebarFooter,
  SidebarGroup,
  SidebarGroupLabel,
  SidebarHeader,
  SidebarInset,
  SidebarMenu,
  SidebarMenuBadge,
  SidebarMenuButton,
  SidebarMenuItem,
  SidebarProvider,
  SidebarTrigger,
} from "@/components/ui/sidebar";
import { Switch } from "@/components/ui/switch";
import { StoreProvider, useStore } from "@/data/store";
import { DashboardPage } from "@/pages/Dashboard";
import { EmployeesPage } from "@/pages/Employees";
import { RequestsPage } from "@/pages/Requests";

type Page = "dashboard" | "requests" | "employees";

const THEME_KEY = "beepy-crm-theme";

function readDark(): boolean {
  try {
    return localStorage.getItem(THEME_KEY) !== "light";
  } catch {
    return true;
  }
}

export default function App() {
  return (
    <StoreProvider>
      <Shell />
    </StoreProvider>
  );
}

function Shell() {
  const { state } = useStore();
  const [page, setPage] = useState<Page>("requests");
  const [expanded, setExpanded] = useState("");
  // Тёмная по умолчанию — как само приложение Beepy.
  const [dark, setDark] = useState(readDark);

  useEffect(() => {
    document.documentElement.classList.toggle("dark", dark);
    try {
      localStorage.setItem(THEME_KEY, dark ? "dark" : "light");
    } catch {
      // Без хранилища тема просто не запомнится.
    }
  }, [dark]);

  const fresh = state.requests.filter((r) => r.status === "new").length;

  function openRequest(id: string) {
    setExpanded(id);
    setPage("requests");
  }

  const nav: { id: Page; label: string; icon: typeof LayoutDashboard; badge?: number }[] = [
    { id: "dashboard", label: "Дашборд", icon: LayoutDashboard },
    { id: "requests", label: "Заявки", icon: ClipboardList, badge: fresh || undefined },
    { id: "employees", label: "Сотрудники", icon: Users },
  ];

  return (
    <SidebarProvider>
      <Sidebar variant="inset">
        <SidebarHeader>
          <div className="flex items-center gap-2 px-2 py-1">
            <span className="flex size-6 items-center justify-center rounded-md bg-amber-400 text-[12px] font-bold text-black">
              B
            </span>
            <span className="flex flex-col leading-tight">
              <span className="text-[13px] font-semibold">Beepy для бизнеса</span>
              <span className="text-[11px] text-muted-foreground">Фсервис</span>
            </span>
          </div>
        </SidebarHeader>

        <SidebarContent>
          <SidebarGroup>
            <SidebarGroupLabel>Сервис</SidebarGroupLabel>
            <SidebarMenu>
              {nav.map((item) => (
                <SidebarMenuItem key={item.id}>
                  <SidebarMenuButton icon={item.icon} isActive={page === item.id} onClick={() => setPage(item.id)}>
                    {item.label}
                  </SidebarMenuButton>
                  {item.badge && <SidebarMenuBadge>{item.badge}</SidebarMenuBadge>}
                </SidebarMenuItem>
              ))}
            </SidebarMenu>
          </SidebarGroup>
        </SidebarContent>

        <SidebarFooter>
          <div className="px-2 py-1">
            <Switch label="Тёмная тема" checked={dark} onToggle={() => setDark((d) => !d)} size="compact" />
          </div>
        </SidebarFooter>
      </Sidebar>

      <SidebarInset>
        <div className="flex h-12 items-center gap-2 px-4">
          <SidebarTrigger />
          <span className="text-[12px] text-muted-foreground">Набросок · данные тестовые, хранятся в браузере</span>
        </div>
        <main className="mx-auto flex w-full max-w-6xl flex-1 flex-col px-6 pb-10 pt-2">
          {page === "dashboard" && <DashboardPage onOpenRequest={openRequest} />}
          {page === "requests" && <RequestsPage initiallyOpen={expanded} />}
          {page === "employees" && <EmployeesPage />}
        </main>
      </SidebarInset>
    </SidebarProvider>
  );
}
