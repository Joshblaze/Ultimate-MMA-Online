import { useEffect, useState } from 'react';
import { Building2, Crown, CalendarDays, ListOrdered, ChevronLeft } from 'lucide-react';
import type { PageProps } from '../App';
import { Card, CardHeader, EmptyState, PageHeader, Badge, Spinner, Belt } from '../components/ui';
import { HiddenSkillCell } from '../components/FighterCard';
import { ResponsiveDataView } from '../components/ResponsiveDataView';
import { fetchPromotion } from '../lib/queries';
import { formatNumber, formatRecord, formatTick } from '../lib/format';
import { PROMOTION_TIER_NAMES, PROMOTION_TIER_COLORS, rankPositionTextClass } from '../lib/constants';
import { useGym } from '../lib/gym';
import { useAuth } from '../lib/auth';
import { navigate } from '../App';
import type { Promotion } from '../lib/types';

interface PromoDetail {
  promotion: Promotion | null;
  championships: any[];
  events: any[];
  rankings: any[];
}

export function PromotionProfile({ params }: PageProps) {
  const { gym } = useGym();
  const { profile } = useAuth();
  const [data, setData] = useState<PromoDetail | null>(null);
  const [loading, setLoading] = useState(true);
  const [tab, setTab] = useState<'champions' | 'rankings' | 'events'>('champions');
  const [rankWc, setRankWc] = useState<string>('Flyweight');

  useEffect(() => {
    fetchPromotion(params.id)
      .then(setData)
      .catch((e) => console.error('Failed to load promotion:', e.message))
      .finally(() => setLoading(false));
  }, [params.id]);

  if (loading) {
    return (
      <div>
        <PageHeader title="Promotion" icon={Building2} />
        <Card><div className="p-8 text-center text-ink-500 text-sm flex items-center justify-center gap-2">
          <Spinner /> Loading...
        </div></Card>
      </div>
    );
  }

  if (!data?.promotion) {
    return (
      <div>
        <PageHeader title="Promotion" icon={Building2} />
        <Card><EmptyState icon={Building2} title="Promotion not found" /></Card>
      </div>
    );
  }

  const p = data.promotion;
  const rankingsForWc = data.rankings.filter((r) => r.weight_class === rankWc);
  const weightClassOptions = Array.from(new Set(data.rankings.map((r) => r.weight_class)));

  return (
    <div className="animate-slideUp">
      <button
        onClick={() => navigate('promotions')}
        className="flex items-center gap-1 text-sm text-ink-400 hover:text-ink-200 mb-4"
      >
        <ChevronLeft className="w-4 h-4" /> Back to Promotions
      </button>

      <PageHeader
        title={p.name}
        subtitle={`${p.country} · ${p.owner_kind === 'player' ? 'Player-owned' : 'AI-controlled'}`}
        icon={Building2}
        action={
          <Badge className={PROMOTION_TIER_COLORS[p.tier]}>
            {PROMOTION_TIER_NAMES[p.tier]}
          </Badge>
        }
      />

      <div className="grid grid-cols-1 sm:grid-cols-2 md:grid-cols-4 gap-3 mb-6">
        <div className="card p-4">
          <div className="stat-label">Reputation</div>
          <div className="stat-value text-ink-100">{p.reputation}</div>
        </div>
        <div className="card p-4">
          <div className="stat-label">Fan Base</div>
          <div className="stat-value text-gold-300">{formatNumber(p.fan_base)}</div>
        </div>
        <div className="card p-4">
          <div className="stat-label">Active Champions</div>
          <div className="stat-value text-gold-300">{data.championships.filter((c) => c.current_champion).length}/{data.championships.length}</div>
        </div>
        <div className="card p-4">
          <div className="stat-label">Events</div>
          <div className="stat-value text-ink-100">{data.events.length}</div>
        </div>
      </div>

      <div className="flex gap-2 mb-4 border-b border-ink-800">
        {(['champions', 'rankings', 'events'] as const).map((t) => (
          <button
            key={t}
            onClick={() => setTab(t)}
            className={`px-4 py-2 text-sm font-semibold capitalize transition-colors ${
              tab === t ? 'text-gold-300 border-b-2 border-gold-500' : 'text-ink-400 hover:text-ink-200'
            }`}
          >
            {t}
          </button>
        ))}
      </div>

      {tab === 'champions' && (
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-3">
          {data.championships.length === 0 ? (
            <Card className="md:col-span-2 lg:col-span-4"><EmptyState icon={Crown} title="No championships" /></Card>
          ) : data.championships.map((c) => (
            <Card key={c.id} className="p-4">
              <div className="flex items-center gap-3 mb-3">
                {c.current_champion ? (
                  <Belt size="md" glowing />
                ) : (
                  <div className="w-8 h-8 rounded-md bg-ink-800 border border-ink-700 flex items-center justify-center">
                    <Crown className="w-4 h-4 text-ink-600" />
                  </div>
                )}
                <div>
                  <div className="text-xs text-ink-500 uppercase">{c.weight_class}</div>
                  {c.current_champion ? (
                    <button
                      onClick={() => navigate(`fighter/${c.current_champion.id}`)}
                      className="text-sm font-display font-semibold text-gold-300 hover:text-gold-200"
                    >
                      {c.current_champion.name}
                    </button>
                  ) : (
                    <div className="text-sm font-display font-semibold text-ink-500">VACANT</div>
                  )}
                </div>
              </div>
              {c.current_champion && (
                <div className="text-xs text-ink-400">
                  {formatRecord(c.current_champion.wins, c.current_champion.losses)} · {c.current_champion.country}
                </div>
              )}
            </Card>
          ))}
        </div>
      )}

      {tab === 'rankings' && (
        <Card>
          <CardHeader
            title="Top 15 Rankings"
            icon={ListOrdered}
            action={
              <select
                value={rankWc}
                onChange={(e) => setRankWc(e.target.value)}
                className="input w-auto"
              >
                {weightClassOptions.map((wc) => (
                  <option key={wc} value={wc}>{wc}</option>
                ))}
              </select>
            }
          />
          {rankingsForWc.length === 0 ? (
            <EmptyState icon={ListOrdered} title="No rankings" body="Rankings have not been computed for this weight class yet." />
          ) : (
            <ResponsiveDataView
              mobileRows={rankingsForWc.map((r) => (
                <div
                  key={r.id}
                  className="mobile-list-item"
                  onClick={() => navigate(`fighter/${r.fighter.id}`)}
                >
                  <div className="flex items-center gap-3">
                    <span className={`font-display font-bold text-xl w-10 flex-shrink-0 ${rankPositionTextClass(r.rank_position)}`}>
                      #{r.rank_position}
                    </span>
                    <div className="flex-1 min-w-0">
                      <div className="font-medium text-ink-100 truncate">{r.fighter.name}</div>
                      <div className="text-xs text-ink-400">{r.fighter.country}</div>
                      <div className="text-xs font-mono text-ink-300 mt-0.5">
                        {formatRecord(r.fighter.wins, r.fighter.losses)}
                      </div>
                    </div>
                    <HiddenSkillCell
                      fighter={r.fighter}
                      gymId={gym?.id}
                      isAdmin={profile?.is_admin ?? false}
                    />
                  </div>
                </div>
              ))}
            >
              <table className="w-full text-sm">
                <thead>
                  <tr className="text-xs text-ink-500 uppercase tracking-wide border-b border-ink-800">
                    <th className="px-3 py-2 text-left font-semibold w-12">#</th>
                    <th className="px-3 py-2 text-left font-semibold">Fighter</th>
                    <th className="px-3 py-2 text-left font-semibold">Country</th>
                    <th className="px-3 py-2 text-left font-semibold">Record</th>
                    <th className="px-3 py-2 text-left font-semibold">Promo Record</th>
                    <th className="px-3 py-2 text-left font-semibold">Win %</th>
                    <th className="px-3 py-2 text-left font-semibold">Skill</th>
                  </tr>
                </thead>
                <tbody className="divide-y divide-ink-800">
                  {rankingsForWc.map((r) => (
                    <tr key={r.id} className="table-row-hover" onClick={() => navigate(`fighter/${r.fighter.id}`)}>
                      <td className={`px-3 py-2 font-mono font-bold ${rankPositionTextClass(r.rank_position)}`}>#{r.rank_position}</td>
                      <td className="px-3 py-2 text-ink-100 font-medium">{r.fighter.name}</td>
                      <td className="px-3 py-2 text-ink-300">{r.fighter.country}</td>
                      <td className="px-3 py-2 text-ink-300 font-mono">{formatRecord(r.fighter.wins, r.fighter.losses)}</td>
                      <td className="px-3 py-2 text-ink-300 font-mono">
                        {r.promoStats && r.promoStats.promo_total > 0
                          ? formatRecord(r.promoStats.promo_wins, r.promoStats.promo_losses, r.promoStats.promo_draws)
                          : '—'}
                      </td>
                      <td className="px-3 py-2 text-ink-300 font-mono">
                        {r.promoStats && r.promoStats.promo_total > 0
                          ? `${Math.round(r.promoStats.promo_win_pct * 100)}%`
                          : '—'}
                      </td>
                      <td className="px-3 py-2">
                        <HiddenSkillCell
                          fighter={r.fighter}
                          gymId={gym?.id}
                          isAdmin={profile?.is_admin ?? false}
                        />
                      </td>
                    </tr>
                  ))}
                </tbody>
              </table>
            </ResponsiveDataView>
          )}
        </Card>
      )}

      {tab === 'events' && (
        <div className="grid grid-cols-1 md:grid-cols-2 gap-3">
          {data.events.length === 0 ? (
            <Card className="md:col-span-2"><EmptyState icon={CalendarDays} title="No events" /></Card>
          ) : data.events.map((e) => (
            <Card
              key={e.id}
              hover
              className="p-3"
              onClick={() => navigate(`events/${e.id}`)}
            >
              <div className="flex items-center justify-between">
                <div className="text-sm text-ink-100 font-medium">{e.name}</div>
                <Badge className={e.status === 'completed' ? 'text-ink-400 bg-ink-800 border-ink-700' : 'text-forest-300 bg-forest-700/30 border-forest-600/40'}>
                  {e.status}
                </Badge>
              </div>
              <div className="text-xs text-ink-500 mt-1">{formatTick(e.scheduled_week)}</div>
            </Card>
          ))}
        </div>
      )}
    </div>
  );
}
