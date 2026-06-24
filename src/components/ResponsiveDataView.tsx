import type { ReactNode } from 'react';

interface ResponsiveDataViewProps {
  /** Table or desktop-only content */
  children: ReactNode;
  /** Card/list rows shown below md breakpoint */
  mobileRows: ReactNode;
  className?: string;
}

export function ResponsiveDataView({ children, mobileRows, className = '' }: ResponsiveDataViewProps) {
  return (
    <div className={className}>
      <div className="hidden md:block">{children}</div>
      <div className="md:hidden space-y-2 p-3">{mobileRows}</div>
    </div>
  );
}
