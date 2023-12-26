import { ReactNode } from 'react';

export function Title({ children }: { children: ReactNode }) {
  return <h2 className="font-semibold text-lg mb-3">{children}</h2>;
}
