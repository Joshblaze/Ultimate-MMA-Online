import { MONTH_NAMES, WEEK_DURATION_MS, WEEKS_PER_MONTH, WEEKS_PER_YEAR } from './constants';
import type { WorldState } from './types';

export interface CalendarDate {
  year: number;
  month: number;
  week: number;
}

export function tickToCalendar(tick: number): CalendarDate {
  return {
    year: Math.floor(tick / WEEKS_PER_YEAR) + 1,
    month: Math.floor((tick % WEEKS_PER_YEAR) / WEEKS_PER_MONTH) + 1,
    week: (tick % WEEKS_PER_MONTH) + 1,
  };
}

export function formatMoney(n: number): string {
  if (n >= 1_000_000) return `$${(n / 1_000_000).toFixed(2)}M`;
  if (n >= 1_000) return `$${(n / 1_000).toFixed(1)}K`;
  return `$${n.toLocaleString()}`;
}

export function formatNumber(n: number): string {
  return n.toLocaleString('en-US');
}

export function formatDate(world: Pick<WorldState, 'current_year' | 'current_week' | 'current_month'>): string {
  return formatTickFromCalendar({
    year: world.current_year,
    month: world.current_month,
    week: world.current_week,
  });
}

function formatTickFromCalendar({ year, month, week }: CalendarDate): string {
  const monthName = MONTH_NAMES[(month - 1) % 12];
  return `${monthName} Week ${week}, Year ${year}`;
}

export function formatTick(tick: number): string {
  return formatTickFromCalendar(tickToCalendar(tick));
}

export function formatTickRange(startTick: number, endTick: number): string {
  return `${formatTick(startTick)} – ${formatTick(endTick)}`;
}

export function formatRecord(w: number, l: number, d: number = 0): string {
  return `${w}-${l}-${d}`;
}

export function classForSkill(value: number): string {
  if (value >= 90) return 'text-gold-300';
  if (value >= 80) return 'text-forest-300';
  if (value >= 70) return 'text-blue-300';
  if (value >= 60) return 'text-ink-200';
  return 'text-ink-400';
}

export function ratingTier(rating: number): { label: string; color: string } {
  if (rating >= 90) return { label: 'Elite', color: 'text-gold-300' };
  if (rating >= 80) return { label: 'Star', color: 'text-forest-300' };
  if (rating >= 70) return { label: 'Contender', color: 'text-blue-300' };
  if (rating >= 60) return { label: 'Solid', color: 'text-ink-200' };
  if (rating >= 50) return { label: 'Average', color: 'text-ink-300' };
  return { label: 'Rookie', color: 'text-ink-400' };
}

export function timeUntilNextTick(lastTickAt: string | null): { ms: number; percentage: number } {
  if (!lastTickAt) return { ms: 0, percentage: 0 };
  const last = new Date(lastTickAt).getTime();
  const now = Date.now();
  const elapsed = now - last;
  const duration = WEEK_DURATION_MS;
  const ms = Math.max(0, duration - elapsed);
  const percentage = Math.min(100, (elapsed / duration) * 100);
  return { ms, percentage };
}

export function formatCountdown(ms: number): string {
  if (ms <= 0) return 'imminent';
  const minutes = Math.floor(ms / 60000);
  const seconds = Math.floor((ms % 60000) / 1000);
  if (minutes > 0) return `${minutes}m ${seconds}s`;
  return `${seconds}s`;
}

export function initials(name: string): string {
  const parts = name.trim().split(/\s+/);
  if (parts.length === 1) return parts[0].slice(0, 2).toUpperCase();
  return (parts[0][0] + parts[parts.length - 1][0]).toUpperCase();
}
