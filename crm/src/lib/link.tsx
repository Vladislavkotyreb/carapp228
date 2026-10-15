import { forwardRef, type AnchorHTMLAttributes } from "react";

// Замена `next/link` для Vite: компоненты Fluid Functionalism написаны под
// Next.js, а карточке от ссылки нужен только обычный <a>.
const Link = forwardRef<HTMLAnchorElement, AnchorHTMLAttributes<HTMLAnchorElement> & { href: string }>(
  (props, ref) => <a ref={ref} {...props} />,
);
Link.displayName = "Link";

export default Link;
