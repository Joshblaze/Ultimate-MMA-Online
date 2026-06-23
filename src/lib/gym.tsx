import { createContext, useContext, useEffect, useState, useCallback, type ReactNode } from 'react';
import { supabase } from './supabase';
import { useAuth } from './auth';
import type { Gym } from './types';

interface GymContextValue {
  gym: Gym | null;
  loading: boolean;
  refresh: () => Promise<void>;
  hasGym: boolean;
  // Bumps whenever gym-owned relations (fighters, offers, etc.) change so
  // consumers that depend on those relations can refetch even when the gym
  // row itself is unchanged. Pass this in your useEffect deps.
  version: number;
  bumpVersion: () => void;
}

const GymContext = createContext<GymContextValue | undefined>(undefined);

export function GymProvider({ children }: { children: ReactNode }) {
  const { user } = useAuth();
  const [gym, setGym] = useState<Gym | null>(null);
  const [loading, setLoading] = useState(true);
  const [version, setVersion] = useState(0);

  const refresh = useCallback(async () => {
    if (!user) {
      setGym(null);
      return;
    }
    const { data, error } = await supabase
      .from('gyms')
      .select('*')
      .eq('owner_id', user.id)
      .maybeSingle();
    if (error) {
      console.error('Failed to load gym:', error.message);
      return;
    }
    setGym(data);
  }, [user]);

  // Bump the version counter to signal that gym-owned relations changed
  // (e.g. a fighter was just signed). Consumers that list those relations
  // should include `version` in their useEffect deps so they refetch.
  const bumpVersion = useCallback(() => {
    setVersion((v) => v + 1);
  }, []);

  useEffect(() => {
    if (!user) {
      setGym(null);
      setLoading(false);
      return;
    }
    setLoading(true);
    refresh().finally(() => setLoading(false));
  }, [user, refresh]);

  return (
    <GymContext.Provider value={{ gym, loading, refresh, hasGym: !!gym, version, bumpVersion }}>
      {children}
    </GymContext.Provider>
  );
}

// eslint-disable-next-line react-refresh/only-export-components
export function useGym(): GymContextValue {
  const ctx = useContext(GymContext);
  if (!ctx) throw new Error('useGym must be used within GymProvider');
  return ctx;
}
