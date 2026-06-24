import { useEffect, useState } from 'react';
import { FileText, Check, X, Trophy, Building2, AlertCircle, Swords } from 'lucide-react';
import { useGym } from '../lib/gym';
import { useWorld } from '../lib/world';
import { useAuth } from '../lib/auth';
import { Card, EmptyState, PageHeader, Spinner, Badge } from '../components/ui';
import { HiddenFighterStats } from '../components/HiddenFighterStats';
import { areFighterStatsVisible } from '../lib/fighters';
import { fetchGymOffers, callAcceptOffer, callDeclineOffer } from '../lib/queries';
import { formatMoney, formatTick } from '../lib/format';
import { PROMOTION_TIER_NAMES, PROMOTION_TIER_COLORS, rankPositionBadgeClass } from '../lib/constants';
import { navigate } from '../App';

interface OfferWithRelations {
  id: string;
  gym_id: string;
  fighter_id: string;
  opponent_fighter_id: string | null;
  promotion_id: string;
  event_id: string | null;
  purse: number;
  offer_kind: 'contract' | 'fight' | 'renewal' | 'title_shot';
  contract_fights: number;
  scheduled_week: number;
  status: string;
  offered_at_week: number;
  response_deadline_week: number;
  booking_group_id?: string | null;
  fighter?: { id: string; name: string; weight_class: string };
  opponent_fighter?: { id: string; name: string; weight_class: string; current_skill: number; gym_id?: string | null };
  opponent_rank?: number | null;
  promotion?: { id: string; name: string; tier: number };
  event?: {
    id: string;
    name: string;
    status: string;
    fights: {
      id: string;
      fighter_a_id: string;
      fighter_b_id: string;
      winner_id: string | null;
      method: string | null;
      round: number | null;
      status: string;
      completed_at_week: number | null;
    }[];
  } | null;
}

type Filter = 'pending' | 'accepted' | 'completed' | 'declined' | 'all';
type OfferArea = 'contracts' | 'fights';

function isContractAreaOffer(kind: string | undefined) {
  return kind === 'contract' || kind === 'renewal';
}

function isFightAreaOffer(kind: string | undefined) {
  return kind === 'fight' || kind === 'title_shot';
}

export function FightOffers() {
  const { gym, refresh } = useGym();
  const { world } = useWorld();
  const { profile } = useAuth();
  const [offers, setOffers] = useState<OfferWithRelations[]>([]);
  const [loading, setLoading] = useState(true);
  const [area, setArea] = useState<OfferArea>('contracts');
  const [filter, setFilter] = useState<Filter>('pending');
  const [actioning, setActioning] = useState<string | null>(null);
  const [loadError, setLoadError] = useState<string | null>(null);
  const [result, setResult] = useState<{ offerId: string; status: string; message?: string } | null>(null);

  useEffect(() => {
    if (!gym) return;
    setLoading(true);
    setLoadError(null);
    fetchGymOffers(gym.id)
      .then((data) => {
        const loaded = data as OfferWithRelations[];
        setOffers(loaded);
        const pendingContracts = loaded.filter(
          (o) => isContractAreaOffer(o.offer_kind) && o.status === 'pending',
        ).length;
        const pendingFights = loaded.filter(
          (o) => isFightAreaOffer(o.offer_kind) && o.status === 'pending',
        ).length;
        if (pendingContracts === 0 && pendingFights > 0) {
          setArea('fights');
        } else if (pendingFights === 0 && pendingContracts > 0) {
          setArea('contracts');
        }
      })
      .catch((e) => {
        console.error('Failed to load offers:', e.message);
        setLoadError(e.message);
        setOffers([]);
      })
      .finally(() => setLoading(false));
  }, [gym, world?.tick_count, world?.last_tick_at]);

  if (!gym) return null;

  async function handleAccept(offer: OfferWithRelations) {
    setActioning(offer.id);
    setResult(null);
    try {
      const r = await callAcceptOffer(offer.id);
      setResult({ offerId: offer.id, status: r.status, message: r.message });
      if (r.status === 'ok') {
        await refresh();
      }
    } catch (e) {
      setResult({ offerId: offer.id, status: 'error', message: (e as Error).message });
    } finally {
      setActioning(null);
    }
  }

  async function handleDecline(offer: OfferWithRelations) {
    setActioning(offer.id);
    setResult(null);
    try {
      const r = await callDeclineOffer(offer.id);
      setResult({ offerId: offer.id, status: r.status, message: r.message });
      if (r.status === 'ok') {
        await refresh();
      }
    } catch (e) {
      setResult({ offerId: offer.id, status: 'error', message: (e as Error).message });
    } finally {
      setActioning(null);
    }
  }

  const areaOffers = offers.filter((o) => {
    const kind = o.offer_kind || 'contract';
    return area === 'contracts' ? isContractAreaOffer(kind) : isFightAreaOffer(kind);
  });

  const filtered = areaOffers.filter((o) => {
    if (filter === 'all') return true;
    return o.status === filter;
  });

  const counts = {
    contracts: offers.filter((o) => isContractAreaOffer(o.offer_kind)).length,
    fights: offers.filter((o) => isFightAreaOffer(o.offer_kind)).length,
    pending: areaOffers.filter((o) => o.status === 'pending').length,
    accepted: areaOffers.filter((o) => o.status === 'accepted').length,
    completed: areaOffers.filter((o) => o.status === 'completed').length,
    declined: areaOffers.filter((o) => o.status === 'declined').length,
    all: areaOffers.length,
  };

  const otherTabPending = area === 'contracts'
    ? offers.filter((o) => isFightAreaOffer(o.offer_kind) && o.status === 'pending').length
    : offers.filter((o) => isContractAreaOffer(o.offer_kind) && o.status === 'pending').length;

  return (
    <div className="animate-slideUp">
      <PageHeader title="Fight Offers" subtitle="Review and respond to promotion offers" icon={FileText} />

      {loadError && (
        <div className="mb-4 flex items-start gap-2 text-sm text-blood-300 bg-blood-950/50 border border-blood-800/50 rounded-lg p-3">
          <AlertCircle className="w-4 h-4 flex-shrink-0 mt-0.5" />
          <span>Failed to load offers: {loadError}</span>
        </div>
      )}

      <div className="grid grid-cols-2 gap-2 mb-4">
        <button
          onClick={() => setArea('contracts')}
          className={`btn justify-center text-sm ${area === 'contracts' ? 'btn-primary' : 'btn-secondary'}`}
        >
          <Building2 className="w-4 h-4" /> Contract Offers
          <span className="text-xs opacity-70 ml-1">({counts.contracts})</span>
        </button>
        <button
          onClick={() => setArea('fights')}
          className={`btn justify-center text-sm ${area === 'fights' ? 'btn-primary' : 'btn-secondary'}`}
        >
          <Swords className="w-4 h-4" /> Fight Offers
          <span className="text-xs opacity-70 ml-1">({counts.fights})</span>
        </button>
      </div>

      {otherTabPending > 0 && (
        <div className="mb-4 text-sm text-gold-400">
          You have {otherTabPending} pending {area === 'contracts' ? 'fight' : 'contract'} offer
          {otherTabPending === 1 ? '' : 's'} on the other tab.
        </div>
      )}

      <div className="flex gap-2 mb-4 flex-wrap">
        {(['pending', 'accepted', 'completed', 'declined', 'all'] as Filter[]).map((f) => (
          <button
            key={f}
            onClick={() => setFilter(f)}
            className={`btn text-sm ${filter === f ? 'btn-primary' : 'btn-secondary'}`}
          >
            {f === 'all' ? 'All' : f.charAt(0).toUpperCase() + f.slice(1)}
            <span className="text-xs opacity-70 ml-1">({counts[f]})</span>
          </button>
        ))}
      </div>

      {loading ? (
        <Card><div className="p-8 text-center text-ink-500 text-sm">Loading offers...</div></Card>
      ) : filtered.length === 0 ? (
        <Card>
          <EmptyState
            icon={FileText}
            title="No offers"
            body={filter === 'pending'
              ? 'No pending offers. Your promotion owner will send contract and fight offers when booking events.'
              : `No ${filter} offers.`}
          />
        </Card>
      ) : (
        <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
          {filtered.map((offer) => {
            const fight = offer.event?.fights?.find((candidate) =>
              (candidate.fighter_a_id === offer.fighter_id
                && candidate.fighter_b_id === offer.opponent_fighter_id)
              || (candidate.fighter_a_id === offer.opponent_fighter_id
                && candidate.fighter_b_id === offer.fighter_id)
            );
            const playerWon = fight?.winner_id === offer.fighter_id;
            const isPvpBooking = Boolean(offer.booking_group_id && offer.opponent_fighter?.gym_id);
            const awaitingOpponentGym = isPvpBooking && offer.status === 'accepted' && !fight;
            const isCompleted = offer.status === 'completed';
            const offerKind = offer.offer_kind || 'contract';
            const isRenewalOffer = offerKind === 'renewal';
            const isContractOffer = offerKind === 'contract';
            const isTitleShotOffer = offerKind === 'title_shot';
            const isContractAreaOfferCard = isContractAreaOffer(offerKind);

            return (
              <Card
                key={offer.id}
                className={`overflow-hidden ${isCompleted
                  ? playerWon ? 'border-forest-700/60' : 'border-blood-800/50'
                  : ''}`}
              >
                <div className="p-4">
                <div className="flex items-start justify-between mb-3">
                  <div>
                    <div className="flex items-center gap-2 mb-1">
                      {isCompleted
                        ? <Swords className="w-4 h-4 text-ink-300" />
                        : <Trophy className="w-4 h-4 text-gold-400" />}
                      <span className="font-display font-semibold text-ink-100">
                        {isCompleted ? 'Fight Result' : isTitleShotOffer ? 'Title Shot' : isRenewalOffer ? 'Contract Renewal' : isContractOffer ? 'Contract Offer' : formatMoney(offer.purse)}
                      </span>
                    </div>
                    <Badge className={
                      offer.status === 'pending' ? 'text-gold-300 bg-gold-700/30 border-gold-600/40' :
                      awaitingOpponentGym ? 'text-gold-300 bg-gold-700/30 border-gold-600/40' :
                      offer.status === 'accepted' ? 'text-forest-300 bg-forest-700/30 border-forest-600/40' :
                      offer.status === 'completed' && playerWon ? 'text-forest-300 bg-forest-700/30 border-forest-600/40' :
                      offer.status === 'completed' ? 'text-blood-300 bg-blood-950/50 border-blood-800/50' :
                      'text-ink-400 bg-ink-800 border-ink-700'
                    }>
                      {isCompleted ? (playerWon ? 'Win' : 'Loss') : awaitingOpponentGym ? 'Awaiting opponent' : offer.status}
                    </Badge>
                  </div>
                  <div className="text-right">
                    <div className="text-xs text-ink-500 uppercase tracking-wide">
                      {isCompleted ? 'Completed' : offer.status === 'pending' ? 'Respond by' : isContractAreaOfferCard ? 'First Fight' : 'Scheduled'}
                    </div>
                    <div className="text-sm text-ink-200 font-mono">
                      {formatTick(
                        fight?.completed_at_week
                        ?? (offer.status === 'pending' ? offer.response_deadline_week : offer.scheduled_week)
                      )}
                    </div>
                    {offer.status === 'pending' && world && (
                      <div className="text-[10px] text-gold-400 mt-0.5">
                        {Math.max(0, offer.response_deadline_week - world.tick_count)} week
                        {Math.max(0, offer.response_deadline_week - world.tick_count) === 1 ? '' : 's'} left
                      </div>
                    )}
                  </div>
                </div>

                {isCompleted && (
                  <div className={`mb-4 rounded-lg border p-3 ${
                    playerWon
                      ? 'bg-forest-950/40 border-forest-700/40'
                      : 'bg-blood-950/30 border-blood-800/40'
                  }`}>
                    <div className={`font-display text-lg font-semibold ${
                      playerWon ? 'text-forest-300' : 'text-blood-300'
                    }`}>
                      {playerWon ? 'Victory' : 'Defeat'}
                    </div>
                    <div className="text-sm text-ink-200 mt-1">
                      {fight?.method
                        ? `${fight.method}${fight.round ? ` · Round ${fight.round}` : ''}`
                        : 'Result unavailable'}
                    </div>
                    {offer.event && (
                      <button
                        className="text-xs text-gold-400 hover:text-gold-300 mt-2"
                        onClick={() => navigate(`events/${offer.event!.id}`)}
                      >
                        View {offer.event.name}
                      </button>
                    )}
                  </div>
                )}

                <div className="space-y-2 text-sm">
                  <div className="flex items-center gap-2">
                    <span className={`badge ${offer.fighter ? 'text-gold-300 bg-gold-700/20 border-gold-600/30' : ''}`}>
                      Your Fighter
                    </span>
                    <button
                      className="text-ink-100 hover:text-gold-300"
                      onClick={() => offer.fighter && navigate(`fighter/${offer.fighter.id}`)}
                    >
                      {offer.fighter?.name || 'Unknown'}
                    </button>
                    <span className="text-ink-500 text-xs">{offer.fighter?.weight_class}</span>
                  </div>
                  <div className="flex items-center gap-2 flex-wrap">
                    <span className="badge text-ink-400 bg-ink-800 border-ink-700">Opponent</span>
                    {offer.opponent_fighter ? (
                      <>
                        <button
                          className="text-ink-200 hover:text-gold-300"
                          onClick={() => navigate(`fighter/${offer.opponent_fighter!.id}`)}
                        >
                          {offer.opponent_fighter.name}
                        </button>
                        {offer.opponent_rank != null && offer.promotion && (
                          <Badge className={rankPositionBadgeClass(offer.opponent_rank)}>
                            #{offer.opponent_rank} · {offer.promotion.name}
                          </Badge>
                        )}
                        <span className="text-ink-500 text-xs">
                          {areFighterStatsVisible(
                            offer.opponent_fighter,
                            gym.id,
                            profile?.is_admin ?? false
                          )
                            ? `Skill ${offer.opponent_fighter.current_skill}`
                            : <HiddenFighterStats compact />}
                        </span>
                      </>
                    ) : (
                      <span className="text-ink-400 text-sm">Contract only — no opponent yet</span>
                    )}
                  </div>
                  <div className="flex items-center gap-2 pt-2 border-t border-ink-800">
                    <Building2 className="w-3.5 h-3.5 text-ink-500" />
                    <button
                      className="text-ink-200 hover:text-gold-300"
                      onClick={() => offer.promotion && navigate(`promotion/${offer.promotion.id}`)}
                    >
                      {offer.promotion?.name || 'Promotion'}
                    </button>
                    {offer.promotion && (
                      <Badge className={PROMOTION_TIER_COLORS[offer.promotion.tier]}>
                        {PROMOTION_TIER_NAMES[offer.promotion.tier]}
                      </Badge>
                    )}
                  </div>
                  {offer.status === 'pending' && (
                    <div className="text-xs text-ink-400 bg-ink-900 border border-ink-800 rounded-lg p-2">
                      {isTitleShotOffer ? (
                        <>
                          Your fighter broke into the top 5 and earns a championship shot vs{' '}
                          {offer.opponent_fighter?.name || 'the champion'}. Accept to book the title fight on{' '}
                          {offer.promotion?.name || 'this promotion'}.
                        </>
                      ) : isRenewalOffer ? (
                        <>
                          Your fighter&apos;s contract with {offer.promotion?.name || 'this promotion'} has ended.
                          Accept to renew for {offer.contract_fights} fights and book the next bout, or decline to
                          release them as a free agent.
                        </>
                      ) : isContractOffer ? (
                        <>
                          Accepting signs an exclusive {offer.contract_fights}-fight contract with{' '}
                          {offer.promotion?.name || 'this promotion'}.
                          {offer.opponent_fighter ? ' The first fight will be booked on acceptance.' : ''}
                        </>
                      ) : isPvpBooking ? (
                        <>
                          Both gyms must accept this bout before it is added to the card. Declining or letting the
                          offer expire cancels the linked opponent offer as well.
                        </>
                      ) : (
                        <>
                          This fight is under the current exclusive contract with{' '}
                          {offer.promotion?.name || 'this promotion'}. {offer.contract_fights} fight
                          {offer.contract_fights === 1 ? '' : 's'} remaining before this bout.
                        </>
                      )}
                    </div>
                  )}
                  {awaitingOpponentGym && (
                    <div className="text-xs text-gold-300 bg-gold-950/30 border border-gold-800/40 rounded-lg p-2">
                      You accepted this bout. Waiting for the opponent gym to accept before it is booked on the card.
                    </div>
                  )}
                </div>

                {offer.status === 'pending' && (
                  <div className="flex gap-2 mt-4 pt-4 border-t border-ink-800">
                    <button
                      onClick={() => handleAccept(offer)}
                      disabled={actioning === offer.id}
                      className="btn-success flex-1 text-sm"
                    >
                      {actioning === offer.id ? <Spinner /> : <><Check className="w-4 h-4" /> Accept</>}
                    </button>
                    <button
                      onClick={() => handleDecline(offer)}
                      disabled={actioning === offer.id}
                      className="btn-danger flex-1 text-sm"
                    >
                      <X className="w-4 h-4" /> Decline
                    </button>
                  </div>
                )}
                </div>
              </Card>
            );
          })}
        </div>
      )}

      {result && result.status !== 'ok' && (
        <div className="mt-3 flex items-start gap-2 text-sm text-blood-300 bg-blood-950/50 border border-blood-800/50 rounded-lg p-3">
          <AlertCircle className="w-4 h-4 flex-shrink-0 mt-0.5" />
          <span>{result.message}</span>
        </div>
      )}
    </div>
  );
}
