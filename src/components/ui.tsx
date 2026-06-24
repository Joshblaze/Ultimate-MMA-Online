import type { ReactNode } from 'react';
import { Crown } from 'lucide-react';

export function Card({
  children,
  className = '',
  hover = false,
  variant = 'default',
  onClick,
}: {
  children: ReactNode;
  className?: string;
  hover?: boolean;
  variant?: 'default' | 'glass';
  onClick?: () => void;
}) {
  const base = variant === 'glass' ? 'card-glass' : 'card';
  return (
    <div
      onClick={onClick}
      className={`${base} ${hover ? 'hover:border-white/10 transition-colors cursor-pointer' : ''} ${className}`}
    >
      {children}
    </div>
  );
}

export function CardHeader({
  title,
  subtitle,
  icon: Icon,
  action,
}: {
  title: string;
  subtitle?: string;
  icon?: React.ComponentType<{ className?: string }>;
  action?: ReactNode;
}) {
  return (
    <div className="flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between p-4 border-b border-ink-800/60">
      <div className="flex items-start gap-3 min-w-0">
        {Icon && (
          <div className="w-8 h-8 sm:w-9 sm:h-9 rounded-lg bg-ink-800 flex items-center justify-center flex-shrink-0">
            <Icon className="w-4 h-4 text-gold-400" />
          </div>
        )}
        <div className="min-w-0">
          <h3 className="font-display font-semibold text-ink-100 leading-tight">{title}</h3>
          {subtitle && <p className="text-xs text-ink-400 mt-0.5">{subtitle}</p>}
        </div>
      </div>
      {action && <div className="flex-shrink-0 sm:ml-2">{action}</div>}
    </div>
  );
}

export function StatPanel({
  label,
  value,
  icon: Icon,
  color = 'text-ink-100',
  sub,
}: {
  label: string;
  value: ReactNode;
  icon?: React.ComponentType<{ className?: string }>;
  color?: string;
  sub?: string;
}) {
  return (
    <div className="card p-3 sm:p-4">
      <div className="flex items-center justify-between gap-2">
        <span className="stat-label">{label}</span>
        {Icon && (
          <div className="w-7 h-7 sm:w-8 sm:h-8 rounded-lg bg-ink-800 flex items-center justify-center flex-shrink-0">
            <Icon className={`w-3.5 h-3.5 sm:w-4 sm:h-4 ${color}`} />
          </div>
        )}
      </div>
      <div className={`stat-value mt-1.5 sm:mt-2 font-display ${color}`}>{value}</div>
      {sub && <div className="text-xs text-ink-400 mt-1">{sub}</div>}
    </div>
  );
}

export function Badge({
  children,
  className = '',
}: {
  children: ReactNode;
  className?: string;
}) {
  return (
    <span className={`badge border ${className}`}>
      {children}
    </span>
  );
}

export function EmptyState({
  icon: Icon,
  title,
  body,
  action,
}: {
  icon: React.ComponentType<{ className?: string }>;
  title: string;
  body?: string;
  action?: ReactNode;
}) {
  return (
    <div className="flex flex-col items-center justify-center text-center py-12 px-6">
      <div className="w-14 h-14 rounded-full bg-ink-800 flex items-center justify-center mb-4">
        <Icon className="w-6 h-6 text-ink-500" />
      </div>
      <h3 className="font-display font-semibold text-ink-200 mb-1">{title}</h3>
      {body && <p className="text-sm text-ink-400 max-w-sm">{body}</p>}
      {action && <div className="mt-4">{action}</div>}
    </div>
  );
}

export function FighterStatBar({
  label,
  value,
  max = 100,
}: {
  label: string;
  value: number;
  max?: number;
}) {
  const pct = Math.min(100, (value / max) * 100);
  const color =
    value >= 85 ? '#e0b62e' : value >= 70 ? '#2b9d56' : value >= 55 ? '#5b86d6' : '#7a8599';

  return (
    <div className="flex items-center gap-3">
      <span className="text-xs text-ink-400 w-24 flex-shrink-0">{label}</span>
      <div className="flex-1 h-2 rounded-full bg-ink-900 overflow-hidden">
        <div
          className="h-full rounded-full transition-all duration-500"
          style={{ width: `${pct}%`, backgroundColor: color }}
        />
      </div>
      <span className="text-xs font-mono font-semibold text-ink-200 w-8 text-right">
        {value}
      </span>
    </div>
  );
}

export function Avatar({
  name,
  size = 'md',
  className = '',
}: {
  name: string;
  size?: 'sm' | 'md' | 'lg';
  className?: string;
}) {
  const parts = name.trim().split(/\s+/);
  const initials = parts.length >= 2
    ? (parts[0][0] + parts[parts.length - 1][0]).toUpperCase()
    : name.slice(0, 2).toUpperCase();
  const sizes = {
    sm: 'w-8 h-8 text-xs',
    md: 'w-10 h-10 text-sm',
    lg: 'w-14 h-14 text-base',
  };
  return (
    <div
      className={`rounded-full bg-gradient-to-br from-ink-700 to-ink-800 flex items-center justify-center font-bold text-ink-100 ${sizes[size]} ${className}`}
    >
      {initials}
    </div>
  );
}

export function Belt({
  size = 'md',
  className = '',
  glowing = false,
}: {
  size?: 'sm' | 'md' | 'lg';
  className?: string;
  glowing?: boolean;
}) {
  const sizes = {
    sm: 'w-6 h-6',
    md: 'w-8 h-8',
    lg: 'w-12 h-12',
  };
  return (
    <div className={`relative ${className}`}>
      {glowing && (
        <div className="absolute inset-0 blur-md bg-gold-500/50 rounded-full animate-pulse" />
      )}
      <div
        className={`relative ${sizes[size]} rounded-md bg-gradient-to-b from-gold-300 via-gold-500 to-gold-700 border border-gold-200 flex items-center justify-center shadow-belt`}
      >
        <Crown className="text-ink-900 w-1/2 h-1/2" />
      </div>
    </div>
  );
}

export function PageHeader({
  title,
  subtitle,
  icon: Icon,
  action,
}: {
  title: string;
  subtitle?: string;
  icon?: React.ComponentType<{ className?: string }>;
  action?: ReactNode;
}) {
  return (
    <div className="flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between mb-5 sm:mb-6 animate-slideUp">
      <div className="flex items-start gap-3 min-w-0">
        {Icon && (
          <div className="w-9 h-9 sm:w-11 sm:h-11 rounded-xl bg-gradient-to-br from-ink-800 to-ink-850 border border-white/[0.06] flex items-center justify-center flex-shrink-0">
            <Icon className="w-4 h-4 sm:w-5 sm:h-5 text-gold-400" />
          </div>
        )}
        <div className="min-w-0">
          <h1 className="font-display text-xl sm:text-2xl font-bold text-ink-100 tracking-tight leading-tight">
            {title}
          </h1>
          {subtitle && <p className="text-xs sm:text-sm text-ink-400 mt-0.5">{subtitle}</p>}
        </div>
      </div>
      {action && <div className="flex-shrink-0">{action}</div>}
    </div>
  );
}

export function Alert({
  variant = 'info',
  title,
  children,
}: {
  variant?: 'info' | 'success' | 'warning' | 'error';
  title?: string;
  children?: ReactNode;
}) {
  const variants = {
    info: 'bg-ink-800 border-ink-700 text-ink-200',
    success: 'bg-forest-950 border-forest-700 text-forest-200',
    warning: 'bg-gold-950 border-gold-700 text-gold-200',
    error: 'bg-blood-950 border-blood-700 text-blood-200',
  };
  return (
    <div className={`rounded-lg border p-3 ${variants[variant]}`}>
      {title && <div className="font-semibold text-sm mb-1">{title}</div>}
      {children && <div className="text-sm">{children}</div>}
    </div>
  );
}

export function Spinner({ className = 'w-4 h-4' }: { className?: string }) {
  return (
    <svg className={`animate-spin ${className}`} viewBox="0 0 24 24" fill="none">
      <circle className="opacity-25" cx="12" cy="12" r="10" stroke="currentColor" strokeWidth="4" />
      <path className="opacity-75" fill="currentColor" d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4z" />
    </svg>
  );
}
