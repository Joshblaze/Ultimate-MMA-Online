import { useEffect, useMemo, useRef, useState } from 'react';
import { Search, X } from 'lucide-react';
import type { Fighter } from '../lib/types';

type PickableFighter = Pick<Fighter, 'id' | 'name' | 'weight_class' | 'current_skill' | 'gym_id'>;

interface FighterSearchPickerProps {
  fighters: PickableFighter[];
  value: string;
  onChange: (fighterId: string) => void;
  placeholder?: string;
  excludeIds?: string[];
  maxSuggestions?: number;
}

export function FighterSearchPicker({
  fighters,
  value,
  onChange,
  placeholder = 'Search by name...',
  excludeIds = [],
  maxSuggestions = 8,
}: FighterSearchPickerProps) {
  const [query, setQuery] = useState('');
  const [open, setOpen] = useState(false);
  const rootRef = useRef<HTMLDivElement>(null);

  const selected = fighters.find((f) => f.id === value) ?? null;
  const exclude = useMemo(() => new Set(excludeIds), [excludeIds]);

  const suggestions = useMemo(() => {
    const q = query.trim().toLowerCase();
    return fighters
      .filter((f) => !exclude.has(f.id))
      .filter((f) => {
        if (!q) return true;
        return (
          f.name.toLowerCase().includes(q)
          || f.weight_class.toLowerCase().includes(q)
        );
      })
      .slice(0, maxSuggestions);
  }, [fighters, query, exclude, maxSuggestions]);

  useEffect(() => {
    function onDocClick(e: MouseEvent) {
      if (!rootRef.current?.contains(e.target as Node)) {
        setOpen(false);
      }
    }
    document.addEventListener('mousedown', onDocClick);
    return () => document.removeEventListener('mousedown', onDocClick);
  }, []);

  function selectFighter(fighter: PickableFighter) {
    onChange(fighter.id);
    setQuery('');
    setOpen(false);
  }

  function clearSelection() {
    onChange('');
    setQuery('');
    setOpen(false);
  }

  if (selected) {
    return (
      <div className="rounded-lg border border-gold-700/40 bg-gold-950/20 p-3 flex items-start justify-between gap-3">
        <div>
          <div className="font-medium text-ink-100">{selected.name}</div>
          <div className="text-xs text-ink-400 mt-0.5">
            {selected.weight_class} · Skill {selected.current_skill}
            {selected.gym_id ? ' · Player managed' : ' · Free agent'}
          </div>
        </div>
        <button
          type="button"
          onClick={clearSelection}
          className="p-1.5 rounded-md hover:bg-ink-800 text-ink-400 hover:text-ink-200"
          aria-label="Clear fighter selection"
        >
          <X className="w-4 h-4" />
        </button>
      </div>
    );
  }

  return (
    <div ref={rootRef} className="relative">
      <div className="relative">
        <Search className="absolute left-3 top-1/2 -translate-y-1/2 w-4 h-4 text-ink-500" />
        <input
          type="text"
          value={query}
          onChange={(e) => {
            setQuery(e.target.value);
            setOpen(true);
          }}
          onFocus={() => setOpen(true)}
          placeholder={placeholder}
          className="input pl-10"
          autoComplete="off"
        />
      </div>

      {open && suggestions.length > 0 && (
        <ul className="absolute z-20 mt-1 w-full max-h-56 overflow-y-auto rounded-lg border border-ink-700 bg-ink-900 shadow-lg">
          {suggestions.map((fighter) => (
            <li key={fighter.id}>
              <button
                type="button"
                onClick={() => selectFighter(fighter)}
                className="w-full text-left px-3 py-2.5 hover:bg-ink-800 transition-colors border-b border-ink-800/80 last:border-b-0"
              >
                <div className="text-sm font-medium text-ink-100">{fighter.name}</div>
                <div className="text-xs text-ink-400">
                  {fighter.weight_class} · Skill {fighter.current_skill}
                  {fighter.gym_id ? ' · Player' : ''}
                </div>
              </button>
            </li>
          ))}
        </ul>
      )}

      {open && query.trim() && suggestions.length === 0 && (
        <div className="absolute z-20 mt-1 w-full rounded-lg border border-ink-700 bg-ink-900 px-3 py-2 text-sm text-ink-500">
          No fighters match &ldquo;{query.trim()}&rdquo;
        </div>
      )}
    </div>
  );
}
