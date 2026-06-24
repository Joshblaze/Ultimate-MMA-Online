import { lazy, Suspense, useMemo, useState, useEffect } from 'react';
import type { ComponentType } from 'react';
import { AuthProvider, useAuth } from './lib/auth';
import { WorldProvider } from './lib/world';
import { GymProvider, useGym } from './lib/gym';
import { AppShell } from './components/AppShell';
import { LoadingScreen } from './components/LoadingScreen';
import { AuthScreen } from './pages/AuthScreen';
import { CreateGymScreen } from './pages/CreateGymScreen';

const ManagePromotion = lazy(() => import('./pages/ManagePromotion').then((m) => ({ default: m.ManagePromotion })));
const Dashboard = lazy(() => import('./pages/Dashboard').then((m) => ({ default: m.Dashboard })));
const MyGym = lazy(() => import('./pages/MyGym').then((m) => ({ default: m.MyGym })));
const MyFighters = lazy(() => import('./pages/MyFighters').then((m) => ({ default: m.MyFighters })));
const FighterProfile = lazy(() => import('./pages/FighterProfile').then((m) => ({ default: m.FighterProfile })));
const Scout = lazy(() => import('./pages/Scout').then((m) => ({ default: m.Scout })));
const FightOffers = lazy(() => import('./pages/FightOffers').then((m) => ({ default: m.FightOffers })));
const Promotions = lazy(() => import('./pages/Promotions').then((m) => ({ default: m.Promotions })));
const PromotionProfile = lazy(() => import('./pages/PromotionProfile').then((m) => ({ default: m.PromotionProfile })));
const Championships = lazy(() => import('./pages/Championships').then((m) => ({ default: m.Championships })));
const Rankings = lazy(() => import('./pages/Rankings').then((m) => ({ default: m.Rankings })));
const Events = lazy(() => import('./pages/Events').then((m) => ({ default: m.Events })));
const FightViewer = lazy(() => import('./pages/FightViewer').then((m) => ({ default: m.FightViewer })));
const WorldNews = lazy(() => import('./pages/WorldNews').then((m) => ({ default: m.WorldNews })));
const Leaderboard = lazy(() => import('./pages/Leaderboard').then((m) => ({ default: m.Leaderboard })));
const AdminPanel = lazy(() => import('./pages/AdminPanel').then((m) => ({ default: m.AdminPanel })));

export interface PageProps {
  params: Record<string, string>;
  navigate: (path: string) => void;
}

interface Route {
  path: string;
  component: ComponentType<PageProps>;
  requiresGym: boolean;
  adminOnly: boolean;
}

const routes: Route[] = [
  { path: 'dashboard', component: Dashboard, requiresGym: true, adminOnly: false },
  { path: 'my-gym', component: MyGym, requiresGym: true, adminOnly: false },
  { path: 'my-fighters', component: MyFighters, requiresGym: true, adminOnly: false },
  { path: 'fighter/:id', component: FighterProfile, requiresGym: true, adminOnly: false },
  { path: 'scout', component: Scout, requiresGym: true, adminOnly: false },
  { path: 'fight-offers', component: FightOffers, requiresGym: true, adminOnly: false },
  { path: 'manage-promotion', component: ManagePromotion, requiresGym: true, adminOnly: false },
  { path: 'promotions', component: Promotions, requiresGym: true, adminOnly: false },
  { path: 'promotion/:id', component: PromotionProfile, requiresGym: true, adminOnly: false },
  { path: 'championships', component: Championships, requiresGym: true, adminOnly: false },
  { path: 'rankings', component: Rankings, requiresGym: true, adminOnly: false },
  { path: 'events', component: Events, requiresGym: true, adminOnly: false },
  { path: 'events/:id', component: EventDetail, requiresGym: true, adminOnly: false },
  { path: 'fight/:id', component: FightViewer, requiresGym: true, adminOnly: false },
  { path: 'world-news', component: WorldNews, requiresGym: true, adminOnly: false },
  { path: 'leaderboard', component: Leaderboard, requiresGym: true, adminOnly: false },
  { path: 'admin', component: AdminPanel, requiresGym: true, adminOnly: true },
];

function matchRoute(route: string): Route | undefined {
  return routes.find((r) => {
    const rParts = r.path.split('/');
    const tParts = route.split('/');
    if (rParts.length !== tParts.length) return false;
    return rParts.every((p, i) => p.startsWith(':') || p === tParts[i]);
  });
}

export function navigate(path: string) {
  window.location.hash = `/${path}`;
}

function getHashRoute(): string {
  const h = window.location.hash.replace(/^#\/?/, '');
  return h || 'dashboard';
}

function AppRoutes() {
  const { user, profile, loading: authLoading } = useAuth();
  const { gym, loading: gymLoading } = useGym();

  const [route, setRoute] = useState(getHashRoute());

  useEffect(() => {
    const onHash = () => setRoute(getHashRoute());
    window.addEventListener('hashchange', onHash);
    return () => window.removeEventListener('hashchange', onHash);
  }, []);

  const matched = matchRoute(route);

  const content = useMemo(() => {
    if (!user) return <AuthScreen />;

    if (!matched) {
      return <Dashboard params={{}} navigate={navigate} />;
    }

    if (matched.adminOnly && !profile?.is_admin) {
      return (
        <div className="flex items-center justify-center min-h-[60vh] text-ink-400">
          Access restricted to administrators.
        </div>
      );
    }

    if (matched.requiresGym && !gym) {
      if (gymLoading) return <LoadingScreen />;
      return <CreateGymScreen />;
    }

    const routeParts = route.split('/');
    const paramParts = matched.path.split('/');
    const params: Record<string, string> = {};
    paramParts.forEach((p, i) => {
      if (p.startsWith(':')) params[p.slice(1)] = routeParts[i];
    });

    const Comp = matched.component;
    return (
      <Suspense fallback={<LoadingScreen />}>
        <Comp params={params} navigate={navigate} />
      </Suspense>
    );
  }, [route, user, profile, matched, gym, gymLoading]);

  if (authLoading) return <LoadingScreen />;
  if (!user) return content;

  return (
    <AppShell currentRoute={route} navigate={navigate}>
      {content}
    </AppShell>
  );
}

export default function App() {
  return (
    <AuthProvider>
      <WorldProvider>
        <GymProvider>
          <AppRoutes />
        </GymProvider>
      </WorldProvider>
    </AuthProvider>
  );
}
