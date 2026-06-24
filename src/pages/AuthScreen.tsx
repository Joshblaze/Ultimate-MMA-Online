import { useState } from 'react';
import { Trophy, Mail, Lock, User, AlertCircle, ArrowLeft } from 'lucide-react';
import { supabase } from '../lib/supabase';
import { Spinner } from '../components/ui';

type Mode = 'login' | 'register' | 'reset';

export function AuthScreen() {
  const [mode, setMode] = useState<Mode>('login');
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [confirmPassword, setConfirmPassword] = useState('');
  const [error, setError] = useState<string | null>(null);
  const [message, setMessage] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault();
    setError(null);
    setMessage(null);

    if (mode === 'reset') {
      if (!email) return setError('Enter your email.');
      setLoading(true);
      const { error } = await supabase.auth.resetPasswordForEmail(email, {
        redirectTo: window.location.origin,
      });
      setLoading(false);
      if (error) return setError(error.message);
      setMessage('Password reset email sent. Check your inbox.');
      return;
    }

    if (!email || !password) return setError('Email and password are required.');
    if (mode === 'register' && password.length < 6)
      return setError('Password must be at least 6 characters.');
    if (mode === 'register' && password !== confirmPassword)
      return setError('Passwords do not match.');

    setLoading(true);
    if (mode === 'login') {
      const { error } = await supabase.auth.signInWithPassword({ email, password });
      if (error) {
        setLoading(false);
        return setError(error.message);
      }
    } else {
      const { data, error } = await supabase.auth.signUp({ email, password });
      if (error) {
        setLoading(false);
        return setError(error.message);
      }
      if (!data.session) {
        setLoading(false);
        setMessage('Account created. Please sign in.');
        setMode('login');
        setPassword('');
        setConfirmPassword('');
        return;
      }
    }
  }

  return (
    <div className="min-h-screen flex flex-col lg:flex-row">
      {/* Brand panel — compact strip on mobile, full hero on desktop */}
      <div className="relative lg:w-1/2 bg-gradient-to-br from-ink-950 via-ink-900 to-ink-850 flex flex-col justify-center items-center px-4 py-6 lg:px-6 lg:py-12 overflow-hidden flex-shrink-0">
        <div className="absolute inset-0 opacity-30 hidden lg:block">
          <div className="absolute top-1/4 left-1/4 w-64 h-64 bg-gold-700/20 rounded-full blur-3xl" />
          <div className="absolute bottom-1/4 right-1/4 w-72 h-72 bg-blood-700/20 rounded-full blur-3xl" />
        </div>
        <div className="relative z-10 max-w-md text-center w-full">
          <div className="flex items-center justify-center gap-3 lg:flex-col lg:gap-0">
            <div className="inline-flex items-center justify-center w-12 h-12 lg:w-20 lg:h-20 rounded-xl lg:rounded-2xl bg-gradient-to-br from-gold-500 to-gold-700 shadow-belt lg:mb-6 flex-shrink-0">
              <Trophy className="w-6 h-6 lg:w-10 lg:h-10 text-ink-950" />
            </div>
            <div className="text-left lg:text-center">
              <h1 className="font-display text-xl lg:text-4xl font-bold tracking-tight text-ink-100 lg:mb-3">
                ULTIMATE MMA
              </h1>
              <p className="font-display tracking-[0.2em] lg:tracking-[0.3em] text-gold-500 text-[10px] lg:text-sm uppercase">
                Manager Online
              </p>
            </div>
          </div>
          <p className="hidden lg:block text-ink-300 text-sm leading-relaxed mb-8 mt-6">
            Build the greatest MMA gym in a living, persistent world. Sign fighters, chase
            championships, and rise through global rankings — even while you sleep.
          </p>
          <div className="hidden lg:grid grid-cols-3 gap-4 text-center">
            <div>
              <div className="font-display text-2xl font-bold text-gold-400">1000+</div>
              <div className="text-xs text-ink-400 uppercase tracking-wide">Fighters</div>
            </div>
            <div>
              <div className="font-display text-2xl font-bold text-gold-400">5</div>
              <div className="text-xs text-ink-400 uppercase tracking-wide">Promotion Tiers</div>
            </div>
            <div>
              <div className="font-display text-2xl font-bold text-gold-400">24/7</div>
              <div className="text-xs text-ink-400 uppercase tracking-wide">Live World</div>
            </div>
          </div>
        </div>
      </div>

      {/* Form panel */}
      <div className="flex-1 lg:w-1/2 flex items-start lg:items-center justify-center px-4 py-6 sm:px-6 sm:py-8 lg:py-12">
        <div className="w-full max-w-sm card-glass p-5 sm:p-6 lg:p-0 lg:bg-transparent lg:border-0 lg:shadow-none lg:backdrop-blur-none">
          {mode === 'reset' && (
            <button
              onClick={() => setMode('login')}
              className="flex items-center gap-1.5 text-sm text-ink-400 hover:text-ink-200 mb-6 transition-colors"
            >
              <ArrowLeft className="w-4 h-4" /> Back to sign in
            </button>
          )}

          <h2 className="font-display text-xl sm:text-2xl font-bold text-ink-100 mb-1">
            {mode === 'login' ? 'Welcome Back' : mode === 'register' ? 'Create Your Account' : 'Reset Password'}
          </h2>
          <p className="text-sm text-ink-400 mb-6">
            {mode === 'login'
              ? 'Sign in to manage your MMA gym.'
              : mode === 'register'
              ? 'Start your journey as a gym owner.'
              : 'Enter your email to receive a reset link.'}
          </p>

          <form onSubmit={handleSubmit} className="space-y-4">
            <div>
              <label className="label">Email</label>
              <div className="relative">
                <Mail className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-ink-500" />
                <input
                  type="email"
                  value={email}
                  onChange={(e) => setEmail(e.target.value)}
                  className="input pl-10"
                  placeholder="you@example.com"
                  autoComplete="email"
                />
              </div>
            </div>

            {mode !== 'reset' && (
              <div>
                <label className="label">Password</label>
                <div className="relative">
                  <Lock className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-ink-500" />
                  <input
                    type="password"
                    value={password}
                    onChange={(e) => setPassword(e.target.value)}
                    className="input pl-10"
                    placeholder="••••••••"
                    autoComplete={mode === 'login' ? 'current-password' : 'new-password'}
                  />
                </div>
              </div>
            )}

            {mode === 'register' && (
              <div>
                <label className="label">Confirm Password</label>
                <div className="relative">
                  <User className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-ink-500" />
                  <input
                    type="password"
                    value={confirmPassword}
                    onChange={(e) => setConfirmPassword(e.target.value)}
                    className="input pl-10"
                    placeholder="••••••••"
                    autoComplete="new-password"
                  />
                </div>
              </div>
            )}

            {error && (
              <div className="flex items-start gap-2 text-sm text-blood-300 bg-blood-950/50 border border-blood-800/50 rounded-lg p-3">
                <AlertCircle className="w-4 h-4 flex-shrink-0 mt-0.5" />
                <span>{error}</span>
              </div>
            )}

            {message && (
              <div className="text-sm text-forest-300 bg-forest-950/50 border border-forest-800/50 rounded-lg p-3">
                {message}
              </div>
            )}

            <button
              type="submit"
              disabled={loading}
              className="btn-primary w-full py-2.5"
            >
              {loading ? (
                <>
                  <Spinner /> Please wait...
                </>
              ) : mode === 'login' ? (
                'Sign In'
              ) : mode === 'register' ? (
                'Create Account'
              ) : (
                'Send Reset Link'
              )}
            </button>
          </form>

          <div className="mt-6 text-center text-sm text-ink-400">
            {mode === 'login' && (
              <>
                <button
                  onClick={() => setMode('register')}
                  className="text-gold-400 hover:text-gold-300 font-medium"
                >
                  New here? Create an account
                </button>
                <div className="mt-2">
                  <button
                    onClick={() => setMode('reset')}
                    className="text-ink-400 hover:text-ink-200"
                  >
                    Forgot password?
                  </button>
                </div>
              </>
            )}
            {mode === 'register' && (
              <button
                onClick={() => setMode('login')}
                className="text-gold-400 hover:text-gold-300 font-medium"
              >
                Already have an account? Sign in
              </button>
            )}
          </div>
        </div>
      </div>
    </div>
  );
}
