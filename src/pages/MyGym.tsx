import { Dumbbell, Trophy, Users, Crown, Wallet, TrendingUp, Swords, Wrench } from 'lucide-react';
import { useGym } from '../lib/gym';
import { useWorld } from '../lib/world';
import type { PageProps } from '../App';
import { Card, CardHeader, PageHeader, StatPanel } from '../components/ui';
import { formatMoney, formatRecord, formatDate } from '../lib/format';
import { navigate } from '../App';

export function MyGym(_: PageProps) {
  const { gym } = useGym();
  const { world } = useWorld();

  if (!gym) return null;
  const capacityPct = Math.min(100, (10 / gym.capacity) * 100); // placeholder; real usage computed on My Fighters

  return (
    <div className="animate-slideUp">
      <PageHeader
        title={gym.name}
        subtitle="Your MMA gym"
        icon={Dumbbell}
      />

      <div className="grid grid-cols-2 md:grid-cols-3 lg:grid-cols-6 gap-3 mb-6">
        <StatPanel label="Tier" value={gym.tier} icon={Trophy} color="text-gold-300" />
        <StatPanel label="Reputation" value={gym.reputation} icon={TrendingUp} color="text-forest-300" />
        <StatPanel label="Ranking" value={gym.ranking ? `#${gym.ranking}` : '—'} icon={Trophy} color="text-gold-300" />
        <StatPanel label="Cash" value={formatMoney(gym.cash)} icon={Wallet} color="text-gold-300" />
        <StatPanel label="Champions" value={gym.champions_produced} icon={Crown} color="text-gold-300" />
        <StatPanel label="Record" value={formatRecord(gym.wins, gym.losses, gym.draws)} icon={Swords} color="text-ink-100" />
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
        <div className="lg:col-span-2 space-y-6">
          <Card>
            <CardHeader title="Gym Overview" icon={Dumbbell} />
            <div className="p-4 space-y-4">
              <div>
                <div className="flex items-center justify-between text-sm mb-2">
                  <span className="text-ink-400">Capacity Usage</span>
                  <span className="font-mono text-ink-200">{gym.id ? `${formatRecord(gym.wins, gym.losses, gym.draws)} record` : ''}</span>
                </div>
                <div className="h-2 bg-ink-900 rounded-full overflow-hidden">
                  <div className="h-full bg-gold-500" style={{ width: `${capacityPct}%` }} />
                </div>
              </div>

              <div className="grid grid-cols-2 gap-3 pt-4 border-t border-ink-800">
                <Detail label="Founded" value={new Date(gym.created_at).toLocaleDateString()} />
                <Detail label="Gym ID" value={gym.id.slice(0, 8)} />
                <Detail label="Wins" value={String(gym.wins)} />
                <Detail label="Losses" value={String(gym.losses)} />
                <Detail label="Draws" value={String(gym.draws)} />
                <Detail label="World Date" value={world ? formatDate(world) : '—'} />
              </div>
            </div>
          </Card>

          {/* Future expansion placeholder */}
          <Card>
            <CardHeader title="Gym Facilities" icon={Wrench} subtitle="Planned feature — coming soon" />
            <div className="p-4">
              <div className="grid grid-cols-2 md:grid-cols-3 gap-3">
                {['Strength & Conditioning', 'Recovery Suite', 'Sparring Cage', 'Sauna & Cut Room', 'Nutrition Lab', 'Strategy Room'].map((facility) => (
                  <div key={facility} className="rounded-lg bg-ink-900 border border-ink-800 p-3 opacity-50">
                    <div className="text-xs text-ink-400 uppercase tracking-wide font-semibold">{facility}</div>
                    <div className="text-xs text-ink-500 mt-1">Not built</div>
                  </div>
                ))}
              </div>
              <p className="text-xs text-ink-500 mt-3">
                Facilities, coaches, and staff are architecture-ready and will be added in a future update.
              </p>
            </div>
          </Card>
        </div>

        <div className="space-y-6">
          <Card>
            <CardHeader title="Quick Actions" icon={Swords} />
            <div className="p-3 space-y-2">
              <button onClick={() => navigate('scout')} className="btn-primary w-full justify-start">
                <Users className="w-4 h-4" /> Scout New Fighters
              </button>
              <button onClick={() => navigate('my-fighters')} className="btn-secondary w-full justify-start">
                <Users className="w-4 h-4" /> View My Fighters
              </button>
              <button onClick={() => navigate('fight-offers')} className="btn-secondary w-full justify-start">
                <Trophy className="w-4 h-4" /> View Fight Offers
              </button>
              <button onClick={() => navigate('leaderboard')} className="btn-secondary w-full justify-start">
                <TrendingUp className="w-4 h-4" /> Leaderboard
              </button>
            </div>
          </Card>
        </div>
      </div>
    </div>
  );
}

function Detail({ label, value }: { label: string; value: string }) {
  return (
    <div>
      <div className="text-xs text-ink-500 uppercase tracking-wide">{label}</div>
      <div className="text-sm text-ink-200 mt-0.5 font-mono">{value}</div>
    </div>
  );
}
