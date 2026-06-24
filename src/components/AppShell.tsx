import { useState, useEffect, useRef, useCallback, forwardRef, type ComponentType } from 'react';
import {
  LayoutDashboard, Dumbbell, Users, Search, FileText, Building2,
  Crown, ListOrdered, CalendarDays, Newspaper, Trophy, Settings,
  LogOut, Menu, X, Clock, Pause, Play, Briefcase, MoreHorizontal,
} from 'lucide-react';
import { fetchOwnedPromotion } from '../lib/queries';
import type { Promotion } from '../lib/types';
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

const BOTTOM_TABS = [
  { path: 'dashboard', label: 'Home', icon: LayoutDashboard, tabKey: 'dashboard' },
  { path: 'my-fighters', label: 'Fighters', icon: Users, tabKey: 'my-fighters' },
  { path: 'fight-offers', label: 'Offers', icon: FileText, tabKey: 'fight-offers' },
  { path: 'events', label: 'Events', icon: CalendarDays, tabKey: 'events' },
] as const;

/** Routes that highlight the Fighters bottom tab */
const FIGHTERS_TAB_ROUTES = new Set(['my-fighters', 'fighter', 'scout']);

/** Routes that highlight the Events bottom tab */
const EVENTS_TAB_ROUTES = new Set(['events', 'event']);

function getActiveBase(route: string): string {
  const parts = route.split('/');
  return parts[0] || 'dashboard';
}

function getActiveBaseForPath(path: string): string {
  return path.split('/')[0];
}

function getBottomTabKey(route: string): string | null {
  const base = getActiveBase(route);
  if (base === 'dashboard') return 'dashboard';
  if (FIGHTERS_TAB_ROUTES.has(base)) return 'my-fighters';
  if (base === 'fight-offers') return 'fight-offers';
  if (EVENTS_TAB_ROUTES.has(base)) return 'events';
  return null;
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
  const [drawerOpen, setDrawerOpen] = useState(false);
  const [ownedPromotion, setOwnedPromotion] = useState<Promotion | null>(null);
  const drawerRef = useRef<HTMLElement>(null);
  const menuButtonRef = useRef<HTMLButtonElement>(null);

  const activeBase = getActiveBase(currentRoute);
  const activeBottomTab = getBottomTabKey(currentRoute);

  useEffect(() => {
    if (!gym) {
      setOwnedPromotion(null);
      return;
    }
    fetchOwnedPromotion(gym.id)
      .then(setOwnedPromotion)
      .catch(() => setOwnedPromotion(null));
  }, [gym?.id, world?.tick_count]);

  useEffect(() => {
    setDrawerOpen(false);
  }, [currentRoute]);

  const closeDrawer = useCallback(() => {
    setDrawerOpen(false);
    menuButtonRef.current?.focus();
  }, []);

  const openDrawer = useCallback(() => {
    setDrawerOpen(true);
  }, []);

  useEffect(() => {
    if (!drawerOpen) return;

    function onKeyDown(e: KeyboardEvent) {
      if (e.key === 'Escape') closeDrawer();
    }

    document.addEventListener('keydown', onKeyDown);
    return () => document.removeEventListener('keydown', onKeyDown);
  }, [drawerOpen, closeDrawer]);

  useEffect(() => {
    if (!drawerOpen || !drawerRef.current) return;

    const drawer = drawerRef.current;
    const focusable = drawer.querySelectorAll<HTMLElement>(
      'button, [href], input, select, textarea, [tabindex]:not([tabindex="-1"])'
    );
    const first = focusable[0];
    const last = focusable[focusable.length - 1];
    first?.focus();

    function trapFocus(e: KeyboardEvent) {
      if (e.key !== 'Tab' || focusable.length === 0) return;
      if (e.shiftKey) {
        if (document.activeElement === first) {
          e.preventDefault();
          last?.focus();
        }
      } else if (document.activeElement === last) {
        e.preventDefault();
        first?.focus();
      }
    }

    document.addEventListener('keydown', trapFocus);
    return () => document.removeEventListener('keydown', trapFocus);
  }, [drawerOpen]);

  const navItems = [
    ...NAV_ITEMS.map((group) => {
      if (group.section !== 'Management') return group;
      const items = [...group.items];
      if (ownedPromotion) {
        items.push({ path: 'manage-promotion', label: 'Manage Promotion', icon: Briefcase });
      }
      return { ...group, items };
    }),
    ...(profile?.is_admin
      ? [{ section: 'Admin', items: [{ path: 'admin', label: 'Admin Panel', icon: Settings }] }]
      : []),
  ];

  return (
    <div className="min-h-screen flex">
      <MobileTopBar
        gym={gym}
        world={world}
        drawerOpen={drawerOpen}
        onToggleDrawer={() => setDrawerOpen((o) => !o)}
        menuButtonRef={menuButtonRef}
      />

      <NavDrawer
        ref={drawerRef}
        open={drawerOpen}
        navItems={navItems}
        activeBase={activeBase}
        navigate={navigate}
        world={world}
        tickProgress={tickProgress}
        gym={gym}
        user={user}
        signOut={signOut}
        onClose={closeDrawer}
        isMobileOnly={true}
      />

      <NavDrawer
        open={true}
        navItems={navItems}
        activeBase={activeBase}
        navigate={navigate}
        world={world}
        tickProgress={tickProgress}
        gym={gym}
        user={user}
        signOut={signOut}
        onClose={() => {}}
        isMobileOnly={false}
      />

      {drawerOpen && (
        <div
          className="lg:hidden fixed inset-0 z-30 bg-black/60 backdrop-blur-sm motion-reduce:backdrop-blur-none"
          onClick={closeDrawer}
          aria-hidden="true"
        />
      )}

      <main className="flex-1 min-w-0 pt-shell-top pb-shell-bottom lg:pt-0 lg:pb-0">
        <div className="max-w-[1400px] mx-auto p-4 sm:p-6 lg:p-8 animate-fadeIn motion-reduce:animate-none">
          {children}
        </div>
      </main>

      <BottomTabBar
        activeBottomTab={activeBottomTab}
        drawerOpen={drawerOpen}
        onNavigate={navigate}
        onOpenDrawer={openDrawer}
      />
    </div>
  );
}

function MobileTopBar({
  gym,
  world,
  drawerOpen,
  onToggleDrawer,
  menuButtonRef,
}: {
  gym: ReturnType<typeof useGym>['gym'];
  world: ReturnType<typeof useWorld>['world'];
  drawerOpen: boolean;
  onToggleDrawer: () => void;
  menuButtonRef: React.RefObject<HTMLButtonElement>;
}) {
  return (
    <header className="lg:hidden fixed top-0 left-0 right-0 z-50 glass-bar border-b pt-safe">
      <div className="px-3 h-14 flex items-center gap-2">
        <button
          ref={menuButtonRef}
          className="min-w-11 min-h-11 flex items-center justify-center rounded-lg hover:bg-ink-800/80 text-ink-200 focus:outline-none focus-visible:ring-2 focus-visible:ring-gold-500/50"
          onClick={onToggleDrawer}
          aria-label={drawerOpen ? 'Close menu' : 'Open menu'}
          aria-expanded={drawerOpen}
          aria-controls="mobile-nav-drawer"
        >
          {drawerOpen ? <X className="w-5 h-5" /> : <Menu className="w-5 h-5" />}
        </button>

        <div className="flex-1 min-w-0">
          {gym ? (
            <div className="min-w-0">
              <div className="font-display font-semibold text-sm text-ink-100 truncate leading-tight">
                {gym.name}
              </div>
              {world && (
                <div className="text-[10px] text-ink-400 truncate">{formatDate(world)}</div>
              )}
            </div>
          ) : (
            <BrandMark compact />
          )}
        </div>

        {gym && (
          <div className="flex-shrink-0 px-2.5 py-1 rounded-full bg-gold-700/20 border border-gold-600/30">
            <span className="text-xs font-mono font-semibold text-gold-300">
              {formatMoney(gym.cash)}
            </span>
          </div>
        )}
      </div>
    </header>
  );
}

function BottomTabBar({
  activeBottomTab,
  drawerOpen,
  onNavigate,
  onOpenDrawer,
}: {
  activeBottomTab: string | null;
  drawerOpen: boolean;
  onNavigate: (path: string) => void;
  onOpenDrawer: () => void;
}) {
  return (
    <nav
      className="lg:hidden fixed bottom-0 left-0 right-0 z-50 glass-bar border-t shadow-glass-bar pb-safe"
      aria-label="Main navigation"
    >
      <div className="flex items-stretch h-[3.75rem] px-1">
        {BOTTOM_TABS.map((tab) => {
          const Icon = tab.icon;
          const isActive = activeBottomTab === tab.tabKey;
          return (
            <button
              key={tab.path}
              onClick={() => onNavigate(tab.path)}
              className={`bottom-nav-item relative ${isActive ? 'bottom-nav-item-active' : ''}`}
              aria-current={isActive ? 'page' : undefined}
            >
              {isActive && (
                <span className="absolute top-0 left-1/2 -translate-x-1/2 w-8 h-0.5 bg-gold-500 rounded-full" />
              )}
              <Icon className={`w-5 h-5 ${isActive ? 'text-gold-400' : 'text-ink-400'}`} />
              <span>{tab.label}</span>
            </button>
          );
        })}
        <button
          onClick={onOpenDrawer}
          className={`bottom-nav-item relative ${drawerOpen || activeBottomTab === null ? 'bottom-nav-item-active' : ''}`}
          aria-current={drawerOpen ? 'true' : undefined}
          aria-expanded={drawerOpen}
          aria-controls="mobile-nav-drawer"
        >
          {(drawerOpen || activeBottomTab === null) && (
            <span className="absolute top-0 left-1/2 -translate-x-1/2 w-8 h-0.5 bg-gold-500 rounded-full" />
          )}
          <MoreHorizontal className={`w-5 h-5 ${drawerOpen || activeBottomTab === null ? 'text-gold-400' : 'text-ink-400'}`} />
          <span>More</span>
        </button>
      </div>
    </nav>
  );
}

interface NavDrawerProps {
  open: boolean;
  navItems: Array<{
    section: string;
    items: Array<{ path: string; label: string; icon: ComponentType<{ className?: string }> }>;
  }>;
  activeBase: string;
  navigate: (path: string) => void;
  world: ReturnType<typeof useWorld>['world'];
  tickProgress: ReturnType<typeof useWorld>['tickProgress'];
  gym: ReturnType<typeof useGym>['gym'];
  user: ReturnType<typeof useAuth>['user'];
  signOut: () => void;
  onClose: () => void;
  isMobileOnly: boolean;
}

const NavDrawer = forwardRef<HTMLElement, NavDrawerProps>(function NavDrawer(
  {
    open,
    navItems,
    activeBase,
    navigate,
    world,
    tickProgress,
    gym,
    user,
    signOut,
    onClose,
    isMobileOnly,
  },
  ref,
) {
  const mobileClasses = isMobileOnly
    ? `fixed top-0 left-0 z-40 h-screen w-[min(20rem,85vw)] transition-transform duration-200 motion-reduce:transition-none ${
        open ? 'translate-x-0' : '-translate-x-full'
      } lg:hidden`
    : 'hidden lg:flex lg:sticky lg:translate-x-0 lg:w-64';

  return (
    <aside
      ref={ref}
      id={isMobileOnly ? 'mobile-nav-drawer' : undefined}
      role={isMobileOnly ? 'dialog' : undefined}
      aria-modal={isMobileOnly ? open : undefined}
      aria-label={isMobileOnly ? 'Navigation menu' : undefined}
      aria-hidden={isMobileOnly ? !open : undefined}
      className={`${mobileClasses} top-0 bg-ink-950/95 backdrop-blur-xl border-r border-white/[0.06] flex-col`}
    >
      <div className="px-4 py-5 border-b border-white/[0.06] flex-shrink-0">
        <div className="flex items-center gap-3">
          <div className="relative">
            <div className="absolute inset-0 blur-md bg-gold-600/40 rounded-full" />
            <Trophy className="relative w-7 h-7 text-gold-500" />
          </div>
          <div>
            <div className="font-display font-bold text-ink-100 leading-tight tracking-wide text-sm">
              ULTIMATE MMA
            </div>
            <div className="font-display text-gold-500 text-[10px] tracking-[0.2em] uppercase">
              Manager Online
            </div>
          </div>
          {isMobileOnly && (
            <button
              onClick={onClose}
              className="ml-auto min-w-11 min-h-11 flex items-center justify-center rounded-lg hover:bg-ink-800 text-ink-400 lg:hidden"
              aria-label="Close menu"
            >
              <X className="w-5 h-5" />
            </button>
          )}
        </div>
      </div>

      <WorldClock world={world} tickProgress={tickProgress} compact={isMobileOnly} />

      <nav className="flex-1 overflow-y-auto px-2 py-2 space-y-4" aria-label="Site navigation">
        {navItems.map((group) => (
          <div key={group.section}>
            <div className="px-3 mb-1 text-[10px] font-semibold text-ink-500 uppercase tracking-wider">
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
                    aria-current={isActive ? 'page' : undefined}
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

      <div className="border-t border-white/[0.06] p-3 flex-shrink-0">
        {gym && (
          <button
            onClick={() => navigate('my-gym')}
            className="w-full text-left mb-2 p-2.5 rounded-lg bg-ink-900/80 hover:bg-ink-850 transition-colors border border-white/[0.06] min-h-11"
          >
            <div className="text-[10px] text-ink-400 uppercase tracking-wide font-semibold truncate">
              {gym.name}
            </div>
            <div className="flex items-center justify-between mt-1">
              <span className="text-xs text-gold-300 font-semibold">Tier {gym.tier}</span>
              <span className="text-xs text-ink-200 font-mono">{formatMoney(gym.cash)}</span>
            </div>
          </button>
        )}
        <div className="flex items-center gap-3 px-1 py-1">
          <div className="w-9 h-9 rounded-full bg-gradient-to-br from-gold-700 to-blood-700 flex items-center justify-center text-ink-100 font-bold text-xs flex-shrink-0">
            {(user?.email || '?').slice(0, 1).toUpperCase()}
          </div>
          <div className="flex-1 min-w-0">
            <div className="text-xs text-ink-200 truncate font-medium">{user?.email}</div>
          </div>
          <button
            onClick={signOut}
            className="min-w-11 min-h-11 flex items-center justify-center rounded-lg hover:bg-ink-800 text-ink-400 hover:text-blood-300 transition-colors"
            title="Sign out"
            aria-label="Sign out"
          >
            <LogOut className="w-4 h-4" />
          </button>
        </div>
      </div>
    </aside>
  );
});

function WorldClock({
  world,
  tickProgress,
  compact,
}: {
  world: ReturnType<typeof useWorld>['world'];
  tickProgress: ReturnType<typeof useWorld>['tickProgress'];
  compact?: boolean;
}) {
  if (!world) {
    return <div className="mx-3 mt-3 h-16 rounded-lg bg-ink-900 animate-pulse" />;
  }

  if (compact) {
    return (
      <div className="mx-3 mt-3 mb-1 flex-shrink-0">
        <div className="rounded-lg bg-ink-900/80 border border-white/[0.06] px-3 py-2 flex items-center justify-between gap-2">
          <div className="flex items-center gap-2 min-w-0">
            {world.is_paused ? (
              <Pause className="w-3 h-3 text-blood-400 flex-shrink-0" />
            ) : (
              <Play className="w-3 h-3 text-forest-400 flex-shrink-0" />
            )}
            <span className="font-display font-semibold text-xs text-ink-100 truncate">
              {formatDate(world)}
            </span>
          </div>
          {!world.is_paused && (
            <span className="text-[10px] text-ink-400 flex-shrink-0 font-mono">
              {formatCountdown(tickProgress.ms)}
            </span>
          )}
        </div>
      </div>
    );
  }

  return (
    <div className="mx-3 mt-3 mb-1 flex-shrink-0">
      <div className="rounded-lg bg-gradient-to-br from-ink-900/90 to-ink-850/90 border border-white/[0.06] p-3">
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
                className="h-full bg-gold-500 rounded-full transition-all duration-500 motion-reduce:transition-none"
                style={{ width: `${tickProgress.percentage}%` }}
              />
            </div>
          </div>
        )}
      </div>
    </div>
  );
}

function BrandMark({ compact = false }: { compact?: boolean }) {
  return (
    <div className="flex items-center gap-2">
      <Trophy className={`${compact ? 'w-4 h-4' : 'w-5 h-5'} text-gold-500`} />
      <span className={`font-display font-bold text-ink-100 tracking-wide ${compact ? 'text-xs' : 'text-sm'}`}>
        ULTIMATE MMA
      </span>
    </div>
  );
}
