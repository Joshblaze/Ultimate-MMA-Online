import { Trophy } from 'lucide-react';
import { formatRecord, ratingTier } from '../lib/format';
import { CAREER_STATUS_COLOR } from '../lib/constants';
import { areFighterStatsVisible } from '../lib/fighters';
import type { Fighter } from '../lib/types';
import { Avatar, Badge, Belt } from './ui';
import { HiddenFighterStats } from './HiddenFighterStats';

interface FighterCardProps {
  fighter: Fighter;
  onClick?: () => void;
  showGym?: boolean;
  hideStats?: boolean;
}

export function FighterCard({ fighter, onClick, hideStats }: FighterCardProps) {
  const tier = ratingTier(fighter.current_skill);

  return (
    <div
      onClick={onClick}
      className="card p-4 hover:border-ink-600 transition-colors cursor-pointer"
    >
      <div className="flex items-center gap-3">
        <div className="relative">
          <Avatar name={fighter.name} size="md" />
          {!hideStats && fighter.career_status === 'champion' && (
            <div className="absolute -bottom-1 -right-1">
              <Belt size="sm" />
            </div>
          )}
        </div>
        <div className="flex-1 min-w-0">
          <div className="flex items-center gap-2">
            <h4 className="font-semibold text-ink-100 truncate">{fighter.name}</h4>
            {!hideStats && fighter.career_status === 'champion' && (
              <Trophy className="w-3.5 h-3.5 text-gold-400 flex-shrink-0" />
            )}
          </div>
          <div className="flex items-center gap-2 text-xs text-ink-400">
            <span>{fighter.weight_class}</span>
            <span>·</span>
            <span>{fighter.country}</span>
            <span>·</span>
            <span>{fighter.age}y</span>
          </div>
        </div>
        <div className="text-right">
          {hideStats ? (
            <HiddenFighterStats compact />
          ) : (
            <>
              <div className={`font-display font-bold text-lg ${tier.color}`}>{fighter.current_skill}</div>
              <div className="text-[10px] text-ink-500 uppercase tracking-wide">{tier.label}</div>
            </>
          )}
        </div>
      </div>

      <div className="flex items-center justify-between mt-3 pt-3 border-t border-ink-800">
        <div className="text-sm font-mono text-ink-200">
          {formatRecord(fighter.wins, fighter.losses, fighter.draws)}
        </div>
        {!hideStats && (
          <Badge className={CAREER_STATUS_COLOR[fighter.career_status]}>
            {fighter.career_status}
          </Badge>
        )}
      </div>
    </div>
  );
}

interface FighterRowProps {
  fighter: Fighter;
  onClick?: () => void;
  right?: React.ReactNode;
  hideStats?: boolean;
}

export function FighterRow({ fighter, onClick, right, hideStats }: FighterRowProps) {
  const tier = ratingTier(fighter.current_skill);

  return (
    <tr
      onClick={onClick}
      className={`table-row-hover ${onClick ? '' : 'cursor-default'}`}
    >
      <td className="px-3 py-2 whitespace-nowrap">
        <div className="flex items-center gap-2.5">
          <Avatar name={fighter.name} size="sm" />
          <div className="min-w-0">
            <div className="font-medium text-ink-100 truncate flex items-center gap-1.5">
              {fighter.name}
              {!hideStats && fighter.career_status === 'champion' && (
                <Trophy className="w-3 h-3 text-gold-400 flex-shrink-0" />
              )}
            </div>
            <div className="text-xs text-ink-400">{fighter.country}</div>
          </div>
        </div>
      </td>
      <td className="px-3 py-2 whitespace-nowrap text-sm text-ink-300">{fighter.weight_class}</td>
      <td className="px-3 py-2 whitespace-nowrap text-sm text-ink-300">{fighter.age}</td>
      <td className="px-3 py-2 whitespace-nowrap text-sm font-mono text-ink-200">
        {formatRecord(fighter.wins, fighter.losses, fighter.draws)}
      </td>
      <td className="px-3 py-2 whitespace-nowrap">
        {hideStats ? (
          <HiddenFighterStats compact />
        ) : (
          <>
            <span className={`font-display font-bold text-sm ${tier.color}`}>{fighter.current_skill}</span>
            <span className="text-xs text-ink-500 ml-1">{tier.label}</span>
          </>
        )}
      </td>
      {right && <td className="px-3 py-2 whitespace-nowrap text-right">{right}</td>}
    </tr>
  );
}

export function HiddenSkillCell({
  fighter,
  gymId,
  isAdmin,
}: {
  fighter: { gym_id?: string | null; current_skill: number };
  gymId: string | null | undefined;
  isAdmin: boolean;
}) {
  if (areFighterStatsVisible(fighter, gymId, isAdmin)) {
    return <span className="font-mono text-ink-200">{fighter.current_skill}</span>;
  }

  return <HiddenFighterStats compact />;
}
