import { Badge } from './ui';
import { rankPositionBadgeClass } from '../lib/constants';

interface PromotionRankBadgeProps {
  rankPosition: number;
  promotionName: string;
  className?: string;
}

export function PromotionRankBadge({ rankPosition, promotionName, className = '' }: PromotionRankBadgeProps) {
  return (
    <Badge className={`${rankPositionBadgeClass(rankPosition)} ${className}`.trim()}>
      #{rankPosition} · {promotionName}
    </Badge>
  );
}
