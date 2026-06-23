import { Trophy } from 'lucide-react';

export function LoadingScreen() {
  return (
    <div className="flex flex-col items-center justify-center min-h-screen gap-4">
      <div className="relative">
        <div className="absolute inset-0 blur-2xl bg-gold-600/40 rounded-full" />
        <Trophy className="relative w-16 h-16 text-gold-500 animate-pulse" />
      </div>
      <div className="text-ink-300 font-display tracking-widest uppercase text-sm">
        Loading
      </div>
      <div className="flex gap-1.5">
        <span className="w-2 h-2 rounded-full bg-gold-500 animate-bounce" style={{ animationDelay: '0ms' }} />
        <span className="w-2 h-2 rounded-full bg-gold-500 animate-bounce" style={{ animationDelay: '150ms' }} />
        <span className="w-2 h-2 rounded-full bg-gold-500 animate-bounce" style={{ animationDelay: '300ms' }} />
      </div>
    </div>
  );
}
