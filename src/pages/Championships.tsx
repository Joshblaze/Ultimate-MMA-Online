import { useEffect, useState } from 'react';
import { Crown } from 'lucide-react';
import type { PageProps } from '../App';
import { Card, EmptyState, PageHeader, Badge, Spinner, Belt, Avatar } from '../components/ui';
import { fetchAllChampionships, fetchTitleHistory } from '../lib/queries';
import { formatRecord, formatTick, formatTickRange } from '../lib/format';
import { PROMOTION_TIER_NAMES, PROMOTION_TIER_COLORS, WEIGHT_CLASSES } from '../lib/constants';
import { navigate } from '../App';

interface ChampRow {
  id: string;
  weight_class: string;
  current_champion_fighter_id: string | null;
  current_champion?: { id: string; name: string; wins: number; losses: number; country: string } | null;
  promotion?: { id: string; name: string; tier: number; country: string } | null;
  weight_class_obj?: { name: string; weight_lbs: number; order: number } | null;
}

export function Championships(_: PageProps) {
  const [champs, setChamps] = useState<ChampRow[]>([]);
  const [loading, setLoading] = useState(true);
  const [wcFilter, setWcFilter] = useState('All');
  const [selected, setSelected] = useState<ChampRow | null>(null);
  const [history, setHistory] = useState<any[]>([]);
  const [historyLoading, setHistoryLoading] = useState(false);

  useEffect(() => {
    fetchAllChampionships()
      .then((data) => setChamps(data as ChampRow[]))
      .catch((e) => console.error('Failed to load championships:', e.message))
      .finally(() => setLoading(false));
  }, []);

  useEffect(() => {
    if (!selected) return;
    setHistoryLoading(true);
    fetchTitleHistory(selected.id)
      .then(setHistory)
      .catch((e) => console.error('Failed to load title history:', e.message))
      .finally(() => setHistoryLoading(false));
  }, [selected]);

  const filtered = champs.filter((c) => wcFilter === 'All' || c.weight_class === wcFilter);

  if (loading) {
    return (
      <div>
        <PageHeader title="Championships" icon={Crown} />
        <Card><div className="p-8 text-center text-ink-500 text-sm flex items-center justify-center gap-2">
          <Spinner /> Loading championships...
        </div></Card>
      </div>
    );
  }

  return (
    <div className="animate-slideUp">
      <PageHeader
        title="Championships"
        subtitle={`${champs.length} titles across ${champs.length ? new Set(champs.map((c) => c.promotion?.id).filter(Boolean)).size : 0} promotions`}
        icon={Crown}
      />

      <div className="flex flex-wrap gap-2 mb-4">
        <button
          onClick={() => setWcFilter('All')}
          className={`btn text-xs ${wcFilter === 'All' ? 'btn-primary' : 'btn-secondary'}`}
        >
          All
        </button>
        {WEIGHT_CLASSES.map((wc) => (
          <button
            key={wc.name}
            onClick={() => setWcFilter(wc.name)}
            className={`btn text-xs ${wcFilter === wc.name ? 'btn-primary' : 'btn-secondary'}`}
          >
            {wc.name}
          </button>
        ))}
      </div>

      {filtered.length === 0 ? (
        <Card><EmptyState icon={Crown} title="No championships" body="Promotions have not generated any championships yet." /></Card>
      ) : (
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
          {filtered.map((c) => {
            const champ = c.current_champion;
            const promotion = c.promotion;
            return (
              <Card
                key={c.id}
                hover
                className="p-4 cursor-pointer"
                onClick={() => setSelected(c)}
              >
                <div className="flex items-center gap-3 mb-3">
                  <Belt size="lg" glowing={!!champ} />
                  <div className="flex-1 min-w-0">
                    <div className="text-xs text-ink-500 uppercase tracking-wide">{c.weight_class}</div>
                    {promotion && (
                      <button
                        onClick={(e) => {
                          e.stopPropagation();
                          navigate(`promotion/${promotion.id}`);
                        }}
                        className="text-sm text-ink-200 hover:text-gold-300 font-medium truncate block"
                      >
                        {promotion.name}
                      </button>
                    )}
                    {promotion && (
                      <Badge className={PROMOTION_TIER_COLORS[promotion.tier]}>
                        {PROMOTION_TIER_NAMES[promotion.tier]}
                      </Badge>
                    )}
                  </div>
                </div>

                {champ ? (
                  <div className="flex items-center gap-3 p-3 rounded-lg bg-gradient-to-br from-gold-950/40 to-ink-900 border border-gold-800/40">
                    <Avatar name={champ.name} size="md" />
                    <div className="flex-1 min-w-0">
                      <button
                        onClick={(e) => {
                          e.stopPropagation();
                          navigate(`fighter/${champ.id}`);
                        }}
                        className="font-display font-bold text-gold-300 hover:text-gold-200 truncate block"
                      >
                        {champ.name}
                      </button>
                      <div className="text-xs text-ink-400 mt-0.5">
                        {formatRecord(champ.wins, champ.losses)} · {champ.country}
                      </div>
                    </div>
                    <Crown className="w-5 h-5 text-gold-400" />
                  </div>
                ) : (
                  <div className="text-center py-4 text-ink-500 text-sm font-display tracking-wider uppercase">
                    Vacant Title
                  </div>
                )}
              </Card>
            );
          })}
        </div>
      )}

      {/* Title detail modal */}
      {selected && (
        <div
          className="fixed inset-0 z-50 bg-black/70 backdrop-blur-sm flex items-center justify-center p-4 animate-fadeIn"
          onClick={() => setSelected(null)}
        >
          <div
            className="bg-ink-850 border border-ink-700 rounded-xl shadow-2xl max-w-2xl w-full max-h-[80vh] overflow-y-auto"
            onClick={(e) => e.stopPropagation()}
          >
            <div className="p-6 border-b border-ink-800">
              <div className="flex items-center gap-4">
                <Belt size="lg" glowing={!!selected.current_champion} />
                <div>
                  <h2 className="font-display text-2xl font-bold text-gold-300">{selected.weight_class} Title</h2>
                  {selected.promotion && (
                    <div className="text-sm text-ink-400">
                      {selected.promotion.name} · {PROMOTION_TIER_NAMES[selected.promotion.tier]}
                    </div>
                  )}
                </div>
              </div>
            </div>

            <div className="p-6">
              {selected.current_champion ? (
                <div className="flex items-center gap-3 mb-4 p-4 rounded-lg bg-gradient-to-br from-gold-950/50 to-ink-900 border border-gold-800/40">
                  <Avatar name={selected.current_champion.name} size="lg" />
                  <div className="flex-1">
                    <button
                      onClick={() => { navigate(`fighter/${selected.current_champion!.id}`); setSelected(null); }}
                      className="font-display font-bold text-lg text-gold-300 hover:text-gold-200"
                    >
                      {selected.current_champion.name}
                    </button>
                    <div className="text-sm text-ink-400">{selected.current_champion.country}</div>
                    <div className="text-xs text-ink-500 mt-1 font-mono">
                      {formatRecord(selected.current_champion.wins, selected.current_champion.losses)}
                    </div>
                  </div>
                  <Crown className="w-7 h-7 text-gold-400" />
                </div>
              ) : (
                <div className="text-center py-6 text-ink-500 font-display tracking-wider uppercase mb-4">
                  Title is currently vacant
                </div>
              )}

              <h3 className="font-display font-semibold text-ink-200 mb-2 uppercase text-xs tracking-wide">
                Title History
              </h3>
              {historyLoading ? (
                <div className="text-center text-ink-500 text-sm py-4"><Spinner className="w-5 h-5 mx-auto" /></div>
              ) : history.length === 0 ? (
                <div className="text-sm text-ink-500">No reigns recorded yet.</div>
              ) : (
                <div className="space-y-2">
                  {history.map((h, i) => (
                    <div
                      key={h.id}
                      className={`flex items-center justify-between p-2.5 rounded-lg ${i === 0 && h.lost_at_week === null ? 'bg-gold-950/30 border border-gold-800/40' : 'bg-ink-900 border border-ink-800'}`}
                    >
                      <div className="flex items-center gap-2">
                        {i === 0 && h.lost_at_week === null && <Belt size="sm" />}
                        <button
                          onClick={() => { navigate(`fighter/${h.fighter.id}`); setSelected(null); }}
                          className={`text-sm hover:text-gold-300 ${i === 0 && h.lost_at_week === null ? 'text-gold-300 font-semibold' : 'text-ink-200'}`}
                        >
                          {h.fighter.name}
                        </button>
                      </div>
                      <div className="text-xs text-ink-400 flex items-center gap-3">
                        <span>Defenses: {h.defenses}</span>
                        <span>
                          {h.lost_at_week != null
                            ? formatTickRange(h.won_at_week, h.lost_at_week)
                            : `${formatTick(h.won_at_week)} – present`}
                        </span>
                      </div>
                    </div>
                  ))}
                </div>
              )}
            </div>

            <div className="p-4 border-t border-ink-800 flex justify-end">
              <button onClick={() => setSelected(null)} className="btn-secondary text-sm">Close</button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
