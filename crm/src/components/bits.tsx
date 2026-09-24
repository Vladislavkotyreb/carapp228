import type { ReactNode } from "react";
import { Globe, Smartphone } from "lucide-react";
import { Badge } from "@/components/ui/badge";
import { initials } from "@/data/format";
import {
  SOURCE_LABEL,
  STATUS_COLOR,
  STATUS_LABEL,
  type RequestSource,
  type RequestStatus,
} from "@/data/types";

export function StatusBadge({ status }: { status: RequestStatus }) {
  return (
    <Badge variant="dot" color={STATUS_COLOR[status]} size="compact">
      {STATUS_LABEL[status]}
    </Badge>
  );
}

/** Источник — иконкой и словом: у заявки из приложения есть находки,
 *  у заявки с сайта — только слова клиента, и это надо видеть сразу. */
export function SourceBadge({ source, iconOnly = false }: { source: RequestSource; iconOnly?: boolean }) {
  const Icon = source === "app" ? Smartphone : Globe;
  return (
    <span
      className="inline-flex shrink-0 items-center gap-1.5 text-[12px] text-muted-foreground"
      title={iconOnly ? SOURCE_LABEL[source] : undefined}
    >
      <Icon className="size-3.5" aria-hidden />
      <span className={iconOnly ? "sr-only" : undefined}>{SOURCE_LABEL[source]}</span>
    </span>
  );
}

/** Цвет аватара — из имени, как в Jira: у человека один цвет везде, на
 *  карточке и в фильтре, и его узнаёшь раньше, чем прочтёшь инициалы.
 *  Тона тёмные, чтобы белые буквы читались и на светлой теме. */
const AVATAR_TONES = ["#2563eb", "#7c3aed", "#db2777", "#ea580c", "#0d9488", "#4d7c0f", "#0891b2", "#9333ea"];

function avatarColor(name: string): string {
  let hash = 0;
  for (const ch of name) hash = (hash * 37 + ch.charCodeAt(0)) >>> 0;
  return AVATAR_TONES[hash % AVATAR_TONES.length];
}

export function Avatar({ name, muted = false, size = 24 }: { name: string; muted?: boolean; size?: number }) {
  return (
    <span
      className={
        "flex shrink-0 items-center justify-center rounded-full font-semibold " +
        (muted ? "bg-muted text-muted-foreground" : "text-white")
      }
      style={{
        width: size,
        height: size,
        fontSize: Math.round(size * 0.4),
        background: muted ? undefined : avatarColor(name),
      }}
      aria-hidden
    >
      {initials(name)}
    </span>
  );
}

/** Горизонтальная шкала: доля от максимума. Без подписей внутри — число
 *  стоит рядом, шкала только сравнивает. */
export function Meter({ share, tone = "bg-foreground" }: { share: number; tone?: string }) {
  return (
    <span className="block h-1.5 w-full overflow-hidden rounded-full bg-muted">
      <span
        className={`block h-full rounded-full ${tone} transition-[width] duration-500`}
        style={{ width: `${Math.max(0, Math.min(1, share)) * 100}%` }}
      />
    </span>
  );
}

export function PageHeader({ title, subtitle, actions }: { title: string; subtitle?: string; actions?: ReactNode }) {
  return (
    <header className="flex flex-wrap items-end justify-between gap-3">
      <div>
        <h1 className="text-[22px] font-semibold tracking-tight">{title}</h1>
        {subtitle && <p className="mt-0.5 text-[13px] text-muted-foreground">{subtitle}</p>}
      </div>
      {actions && <div className="flex items-center gap-2">{actions}</div>}
    </header>
  );
}

export function SectionTitle({ children }: { children: ReactNode }) {
  return <h2 className="text-[13px] font-medium text-muted-foreground">{children}</h2>;
}
