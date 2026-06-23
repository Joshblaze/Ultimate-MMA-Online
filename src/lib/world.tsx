import { createContext, useContext, useEffect, useState, useCallback, type ReactNode } from 'react';
import { supabase } from './supabase';
import type { WorldState } from './types';
import { timeUntilNextTick } from './format';

interface WorldContextValue {
  world: WorldState | null;
  loading: boolean;
  refresh: () => Promise<void>;
  tickProgress: { ms: number; percentage: number };
}

const WorldContext = createContext<WorldContextValue | undefined>(undefined);

const POLL_MS = 30000;

export function WorldProvider({ children }: { children: ReactNode }) {
  const [world, setWorld] = useState<WorldState | null>(null);
  const [loading, setLoading] = useState(true);
  const [tickProgress, setTickProgress] = useState({ ms: 0, percentage: 0 });

  const refresh = useCallback(async () => {
    const { data, error } = await supabase
      .from('world_state')
      .select('*')
      .eq('id', 1)
      .maybeSingle();
    if (error) {
      console.error('Failed to load world state:', error.message);
      return;
    }
    setWorld(data);
  }, []);

  useEffect(() => {
    refresh().finally(() => setLoading(false));

    const interval = setInterval(refresh, POLL_MS);
    const progressInterval = setInterval(() => {
      if (world?.last_tick_at) {
        setTickProgress(timeUntilNextTick(world.last_tick_at));
      }
    }, 1000);

    return () => {
      clearInterval(interval);
      clearInterval(progressInterval);
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [world?.last_tick_at, refresh]);

  return (
    <WorldContext.Provider value={{ world, loading, refresh, tickProgress }}>
      {children}
    </WorldContext.Provider>
  );
}

// eslint-disable-next-line react-refresh/only-export-components
export function useWorld(): WorldContextValue {
  const ctx = useContext(WorldContext);
  if (!ctx) throw new Error('useWorld must be used within WorldProvider');
  return ctx;
}
