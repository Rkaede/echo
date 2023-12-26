import { ReactNode } from 'react';

export function SettingTitle({ children }: { children: ReactNode }) {
  return (
    <div className="mb-2">
      <h3 className="text-lg font-medium">{children}</h3>
    </div>
  );
}
