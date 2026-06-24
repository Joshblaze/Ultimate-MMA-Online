import { useState } from 'react';
import { Dumbbell, AlertCircle } from 'lucide-react';
import { supabase } from '../lib/supabase';
import { useAuth } from '../lib/auth';
import { useGym } from '../lib/gym';
import { Spinner } from '../components/ui';
import { STARTING_CASH, STARTING_CAPACITY, STARTING_REPUTATION } from '../lib/constants';
import { formatMoney } from '../lib/format';

const GYM_NAME_PRESETS = [
  'Iron Fist MMA', 'Predator Training Camp', 'Lionheart Gym',
  'Black Belt Academy', 'Knockout Kings', 'Warrior Forge',
];

export function CreateGymScreen() {
  const { user } = useAuth();
  const { refresh } = useGym();
  const [name, setName] = useState('');
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    setError(null);
    if (!name.trim()) return setError('Enter a gym name.');
    if (name.trim().length < 3) return setError('Gym name must be at least 3 characters.');
    if (!user) return setError('Not signed in.');

    setLoading(true);
    const { error: insertError } = await supabase.from('gyms').insert([{
      owner_id: user.id,
      name: name.trim(),
      tier: 1,
      reputation: STARTING_REPUTATION,
      capacity: STARTING_CAPACITY,
      cash: STARTING_CASH,
      wins: 0,
      losses: 0,
      draws: 0,
      champions_produced: 0,
    }] as any);
    if (insertError) {
      setLoading(false);
      return setError(insertError.message);
    }
    await refresh();
  }

  return (
    <div className="min-h-screen flex items-center justify-center px-4 py-8 sm:py-12 pt-safe pb-safe">
      <div className="w-full max-w-md">
        <div className="text-center mb-6 sm:mb-8">
          <div className="inline-flex items-center justify-center w-14 h-14 sm:w-16 sm:h-16 rounded-2xl bg-gradient-to-br from-gold-500 to-gold-700 shadow-belt mb-4">
            <Dumbbell className="w-7 h-7 sm:w-8 sm:h-8 text-ink-950" />
          </div>
          <h1 className="font-display text-2xl sm:text-3xl font-bold text-ink-100 mb-2">
            Found Your Gym
          </h1>
          <p className="text-sm text-ink-400 px-2">
            Every legend starts somewhere. Name your new MMA gym to begin.
          </p>
        </div>

        <div className="card-glass p-5 sm:p-6">
          <div className="grid grid-cols-1 sm:grid-cols-3 gap-2 sm:gap-3 mb-6">
            <Stat label="Starting Cash" value={formatMoney(STARTING_CASH)} />
            <Stat label="Tier" value="1" />
            <Stat label="Capacity" value={`${STARTING_CAPACITY}`} />
          </div>

          <form onSubmit={handleSubmit} className="space-y-4">
            <div>
              <label className="label">Gym Name</label>
              <input
                type="text"
                value={name}
                onChange={(e) => setName(e.target.value)}
                className="input"
                placeholder="e.g., Iron Fist MMA"
                maxLength={40}
                autoFocus
              />
            </div>

            <div>
              <div className="text-xs text-ink-500 mb-2">Or pick a preset:</div>
              <div className="flex flex-wrap gap-2">
                {GYM_NAME_PRESETS.map((preset) => (
                  <button
                    key={preset}
                    type="button"
                    onClick={() => setName(preset)}
                    className="px-2.5 py-1 rounded-md text-xs bg-ink-800 hover:bg-ink-700 text-ink-300 hover:text-ink-100 border border-ink-700 transition-colors"
                  >
                    {preset}
                  </button>
                ))}
              </div>
            </div>

            {error && (
              <div className="flex items-start gap-2 text-sm text-blood-300 bg-blood-950/50 border border-blood-800/50 rounded-lg p-3">
                <AlertCircle className="w-4 h-4 flex-shrink-0 mt-0.5" />
                <span>{error}</span>
              </div>
            )}

            <button type="submit" disabled={loading} className="btn-primary w-full py-2.5">
              {loading ? <><Spinner /> Creating...</> : 'Found My Gym'}
            </button>
          </form>
        </div>

        <p className="text-center text-xs text-ink-500 mt-4">
          You can rename your gym later from the My Gym page.
        </p>
      </div>
    </div>
  );
}

function Stat({ label, value }: { label: string; value: string }) {
  return (
    <div className="rounded-lg bg-ink-900 border border-ink-800 p-3 text-center">
      <div className="text-[10px] uppercase tracking-wider text-ink-500 mb-1">{label}</div>
      <div className="font-display font-bold text-gold-300 text-sm">{value}</div>
    </div>
  );
}
