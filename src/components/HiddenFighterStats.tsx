import { EyeOff } from 'lucide-react';

interface HiddenFighterStatsProps {
  compact?: boolean;
}

export function HiddenFighterStats({ compact }: HiddenFighterStatsProps) {
  if (compact) {
    return (
      <span className="text-xs text-ink-500 italic" title="Stats are hidden until you scout this fighter.">
        Hidden — scout to reveal
      </span>
    );
  }

  return (
    <div className="flex flex-col items-center justify-center text-center py-8 px-6">
      <div className="w-12 h-12 rounded-full bg-ink-800 flex items-center justify-center mb-3">
        <EyeOff className="w-5 h-5 text-ink-500" />
      </div>
      <p className="text-sm text-ink-300 font-medium">
        Stats are hidden until you scout this fighter.
      </p>
    </div>
  );
}
