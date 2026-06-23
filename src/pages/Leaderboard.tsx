import { useEffect, useState } from 'react';
import { Trophy, Crown, Users } from 'lucide-react';
import type { PageProps } from '../App';
import { Card, EmptyState, PageHeader, Spinner } from '../components/ui';
import { fetchGymLeaderboard } from '../lib/queries';
import { formatMoney, formatRecord } from '../lib/format';
import type { Gym } from '../lib/types';

export function Leaderboard(_: PageProps) {
  const [gyms, setGyms] = useState<Pick<Gym, 'id' | 'name' | 'tier' | 'reputation' | 'ranking' | 'champions_produced' | 'wins' | 'losses' | 'draws' | 'cash' | 'created_at'>[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    fetchGymLeaderboard(100)
      .then(setGyms)
      .catch((e) => console.error('Failed to load leaderboard:', e.message))
      .finally(() => setLoading(false));
  }, []);

  return (
    <div className="animate-slideUp">
      <PageHeader
        title="Gym Leaderboard"
        subtitle="Compete with other player gyms worldwide"
        icon={Trophy}
      />

      {loading ? (
        <Card><div className="p-8 text-center text-ink-500 text-sm flex items-center justify-center gap-2"><Spinner /> Loading leaderboard...</div></Card>
      ) : gyms.length === 0 ? (
        <Card><EmptyState icon={Users} title="No gyms ranked yet" body="Once players register and start building gyms, they'll appear on the leaderboard here." /></Card>
      ) : (
        <Card>
          <table className="w-full text-sm">
            <thead>
              <tr className="text-xs text-ink-500 uppercase tracking-wide border-b border-ink-800">
                <th className="px-3 py-3 text-left font-semibold w-12">#</th>
                <th className="px-3 py-3 text-left font-semibold">Gym</th>
                <th className="px-3 py-3 text-left font-semibold">Tier</th>
                <th className="px-3 py-3 text-left font-semibold">Reputation</th>
                <th className="px-3 py-3 text-left font-semibold">Champions</th>
                <th className="px-3 py-3 text-left font-semibold">Record</th>
                <th className="px-3 py-3 text-left font-semibold">Cash</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-ink-800">
              {gyms.map((gym, i) => {
                const rank = i + 1;
                return (
                  <tr key={gym.id} className="table-row-hover">
                    <td className="px-3 py-3">
                      <span className={`font-display font-bold text-lg ${
                        rank === 1 ? 'text-gold-400' :
                        rank <= 3 ? 'text-gold-300' :
                        rank <= 10 ? 'text-blue-300' :
                        'text-ink-400'
                      }`}>
                        {rank === 1 && <Trophy className="inline w-4 h-4 mr-1 mb-1" />}
                        {rank}
                      </span>
                    </td>
                    <td className="px-3 py-3">
                      <span className="font-medium text-ink-100">{gym.name}</span>
                    </td>
                    <td className="px-3 py-3">
                      <span className="badge text-gold-300 bg-gold-700/20 border-gold-600/30">
                        Tier {gym.tier}
                      </span>
                    </td>
                    <td className="px-3 py-3">
                      <span className="text-forest-300 font-medium">{gym.reputation}</span>
                    </td>
                    <td className="px-3 py-3">
                      <div className="flex items-center gap-1">
                        {gym.champions_produced > 0 && <Crown className="w-3.5 h-3.5 text-gold-400" />}
                        <span className="text-ink-200">{gym.champions_produced}</span>
                      </div>
                    </td>
                    <td className="px-3 py-3 text-ink-200 font-mono">{formatRecord(gym.wins, gym.losses, gym.draws)}</td>
                    <td className="px-3 py-3 text-gold-300 font-mono">{formatMoney(gym.cash)}</td>
                  </tr>
                );
              })}
            </tbody>
          </table>
        </Card>
      )}
    </div>
  );
}
