import { useState, useEffect } from 'react';
import {
  LayoutDashboard, Dumbbell, Users, Search, FileText, Building2,
  Crown, ListOrdered, CalendarDays, Newspaper, Trophy, Settings,
  LogOut, Menu, X, Clock, Pause, Play,
} from 'lucide-react';
import { useAuth } from '../lib/auth';
import { useGym } from '../lib/gym';
import { useWorld } from '../lib/world';
import { formatCountdown, formatDate, formatMoney } from '../lib/format';

const NAV_ITEMS = [
  { section: 'Management', items: [
    { path: 'dashboard', label: 'Dashboard', icon: LayoutDashboard },
    { path: 'my-gym', label: 'My Gym', icon: Dumbbell },
    { path: 'my-fighters', label: 'My Fighters', icon: Users },
    { path: 'scout', label: 'Scout', icon: Search },
    { path: 'fight-offers', label: 'Fight Offers', icon: FileText },
  ]},
  { section: 'World', items: [
    { path: 'promotions', label: 'Promotions', icon: Building2 },
    { path: 'championships', label: 'Championships', icon: Crown },
    { path: 'rankings', label: 'Rankings', icon: ListOrdered },
    { path: 'events', label: 'Events', icon: CalendarDays },
    { path: 'world-news', label: 'World News', icon: Newspaper },
    { path: 'leaderboard', label: 'Leaderboard', icon: Trophy },
  ]},
];

function getActiveBase(route: string): string {
  const parts = route.split('/');
  return parts[0] || 'dashboard';
}

interface AppShellProps {
  currentRoute: string;
  navigate: (path: string) => void;
  children: React.ReactNode;
}

export function AppShell({ currentRoute, navigate, children }: AppShellProps) {
  const { user, profile, signOut } = useAuth();
  const { gym } = useGym();
  const { world, tickProgress } = useWorld();
  const [mobileOpen, setMobileOpen] = useState(false);

  const activeBase = getActiveBase(currentRoute);

  useEffect(() => {
    setMobileOpen(false);
  }, [currentRoute]);

  const navItems = [
    ...NAV_ITEMS,
    ...(profile?.is_admin
      ? [{ section: 'Admin', items: [{ path: 'admin', label: 'Admin Panel', icon: Settings }] }]
      : []),
  ];

  return (
    <div className="min-h-screen flex">
      {/* Mobile top bar */}
      <div className="lg:hidden fixed top-0 left-0 right-0 z-50 bg-ink-900/95 backdrop-blur border-b border-ink-800 px-4 py-3 flex items-center justify-between">
        <button
          className="p-1.5 rounded-lg hover:bg-ink-800 text-ink-200"
          onClick={() => setMobileOpen((o) => !o)}
          aria-label="Toggle menu"
        >
          {mobileOpen ? <X className="w-5 h-5" /> : <Menu className="w-5 h-5" />}
        </button>
        <BrandMark />
        <div className="w-9" />
      </div>

      {/* Sidebar */}
      <aside
        className={`fixed lg:sticky top-0 left-0 z-40 h-screen w-72 bg-ink-950 border-r border-ink-800 flex flex-col transition-transform duration-200 ${
          mobileOpen ? 'translate-x-0' : '-translate-x-full lg:translate-x-0'
        }`}
      >
        <div className="px-5 py-6 border-b border-ink-800">
          <div className="flex items-center gap-3">
            <div className="relative">
              <div className="absolute inset-0 blur-md bg-gold-600/50 rounded-full" />
              <Trophy className="relative w-8 h-8 text-gold-500" />
            </div>
            <div>
              <div className="font-display font-bold text-ink-100 leading-tight tracking-wide">
                ULTIMATE MMA
              </div>
              <div className="font-display text-gold-500 text-xs tracking-[0.2em] uppercase">
                Manager Online
              </div>
            </div>
          </div>
        </div>

        {/* World clock */}
        <div className="mx-4 mt-4 mb-2">
          {world ? (
            <div className="rounded-lg bg-gradient-to-br from-ink-900 to-ink-850 border border-ink-700/60 p-3">
              <div className="flex items-center gap-2 text-[10px] uppercase tracking-wider text-ink-400">
                {world.is_paused ? (
                  <>
                    <Pause className="w-3 h-3 text-blood-400" /> Simulation Paused
                  </>
                ) : (
                  <>
                    <Play className="w-3 h-3 text-forest-400" /> Simulation Running
                  </>
                )}
              </div>
              <div className="mt-1.5 font-display font-bold text-ink-100 text-sm leading-tight">
                {formatDate(world)}
              </div>
              {!world.is_paused && (
                <div className="mt-2">
                  <div className="flex items-center gap-1 text-[10px] text-ink-400 mb-1">
                    <Clock className="w-3 h-3" />
                    Next week in {formatCountdown(tickProgress.ms)}
                  </div>
                  <div className="h-1 bg-ink-800 rounded-full overflow-hidden">
                    <div
                      className="h-full bg-gold-500 rounded-full transition-all duration-500"
                      style={{ width: `${tickProgress.percentage}%` }}
                    />
                  </div>
                </div>
              )}
            </div>
          ) : (
            <div className="h-24 rounded-lg bg-ink-900 animate-pulse" />
          )}
        </div>

        {/* Navigation */}
        <nav className="flex-1 overflow-y-auto px-3 py-2 space-y-4">
          {navItems.map((group) => (
            <div key={group.section}>
              <div className="px-3 mb-1.5 text-[10px] font-semibold text-ink-500 uppercase tracking-wider">
                {group.section}
              </div>
              <div className="space-y-0.5">
                {group.items.map((item) => {
                  const Icon = item.icon;
                  const isActive = activeBase === getActiveBaseForPath(item.path);
                  return (
                    <button
                      key={item.path}
                      onClick={() => navigate(item.path)}
                      className={`nav-link w-full text-left ${isActive ? 'nav-link-active' : ''}`}
                    >
                      <Icon className="w-4 h-4 flex-shrink-0" />
                      <span>{item.label}</span>
                    </button>
                  );
                })}
              </div>
            </div>
          ))}
        </nav>

        {/* User panel */}
        <div className="border-t border-ink-800 p-3">
          {gym && (
            <button
              onClick={() => navigate('my-gym')}
              className="w-full text-left mb-2 p-2.5 rounded-lg bg-ink-900 hover:bg-ink-850 transition-colors border border-ink-700/40"
            >
              <div className="text-[10px] text-ink-400 uppercase tracking-wide font-semibold">
                {gym.name}
              </div>
              <div className="flex items-center justify-between mt-1">
                <span className="text-xs text-gold-300 font-semibold">
                  Tier {gym.tier}
                </span>
                <span className="text-xs text-ink-200 font-mono">
                  {formatMoney(gym.cash)}
                </span>
              </div>
            </button>
          )}
          <div className="flex items-center gap-3 px-2 py-1.5">
            <div className="w-8 h-8 rounded-full bg-gradient-to-br from-gold-700 to-blood-700 flex items-center justify-center text-ink-100 font-bold text-xs">
              {(user?.email || '?').slice(0, 1).toUpperCase()}
            </div>
            <div className="flex-1 min-w-0">
              <div className="text-xs text-ink-200 truncate font-medium">
                {user?.email}
              </div>
            </div>
            <button
              onClick={signOut}
              className="p-1.5 rounded-lg hover:bg-ink-800 text-ink-400 hover:text-blood-300 transition-colors"
              title="Sign out"
              aria-label="Sign out"
            >
              <LogOut className="w-4 h-4" />
            </button>
          </div>
        </div>
      </aside>

      {/* Backdrop */}
      {mobileOpen && (
        <div
          className="lg:hidden fixed inset-0 z-30 bg-black/60 backdrop-blur-sm"
          onClick={() => setMobileOpen(false)}
        />
      )}

      {/* Main content */}
      <main className="flex-1 min-w-0 pt-14 lg:pt-0">
        <div className="max-w-[1400px] mx-auto p-4 lg:p-8 animate-fadeIn">
          {children}
        </div>
      </main>
    </div>
  );
}

function getActiveBaseForPath(path: string): string {
  return path.split('/')[0];
}

function BrandMark() {
  return (
    <div className="flex items-center gap-2">
      <Trophy className="w-5 h-5 text-gold-500" />
      <span className="font-display font-bold text-ink-100 text-sm tracking-wide">
        ULTIMATE MMA
      </span>
    </div>
  );
}
