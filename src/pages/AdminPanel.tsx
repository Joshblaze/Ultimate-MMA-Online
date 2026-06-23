import { useEffect, useState } from 'react';
import {
  Settings, Pause, Play, SkipForward, RotateCcw, Trash2, AlertTriangle,
  CheckCircle2, Clock, CalendarDays,
} from 'lucide-react';
import type { PageProps } from '../App';
import { Card, CardHeader, PageHeader, Spinner, Badge, Alert } from '../components/ui';
import { callAdmin } from '../lib/queries';
import { useWorld } from '../lib/world';
import { formatDate } from '../lib/format';

type AdminAction = 'pause' | 'resume' | 'advance' | 'reset' | 'wipe_gyms' | 'wipe_fighters' | 'status';
const CONFIRMABLE: AdminAction[] = ['advance', 'reset', 'wipe_gyms', 'wipe_fighters'];

const ACTION_META: Record<AdminAction, { label: string; icon: React.ComponentType<{ className?: string }>; danger?: boolean; desc: string }> = {
  pause: { label: 'Pause Simulation', icon: Pause, desc: 'Halts the world simulation. No weekly ticks will occur while paused.' },
  resume: { label: 'Resume Simulation', icon: Play, desc: 'Resumes the world simulation. Weekly ticks continue each hour.' },
  advance: { label: 'Advance One Week', icon: SkipForward, desc: 'Manually advances the world by one week (runs all tick phases immediately).' },
  reset: { label: 'Reset World to Day 1', icon: RotateCcw, danger: true, desc: 'Wipes all gyms/fighters/promotions/events and regenerates a fresh world. User accounts are preserved.' },
  wipe_gyms: { label: 'Wipe All Gyms', icon: Trash2, danger: true, desc: 'Deletes all player gyms and releases their fighters. Does not affect sim state.' },
  wipe_fighters: { label: 'Wipe All Fighters', icon: Trash2, danger: true, desc: 'Deletes all fighters, contracts, rankings, and clears champions. World will resupply on next tick.' },
  status: { label: 'Check Status', icon: Clock, desc: 'Refresh the simulation status below.' },
};

export function AdminPanel(_: PageProps) {
  const { world, refresh } = useWorld();
  const [pending, setPending] = useState<AdminAction | null>(null);
  const [confirming, setConfirming] = useState<AdminAction | null>(null);
  const [message, setMessage] = useState<{ kind: 'success' | 'error'; text: string } | null>(null);
  const [advanceResult, setAdvanceResult] = useState<any>(null);

  async function runAction(action: AdminAction) {
    if (CONFIRMABLE.includes(action) && confirming !== action) {
      setConfirming(action);
      return;
    }
    setMessage(null);
    setAdvanceResult(null);
    setPending(action);
    try {
      const result: any = await callAdmin(action);
      if (action === 'advance' && result?.data) {
        setAdvanceResult(result.data);
      }
      const meta = ACTION_META[action];
      setMessage({ kind: 'success', text: `${meta.label} succeeded.` });
      await refresh();
    } catch (e) {
      setMessage({ kind: 'error', text: (e as Error).message });
    } finally {
      setPending(null);
      setConfirming(null);
    }
  }

  useEffect(() => {
    if (!world) {
      // initial status fetch — the world context will populate
      callAdmin('status').catch(() => {});
    }
  }, [world]);

  return (
    <div className="animate-slideUp">
      <PageHeader
        title="Admin Panel"
        subtitle="Simulation controls and world management"
        icon={Settings}
        action={
          world && (
            <Badge className={world.is_paused ? 'text-blood-300 bg-blood-700/30 border-blood-600/40' : 'text-forest-300 bg-forest-700/30 border-forest-600/40'}>
              {world.is_paused ? 'PAUSED' : 'RUNNING'}
            </Badge>
          )
        }
      />

      {world && (
        <Card className="mb-6">
          <CardHeader title="World Status" icon={CalendarDays} />
          <div className="p-4 grid grid-cols-2 md:grid-cols-4 gap-4">
            <div>
              <div className="stat-label">Current Date</div>
              <div className="stat-value text-ink-100">{world ? formatDate(world) : '—'}</div>
            </div>
            <div>
              <div className="stat-label">Tick</div>
              <div className="stat-value text-gold-300">{world?.tick_count ?? 0}</div>
            </div>
            <div>
              <div className="stat-label">Last Tick</div>
              <div className="text-sm text-ink-200 mt-2">
                {world?.last_tick_at ? new Date(world.last_tick_at).toLocaleString() : 'Never'}
              </div>
            </div>
            <div>
              <div className="stat-label">Status</div>
              <div className={`text-sm font-semibold mt-2 ${world?.is_paused ? 'text-blood-300' : 'text-forest-300'}`}>
                {world?.is_paused ? 'Paused' : 'Running'}
              </div>
            </div>
          </div>
        </Card>
      )}

      {message && (
        <div className="mb-4">
          {message.kind === 'success' ? (
            <Alert variant="success"><span className="flex items-center gap-2"><CheckCircle2 className="w-4 h-4" /> {message.text}</span></Alert>
          ) : (
            <Alert variant="error"><span className="flex items-center gap-2"><AlertTriangle className="w-4 h-4" /> {message.text}</span></Alert>
          )}
        </div>
      )}

      {advanceResult && (
        <Card className="mb-6">
          <CardHeader title="Advance Result" icon={SkipForward} />
          <div className="p-4 grid grid-cols-2 md:grid-cols-4 gap-3 text-sm">
            <ResultStat label="New Tick" value={advanceResult.tick} />
            <ResultStat label="Retired" value={advanceResult.retired} />
            <ResultStat label="Signed" value={advanceResult.signed} />
            <ResultStat label="Events" value={advanceResult.events_processed} />
            <ResultStat label="Fights" value={advanceResult.fights_simulated} />
            <ResultStat label="Offers" value={advanceResult.offers_generated} />
            <ResultStat label="Purses Paid" value={`$${advanceResult.purses_paid?.toLocaleString()}`} />
            <ResultStat label="Status" value={advanceResult.status} />
          </div>
        </Card>
      )}

      <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
        {(['resume', 'pause', 'advance', 'wipe_gyms', 'wipe_fighters', 'reset'] as AdminAction[]).map((action) => {
          const meta = ACTION_META[action];
          const Icon = meta.icon;
          const isConfirming = confirming === action;
          const isPending = pending === action;
          const isDanger = meta.danger;
          return (
            <Card key={action} className="p-4">
              <div className="flex items-start gap-3 mb-3">
                <div className={`w-10 h-10 rounded-lg flex items-center justify-center flex-shrink-0 ${
                  isDanger ? 'bg-blood-950/50' : 'bg-ink-800'
                }`}>
                  <Icon className={isDanger ? 'w-5 h-5 text-blood-400' : 'w-5 h-5 text-gold-400'} />
                </div>
                <div className="flex-1 min-w-0">
                  <h4 className="font-display font-semibold text-ink-100">{meta.label}</h4>
                  <p className="text-xs text-ink-400 mt-0.5">{meta.desc}</p>
                </div>
              </div>
              {isConfirming ? (
                <div className="flex items-center gap-2">
                  <AlertTriangle className="w-4 h-4 text-blood-400" />
                  <span className="text-xs text-blood-300 flex-1">Are you sure? This cannot be undone.</span>
                  <button
                    onClick={() => runAction(action)}
                    disabled={isPending}
                    className={`btn text-xs ${isDanger ? 'btn-danger' : 'btn-primary'}`}
                  >
                    {isPending ? <Spinner className="w-3 h-3" /> : 'Confirm'}
                  </button>
                  <button
                    onClick={() => setConfirming(null)}
                    disabled={isPending}
                    className="btn-secondary text-xs"
                  >
                    Cancel
                  </button>
                </div>
              ) : (
                <button
                  onClick={() => runAction(action)}
                  disabled={isPending || action === 'pause' && world?.is_paused || action === 'resume' && !world?.is_paused}
                  className={`btn w-full text-sm ${isDanger ? 'btn-danger' : 'btn-primary'}`}
                >
                  {isPending ? <><Spinner /> Running...</> : <><Icon className="w-4 h-4" /> {meta.label}</>}
                </button>
              )}
            </Card>
          );
        })}
      </div>

      <div className="mt-6 text-xs text-ink-500 text-center">
        The world simulation automatically runs every hour (1 real hour = 1 in-game week).
        Manual advances do not affect the hourly schedule.
      </div>
    </div>
  );
}

function ResultStat({ label, value }: { label: string; value: React.ReactNode }) {
  return (
    <div className="rounded-lg bg-ink-900 border border-ink-800 p-2.5">
      <div className="text-[10px] text-ink-500 uppercase tracking-wider">{label}</div>
      <div className="text-sm text-ink-100 mt-0.5 font-display font-semibold">{value ?? '—'}</div>
    </div>
  );
}
