import { useEffect, useLayoutEffect, useRef } from "react";
import { emptyScan, feedScan, type ScanBuffer } from "@/data/inventory";

/** Ловит поток USB-/Bluetooth-сканера на всей странице: сканер печатает как
 *  клавиатура, но быстрее человека (разбор — `feedScan`). Если фокус в поле
 *  ввода, код туда уже напечатан — поле обработает Enter само, здесь
 *  пропускаем, чтобы скан не сработал дважды. */
export function useBarcodeScanner(onScan: (code: string) => void, enabled = true) {
  const buffer = useRef<ScanBuffer>(emptyScan);
  const handler = useRef(onScan);
  // Свежий обработчик — после рендера, не во время: подписка на клавиатуру
  // одна на всё время жизни, а замыкание внутри неё должно видеть новое.
  useLayoutEffect(() => {
    handler.current = onScan;
  });

  useEffect(() => {
    if (!enabled) return;
    function onKey(e: KeyboardEvent) {
      if (e.metaKey || e.ctrlKey || e.altKey) return;
      const t = e.target as HTMLElement | null;
      if (t && (t.tagName === "INPUT" || t.tagName === "TEXTAREA" || t.isContentEditable)) {
        buffer.current = emptyScan;
        return;
      }
      const r = feedScan(buffer.current, e.key, e.timeStamp);
      buffer.current = r.buffer;
      if (r.code) {
        e.preventDefault();
        handler.current(r.code);
      }
    }
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [enabled]);
}
