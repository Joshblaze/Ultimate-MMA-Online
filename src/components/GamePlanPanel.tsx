import { useState } from 'react';
import { Target } from 'lucide-react';
import type { FightGamePlanInput, GamePlanPreset } from '../lib/types';
import { Card, CardHeader, Spinner } from './ui';

const PRESETS: { id: GamePlanPreset; label: string; hint: string }[] = [
  { id: 'striker', label: 'Striker', hint: 'Prioritize boxing and kickboxing' },
  { id: 'grappler', label: 'Grappler', hint: 'Wrestling and submissions' },
  { id: 'counter', label: 'Counter', hint: 'Defense and timing' },
  { id: 'volume', label: 'Volume', hint: 'High output striking' },
];

const SLIDERS: { key: keyof Omit<FightGamePlanInput, 'preset'>; label: string; low: string; high: string }[] = [
  { key: 'pressure', label: 'Pressure', low: 'Patient', high: 'Forward' },
  { key: 'distance', label: 'Distance', low: 'Clinch', high: 'Range' },
  { key: 'takedown_freq', label: 'Takedowns', low: 'Stay up', high: 'Shoot often' },
  { key: 'risk', label: 'Risk', low: 'Safe', high: 'Finish hunting' },
];

export function defaultGamePlan(): FightGamePlanInput {
  return { preset: 'volume', pressure: 50, distance: 50, takedown_freq: 50, risk: 50 };
}

export function GamePlanPanel({
  fighterName,
  forRound,
  initialPlan,
  submitting,
  onSubmit,
}: {
  fighterName: string;
  forRound: number;
  initialPlan?: FightGamePlanInput;
  submitting: boolean;
  onSubmit: (plan: FightGamePlanInput) => Promise<void>;
}) {
  const [plan, setPlan] = useState<FightGamePlanInput>(initialPlan ?? defaultGamePlan());

  function setPreset(preset: GamePlanPreset) {
    setPlan((prev) => ({ ...prev, preset }));
  }

  function setSlider(key: keyof Omit<FightGamePlanInput, 'preset'>, value: number) {
    setPlan((prev) => ({ ...prev, [key]: value }));
  }

  return (
    <Card className="border-gold-700/30">
      <CardHeader
        title={`Game Plan — ${fighterName}`}
        subtitle={`Round ${forRound} corner instructions`}
        icon={Target}
      />
      <div className="p-4 space-y-5">
        <div>
          <div className="text-xs text-ink-500 uppercase tracking-wide font-semibold mb-2">Preset</div>
          <div className="grid grid-cols-2 sm:grid-cols-4 gap-2">
            {PRESETS.map((p) => (
              <button
                key={p.id}
                type="button"
                onClick={() => setPreset(p.id)}
                className={`rounded-lg border px-3 py-2 text-left transition-colors ${
                  plan.preset === p.id
                    ? 'border-gold-500/60 bg-gold-700/20 text-gold-200'
                    : 'border-ink-700 bg-ink-900/40 text-ink-300 hover:border-ink-600'
                }`}
              >
                <div className="text-sm font-medium">{p.label}</div>
                <div className="text-xs text-ink-500 mt-0.5">{p.hint}</div>
              </button>
            ))}
          </div>
        </div>

        <div className="space-y-4">
          <div className="text-xs text-ink-500 uppercase tracking-wide font-semibold">Tactics</div>
          {SLIDERS.map((s) => (
            <div key={s.key}>
              <div className="flex items-center justify-between text-sm mb-1">
                <span className="text-ink-200">{s.label}</span>
                <span className="text-gold-300 font-mono text-xs">{plan[s.key]}</span>
              </div>
              <input
                type="range"
                min={0}
                max={100}
                value={plan[s.key]}
                onChange={(e) => setSlider(s.key, Number(e.target.value))}
                className="w-full accent-gold-500"
              />
              <div className="flex justify-between text-xs text-ink-600 mt-0.5">
                <span>{s.low}</span>
                <span>{s.high}</span>
              </div>
            </div>
          ))}
        </div>

        <button
          type="button"
          disabled={submitting}
          onClick={() => onSubmit(plan)}
          className="btn-primary w-full text-sm"
        >
          {submitting ? <Spinner /> : `Submit plan for round ${forRound}`}
        </button>
      </div>
    </Card>
  );
}
