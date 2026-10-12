import { useEffect, useMemo, useState } from "react";
import {
  ArrowDownToLine,
  ClipboardList,
  LayoutDashboard,
  Moon,
  Package,
  Search,
  Sun,
  Users,
  Wrench,
} from "lucide-react";
import {
  CommandMenu,
  CommandMenuDialog,
  CommandMenuEmpty,
  CommandMenuInput,
  CommandMenuList,
  type CommandMenuItemData,
} from "@/components/ui/command-menu";
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
import { StockPage } from "@/pages/Stock";
import { isLow, stockLevels } from "@/data/inventory";
import { qty } from "@/data/format";
import { UNIT_LABEL } from "@/data/types";

type Page = "dashboard" | "requests" | "stock" | "employees";

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
  const [palette, setPalette] = useState(false);
  const [focusItem, setFocusItem] = useState<string | undefined>();

  useEffect(() => {
    document.documentElement.classList.toggle("dark", dark);
    try {
      localStorage.setItem(THEME_KEY, dark ? "dark" : "light");
    } catch {
      // Без хранилища тема просто не запомнится.
    }
  }, [dark]);

  const fresh = state.requests.filter((r) => r.status === "new").length;
  const levels = useMemo(() => stockLevels(state.moves), [state.moves]);
  const low = state.stock.filter((i) => isLow(i, levels.get(i.id) ?? 0)).length;

  function openRequest(id: string) {
    setExpanded(id);
    setPage("requests");
  }


  const nav: { id: Page; label: string; icon: typeof LayoutDashboard; badge?: number }[] = [
    { id: "dashboard", label: "Дашборд", icon: LayoutDashboard },
    { id: "requests", label: "Заявки", icon: ClipboardList, badge: fresh || undefined },
    { id: "stock", label: "Склад", icon: Package, badge: low || undefined },
    { id: "employees", label: "Сотрудники", icon: Users },
  ];

  // Палитра ⌘K — главный вход с клавиатуры, как в Linear: разделы, действия,
  // заявка по номеру или клиенту, позиция склада по названию или артикулу.
  const commands = useMemo<CommandMenuItemData[]>(() => {
    const go = (p: Page) => () => {
      setPage(p);
      setFocusItem(undefined);
    };
    return [
      { value: "go-dashboard", label: "Дашборд", icon: LayoutDashboard, group: "Разделы", onSelect: go("dashboard") },
      { value: "go-requests", label: "Заявки", icon: ClipboardList, group: "Разделы", onSelect: go("requests") },
      { value: "go-stock", label: "Склад", icon: Package, group: "Разделы", onSelect: go("stock") },
      { value: "go-employees", label: "Сотрудники", icon: Users, group: "Разделы", onSelect: go("employees") },
      {
        value: "act-receive",
        label: "Приход на склад",
        description: "Отсканируйте упаковку",
        icon: ArrowDownToLine,
        group: "Действия",
        keywords: ["скан", "штрихкод", "оприходовать"],
        onSelect: go("stock"),
      },
      {
        value: "act-theme",
        label: dark ? "Светлая тема" : "Тёмная тема",
        icon: dark ? Sun : Moon,
        group: "Действия",
        onSelect: () => setDark((d) => !d),
      },
      ...state.requests.map(
        (r): CommandMenuItemData => ({
          value: `req-${r.id}`,
          label: `№${r.number} · ${r.client.name} · ${r.car.name}`,
          description: r.summary,
          icon: Wrench,
          group: "Заявки",
          keywords: [String(r.number), r.car.plate ?? ""],
          onSelect: () => openRequest(r.id),
        }),
      ),
      ...state.stock.map(
        (i): CommandMenuItemData => ({
          value: `stock-${i.id}`,
          label: i.name,
          description: `${i.sku} · ${qty(levels.get(i.id) ?? 0, UNIT_LABEL[i.unit])}`,
          icon: Package,
          group: "Склад",
          keywords: [i.sku, ...i.barcodes],
          onSelect: () => {
            setPage("stock");
            setFocusItem(i.id);
          },
        }),
      ),
    ];
    // openRequest стабилен по смыслу: только сеттеры.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [state.requests, state.stock, levels, dark]);

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
          <button
            type="button"
            onClick={() => setPalette(true)}
            className="ml-auto flex h-7 items-center gap-2 rounded-md border border-border px-2.5 text-[12px] text-muted-foreground transition-colors hover:bg-hover hover:text-foreground"
          >
            <Search className="size-3.5" aria-hidden />
            Поиск и команды
            <kbd className="rounded border border-border px-1 font-sans text-[11px]">⌘K</kbd>
          </button>
        </div>
        <main className="mx-auto flex w-full max-w-6xl flex-1 flex-col px-4 pb-10 pt-2 md:px-6">
          {page === "dashboard" && <DashboardPage onOpenRequest={openRequest} />}
          {page === "requests" && <RequestsPage initiallyOpen={expanded} />}
          {page === "stock" && <StockPage focusItemId={focusItem} />}
          {page === "employees" && <EmployeesPage />}
        </main>
        <CommandMenuDialog open={palette} onOpenChange={setPalette} title="Поиск и команды">
          <CommandMenu items={commands}>
            <CommandMenuInput placeholder="Раздел, заявка №, клиент, запчасть или артикул…" />
            <CommandMenuList />
            <CommandMenuEmpty>Ничего не нашли</CommandMenuEmpty>
          </CommandMenu>
        </CommandMenuDialog>
      </SidebarInset>
    </SidebarProvider>
  );
}
