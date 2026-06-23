import { createContext, useContext, useEffect, useState, useCallback, type ReactNode } from 'react';
import type { Session, User } from '@supabase/supabase-js';
import { supabase } from './supabase';
import type { Profile } from './types';

interface AuthState {
  user: User | null;
  session: Session | null;
  profile: Profile | null;
  loading: boolean;
}

interface AuthContextValue extends AuthState {
  refreshProfile: () => Promise<void>;
  signOut: () => Promise<void>;
}

const AuthContext = createContext<AuthContextValue | undefined>(undefined);

export function AuthProvider({ children }: { children: ReactNode }) {
  const [state, setState] = useState<AuthState>({
    user: null,
    session: null,
    profile: null,
    loading: true,
  });

  const loadProfile = useCallback(async (userId: string) => {
    const { data, error } = await supabase
      .from('profiles')
      .select('*')
      .eq('id', userId)
      .maybeSingle();
    if (error) {
      console.error('Failed to load profile:', error.message);
      return;
    }
    if (data) {
      setState((s) => ({ ...s, profile: data }));
    } else {
      // Create profile row for new auth user
      const { data: newProfile, error: insertError } = await supabase
        .from('profiles')
        .insert([{ id: userId, is_admin: false }] as any)
        .select()
        .maybeSingle();
      if (insertError) {
        console.error('Failed to create profile:', insertError.message);
        return;
      }
      if (newProfile) {
        setState((s) => ({ ...s, profile: newProfile }));
      }
    }
  }, []);

  useEffect(() => {
    let mounted = true;

    supabase.auth.getSession().then(({ data, error }) => {
      if (error || !mounted) {
        setState((s) => ({ ...s, loading: false }));
        return;
      }
      if (data.session) {
        setState({
          user: data.session.user,
          session: data.session,
          profile: null,
          loading: true,
        });
        loadProfile(data.session.user.id).finally(() => {
          if (mounted) setState((s) => ({ ...s, loading: false }));
          });
      } else {
        setState({ user: null, session: null, profile: null, loading: false });
      }
    });

    const { data: sub } = supabase.auth.onAuthStateChange((event, session) => {
      (async () => {
        if (event === 'SIGNED_OUT' || !session) {
          if (mounted) {
            setState({ user: null, session: null, profile: null, loading: false });
          }
          return;
        }
        if (mounted) {
          setState({
            user: session.user,
            session,
            profile: null,
            loading: true,
          });
          await loadProfile(session.user.id);
          if (mounted) setState((s) => ({ ...s, loading: false }));
        }
      })();
    });

    return () => {
      mounted = false;
      sub.subscription.unsubscribe();
    };
  }, [loadProfile]);

  const refreshProfile = useCallback(async () => {
    if (state.user) await loadProfile(state.user.id);
  }, [state.user, loadProfile]);

  const signOut = useCallback(async () => {
    await supabase.auth.signOut();
  }, []);

  return (
    <AuthContext.Provider value={{ ...state, refreshProfile, signOut }}>
      {children}
    </AuthContext.Provider>
  );
}

// eslint-disable-next-line react-refresh/only-export-components
export function useAuth(): AuthContextValue {
  const ctx = useContext(AuthContext);
  if (!ctx) throw new Error('useAuth must be used within AuthProvider');
  return ctx;
}
