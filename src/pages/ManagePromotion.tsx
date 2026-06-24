import { useEffect, useState } from 'react';
import {
  Building2, CalendarDays, Plus, Send, AlertCircle, CheckCircle2, Swords,
} from 'lucide-react';
import type { PageProps } from '../App';
import { navigate } from '../App';
import { useGym } from '../lib/gym';
import { useWorld } from '../lib/world';
import { Card, CardHeader, EmptyState, PageHeader, Spinner, Badge, Alert } from '../components/ui';
import { FighterSearchPicker } from '../components/FighterSearchPicker';
import {
  fetchOwnedPromotion,
  fetchPromotionEvents,
  fetchBookableFighters,
  callCreatePromotionEvent,
  callSendContractOffer,
} from '../lib/queries';
import { formatTick } from '../lib/format';
import { EVENT_LEAD_WEEKS, OFFER_RESPONSE_WEEKS, PROMOTION_TIER_NAMES, PROMOTION_TIER_COLORS } from '../lib/constants';
import type { Fighter, Promotion } from '../lib/types';

export function ManagePromotion(_: PageProps) {
  const { gym } = useGym();
  const { world } = useWorld();
  const [promotion, setPromotion] = useState<Promotion | null>(null);
  const [events, setEvents] = useState<any[]>([]);
  const [fighters, setFighters] = useState<Fighter[]>([]);
  const [loading, setLoading] = useState(true);
  const [eventName, setEventName] = useState('');
  const [extraWeeks, setExtraWeeks] = useState(0);
  const [creatingEvent, setCreatingEvent] = useState(false);
  const [contractFighterId, setContractFighterId] = useState('');
  const [contractFights, setContractFights] = useState(4);
  const [contractPurse, setContractPurse] = useState(5000);
  const [sendingContract, setSendingContract] = useState(false);
  const [message, setMessage] = useState<{ kind: 'success' | 'error'; text: string } | null>(null);

  const minEventWeek = (world?.tick_count ?? 0) + EVENT_LEAD_WEEKS;
  const scheduledWeek = minEventWeek + extraWeeks;

  async function load() {
    if (!gym) return;
    setLoading(true);
    try {
      const promo = await fetchOwnedPromotion(gym.id);
      setPromotion(promo);
      if (promo) {
        const [evts, roster] = await Promise.all([
          fetchPromotionEvents(promo.id, 'scheduled'),
          fetchBookableFighters(promo.id),
        ]);
        setEvents(evts);
        setFighters(roster as Fighter[]);
      } else {
        setEvents([]);
        setFighters([]);
      }
    } catch (e) {
      setMessage({ kind: 'error', text: (e as Error).message });
    } finally {
      setLoading(false);
    }
  }

  useEffect(() => {
    load();
  }, [gym?.id, world?.tick_count]);

  if (!gym) return null;

  async function handleCreateEvent(e: React.FormEvent) {
    e.preventDefault();
    if (!promotion) return;
    setCreatingEvent(true);
    setMessage(null);
    try {
      const r = await callCreatePromotionEvent(eventName.trim(), scheduledWeek);
      if (r.status !== 'ok') throw new Error(r.message || 'Failed to create event.');
      setMessage({ kind: 'success', text: r.message || 'Event created.' });
      setEventName('');
      await load();
    } catch (err) {
      setMessage({ kind: 'error', text: (err as Error).message });
    } finally {
      setCreatingEvent(false);
    }
  }

  async function handleSendContract(e: React.FormEvent) {
    e.preventDefault();
    if (!contractFighterId) return;
    setSendingContract(true);
    setMessage(null);
    try {
      const r = await callSendContractOffer(contractFighterId, contractFights, contractPurse);
      if (r.status !== 'ok') throw new Error(r.message || 'Failed to send contract offer.');
      setMessage({ kind: 'success', text: r.message || 'Contract offer sent.' });
      setContractFighterId('');
      await load();
    } catch (err) {
      setMessage({ kind: 'error', text: (err as Error).message });
    } finally {
      setSendingContract(false);
    }
  }

  if (loading) {
    return (
      <div>
        <PageHeader title="Manage Promotion" icon={Building2} />
        <Card><div className="p-8 text-center text-ink-500 text-sm flex items-center justify-center gap-2">
          <Spinner /> Loading...
        </div></Card>
      </div>
    );
  }

  if (!promotion) {
    return (
      <div className="animate-slideUp">
        <PageHeader title="Manage Promotion" subtitle="Promotion ownership required" icon={Building2} />
        <Card>
          <EmptyState
            icon={Building2}
            title="No promotion assigned"
            body="An administrator must assign the game promotion to your gym before you can schedule events and send offers."
          />
        </Card>
      </div>
    );
  }

  return (
    <div className="animate-slideUp space-y-6">
      <PageHeader
        title={promotion.name}
        subtitle={`Promotion management · Reputation ${promotion.reputation}`}
        icon={Building2}
        action={
          <Badge className={PROMOTION_TIER_COLORS[promotion.tier]}>
            {PROMOTION_TIER_NAMES[promotion.tier]}
          </Badge>
        }
      />

      {message && (
        message.kind === 'success' ? (
          <Alert variant="success">
            <span className="flex items-center gap-2"><CheckCircle2 className="w-4 h-4" /> {message.text}</span>
          </Alert>
        ) : (
          <Alert variant="error">
            <span className="flex items-center gap-2"><AlertCircle className="w-4 h-4" /> {message.text}</span>
          </Alert>
        )
      )}

      <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
        <Card>
          <CardHeader title="Schedule Event" icon={CalendarDays} />
          <form onSubmit={handleCreateEvent} className="p-4 space-y-4">
            <p className="text-xs text-ink-400">
              Events must be scheduled at least {EVENT_LEAD_WEEKS} weeks (1 month) in advance.
              Fight offers to player gyms expire after {OFFER_RESPONSE_WEEKS} weeks.
            </p>
            <div>
              <label className="label">Event Name</label>
              <input
                className="input"
                value={eventName}
                onChange={(e) => setEventName(e.target.value)}
                placeholder="e.g., Ultimate MMA 1"
                required
              />
            </div>
            <div>
              <label className="label">Extra weeks beyond minimum</label>
              <input
                type="number"
                min={0}
                className="input"
                value={extraWeeks}
                onChange={(e) => setExtraWeeks(Math.max(0, parseInt(e.target.value, 10) || 0))}
              />
              <p className="text-xs text-ink-500 mt-1">Scheduled for {formatTick(scheduledWeek)}</p>
            </div>
            <button type="submit" disabled={creatingEvent} className="btn-primary w-full">
              {creatingEvent ? <Spinner /> : <><Plus className="w-4 h-4" /> Create Event</>}
            </button>
          </form>
        </Card>

        <Card>
          <CardHeader title="Send Contract Offer" icon={Send} />
          <form onSubmit={handleSendContract} className="p-4 space-y-4">
            <p className="text-xs text-ink-400">
              Unsigned fighters auto-accept if skill is at or below promotion reputation ({promotion.reputation}).
              Player-managed fighters receive a {OFFER_RESPONSE_WEEKS}-week offer window.
            </p>
            <div>
              <label className="label">Fighter</label>
              <FighterSearchPicker
                fighters={fighters}
                value={contractFighterId}
                onChange={setContractFighterId}
                placeholder="Search fighter name or weight class..."
              />
            </div>
            <div className="grid grid-cols-2 gap-3">
              <div>
                <label className="label">Fights</label>
                <input
                  type="number"
                  min={1}
                  max={12}
                  className="input"
                  value={contractFights}
                  onChange={(e) => setContractFights(parseInt(e.target.value, 10) || 4)}
                />
              </div>
              <div>
                <label className="label">Purse / fight</label>
                <input
                  type="number"
                  min={1000}
                  step={500}
                  className="input"
                  value={contractPurse}
                  onChange={(e) => setContractPurse(parseInt(e.target.value, 10) || 5000)}
                />
              </div>
            </div>
            <button type="submit" disabled={sendingContract || !contractFighterId} className="btn-primary w-full">
              {sendingContract ? <Spinner /> : <><Send className="w-4 h-4" /> Send Contract Offer</>}
            </button>
          </form>
        </Card>
      </div>

      <Card>
        <CardHeader title="Upcoming Events" icon={Swords} />
        {events.length === 0 ? (
          <div className="p-4">
            <EmptyState icon={CalendarDays} title="No scheduled events" body="Create an event to start building fight cards." />
          </div>
        ) : (
          <div className="divide-y divide-ink-800">
            {events.map((event) => {
              const fightCount = event.fights?.length ?? 0;
              const canRun = world && world.tick_count >= event.scheduled_week;
              return (
                <div key={event.id} className="p-4 flex flex-col sm:flex-row sm:items-center justify-between gap-3">
                  <div>
                    <div className="font-display font-semibold text-ink-100">{event.name}</div>
                    <div className="text-sm text-ink-400">{formatTick(event.scheduled_week)}</div>
                    <div className="text-xs text-ink-500 mt-1">{fightCount} fight{fightCount === 1 ? '' : 's'} on card</div>
                  </div>
                  <div className="flex gap-2 items-center">
                    <button
                      className="btn-secondary text-sm"
                      onClick={() => navigate(`events/${event.id}`)}
                    >
                      Manage Card
                    </button>
                    {canRun && (
                      <Badge className="text-gold-300 bg-gold-700/30 border-gold-600/40">
                        Ready to run
                      </Badge>
                    )}
                  </div>
                </div>
              );
            })}
          </div>
        )}
      </Card>
    </div>
  );
}
