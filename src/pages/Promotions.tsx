import { useEffect, useState } from 'react';
import { Building2, Users, Crown, Star } from 'lucide-react';
import type { PageProps } from '../App';
import { Card, EmptyState, PageHeader, Badge, Spinner } from '../components/ui';
import { fetchPromotions } from '../lib/queries';
import { formatNumber } from '../lib/format';
import { PROMOTION_TIER_NAMES, PROMOTION_TIER_COLORS } from '../lib/constants';
import type { Promotion } from '../lib/types';
import { navigate } from '../App';
import { supabase } from '../lib/supabase';

export function Promotions(_: PageProps) {
  const [promos, setPromos] = useState<Promotion[]>([]);
  const [loading, setLoading] = useState(true);
  const [champCounts, setChampCounts] = useState<Record<string, number>>({});

  useEffect(() => {
    fetchPromotions()
      .then(async (data) => {
        setPromos(data);
        const counts: Record<string, number> = {};
        await Promise.all(data.map(async (p) => {
          const { count } = await supabase
            .from('championships')
            .select('id', { count: 'exact', head: true })
            .eq('promotion_id', p.id)
            .not('current_champion_fighter_id', 'is', null);
          counts[p.id] = count || 0;
        }));
        setChampCounts(counts);
      })
      .catch((e) => console.error('Failed to load promotions:', e.message))
      .finally(() => setLoading(false));
  }, []);

  return (
    <div className="animate-slideUp">
      <PageHeader
        title="Promotions"
        subtitle="AI-controlled MMA promotions across 5 tiers"
        icon={Building2}
      />

      {loading ? (
        <Card><div className="p-8 text-center text-ink-500 text-sm flex items-center justify-center gap-2">
          <Spinner /> Loading promotions...
        </div></Card>
      ) : promos.length === 0 ? (
        <Card><EmptyState icon={Building2} title="No promotions" body="The world simulation has not generated any promotions yet." /></Card>
      ) : (
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
          {promos.map((p) => (
            <Card key={p.id} hover onClick={() => navigate(`promotion/${p.id}`)} className="p-5">
              <div className="flex items-start justify-between mb-3">
                <div>
                  <div className="font-display font-bold text-lg text-ink-100">{p.name}</div>
                  <Badge className={PROMOTION_TIER_COLORS[p.tier]}>
                    {PROMOTION_TIER_NAMES[p.tier]}
                  </Badge>
                </div>
                <Building2 className="w-8 h-8 text-ink-700" />
              </div>

              <div className="space-y-2 pt-3 border-t border-ink-800">
                <Detail icon={Star} label="Reputation" value={String(p.reputation)} />
                <Detail icon={Users} label="Fan Base" value={formatNumber(p.fan_base)} />
                <Detail icon={Crown} label="Active Champions" value={`${champCounts[p.id] ?? 0} / 8`} />
                <div className="flex items-center gap-2 text-xs text-ink-500">
                  <span>Country: {p.country}</span>
                  <span>·</span>
                  <span>{p.owner_kind === 'player' ? 'Player-owned' : 'AI-controlled'}</span>
                </div>
              </div>
            </Card>
          ))}
        </div>
      )}
    </div>
  );
}

function Detail({ icon: Icon, label, value }: { icon: React.ComponentType<{ className?: string }>; label: string; value: string }) {
  return (
    <div className="flex items-center justify-between text-sm">
      <div className="flex items-center gap-2 text-ink-400">
        <Icon className="w-3.5 h-3.5" /> {label}
      </div>
      <span className="text-ink-100 font-medium">{value}</span>
    </div>
  );
}
