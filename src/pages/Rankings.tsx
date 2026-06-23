import { useEffect, useState } from 'react';
import { ListOrdered } from 'lucide-react';
import type { PageProps } from '../App';
import { Card, EmptyState, PageHeader, Spinner } from '../components/ui';
import { HiddenSkillCell } from '../components/FighterCard';
import { fetchRankings } from '../lib/queries';
import { formatRecord } from '../lib/format';
import { PROMOTION_TIER_NAMES, PROMOTION_TIER_COLORS, WEIGHT_CLASSES } from '../lib/constants';
import { useGym } from '../lib/gym';
import { useAuth } from '../lib/auth';
import { navigate } from '../App';
import { supabase } from '../lib/supabase';
import type { Promotion } from '../lib/types';

interface RankRow {
  id: string;
  weight_class: string;
  rank_position: number;
  fighter: { id: string; name: string; country: string; wins: number; losses: number; draws?: number; current_skill: number; gym_id?: string | null };
  promotion?: { id: string; name: string; tier: number };
}

export function Rankings(_: PageProps) {
  const { gym } = useGym();
  const { profile } = useAuth();
  const [promos, setPromos] = useState<Promotion[]>([]);
  const [selectedPromo, setSelectedPromo] = useState<string>('');
  const [wcFilter, setWcFilter] = useState('Flyweight');
  const [rankings, setRankings] = useState<RankRow[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    void Promise.resolve(supabase.from('promotions').select('*').order('tier', { ascending: false }).order('name'))
      .then(({ data, error }) => {
        if (error) throw error;
        const list = (data || []) as Promotion[];
        setPromos(list);
        if (list[0]) setSelectedPromo(list[0].id);
      })
      .catch((e: unknown) => {
        const msg = e instanceof Error ? e.message : String(e);
        console.error('Failed to load promotions list:', msg);
      });
  }, []);

  useEffect(() => {
    if (!selectedPromo) return;
    setLoading(true);
    fetchRankings(selectedPromo)
      .then((data) => setRankings(data as unknown as RankRow[]))
      .catch((e) => console.error('Failed to load rankings:', e.message))
      .finally(() => setLoading(false));
  }, [selectedPromo]);

  const filtered = rankings.filter((r) => r.weight_class === wcFilter);
  const promo = promos.find((p) => p.id === selectedPromo);

  return (
    <div className="animate-slideUp">
      <PageHeader
        title="Rankings"
        subtitle="Top 15 per promotion per weight class"
        icon={ListOrdered}
      />

      <div className="mb-4 flex flex-wrap gap-2 items-center">
        <select
          value={selectedPromo}
          onChange={(e) => setSelectedPromo(e.target.value)}
          className="input w-auto"
        >
          {promos.map((p) => (
            <option key={p.id} value={p.id}>
              {p.name} (Tier {p.tier})
            </option>
          ))}
        </select>
        <select
          value={wcFilter}
          onChange={(e) => setWcFilter(e.target.value)}
          className="input w-auto"
        >
          {WEIGHT_CLASSES.map((wc) => (
            <option key={wc.name} value={wc.name}>{wc.name}</option>
          ))}
        </select>
        {promo && (
          <span className={`badge border ${PROMOTION_TIER_COLORS[promo.tier]}`}>
            {PROMOTION_TIER_NAMES[promo.tier]}
          </span>
        )}
      </div>

      <Card>
        {loading ? (
          <div className="p-8 text-center text-ink-500 text-sm flex items-center justify-center gap-2">
            <Spinner /> Loading rankings...
          </div>
        ) : filtered.length === 0 ? (
          <EmptyState icon={ListOrdered} title="No rankings for this weight class" body="Try a different filter or check back after the next tick." />
        ) : (
          <table className="w-full text-sm">
            <thead>
              <tr className="text-xs text-ink-500 uppercase tracking-wide border-b border-ink-800">
                <th className="px-3 py-2 text-left font-semibold w-12">#</th>
                <th className="px-3 py-2 text-left font-semibold">Fighter</th>
                <th className="px-3 py-2 text-left font-semibold">Country</th>
                <th className="px-3 py-2 text-left font-semibold">Record</th>
                <th className="px-3 py-2 text-left font-semibold">Skill</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-ink-800">
              {filtered.sort((a, b) => a.rank_position - b.rank_position).map((r) => (
                <tr key={r.id} className="table-row-hover" onClick={() => navigate(`fighter/${r.fighter.id}`)}>
                  <td className="px-3 py-2">
                    <span className={`font-display font-bold text-lg ${
                      r.rank_position === 1 ? 'text-gold-400' :
                      r.rank_position <= 3 ? 'text-gold-300' :
                      r.rank_position <= 5 ? 'text-blue-300' :
                      'text-ink-400'
                    }`}>
                      #{r.rank_position}
                    </span>
                  </td>
                  <td className="px-3 py-2 text-ink-100 font-medium">{r.fighter.name}</td>
                  <td className="px-3 py-2 text-ink-300">{r.fighter.country}</td>
                  <td className="px-3 py-2 text-ink-300 font-mono">
                    {formatRecord(r.fighter.wins, r.fighter.losses, r.fighter.draws)}
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
        )}
      </Card>
    </div>
  );
}
