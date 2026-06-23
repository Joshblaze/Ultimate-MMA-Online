import type { WeightClass } from './types';

export const PROMOTION_TIER_NAMES: Record<number, string> = {
  1: 'Local',
  2: 'Regional',
  3: 'National',
  4: 'International',
  5: 'Elite Global',
};

export const PROMOTION_TIER_COLORS: Record<number, string> = {
  1: 'text-ink-300 bg-ink-700',
  2: 'text-forest-200 bg-forest-700/40',
  3: 'text-blue-200 bg-blue-700/40',
  4: 'text-gold-200 bg-gold-700/40',
  5: 'text-blood-200 bg-blood-700/40',
};

export const WEIGHT_CLASSES: { name: WeightClass; lbs: string }[] = [
  { name: 'Flyweight', lbs: '125' },
  { name: 'Bantamweight', lbs: '135' },
  { name: 'Featherweight', lbs: '145' },
  { name: 'Lightweight', lbs: '155' },
  { name: 'Welterweight', lbs: '170' },
  { name: 'Middleweight', lbs: '185' },
  { name: 'Light Heavyweight', lbs: '205' },
  { name: 'Heavyweight', lbs: '265' },
];

export const MONTH_NAMES = [
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December',
];

export const CAREER_STATUS_COLOR: Record<string, string> = {
  prospect: 'text-forest-300 bg-forest-700/40 border-forest-600/40',
  contender: 'text-blue-300 bg-blue-700/40 border-blue-600/40',
  champion: 'text-gold-300 bg-gold-700/40 border-gold-600/40',
  veteran: 'text-ink-300 bg-ink-700 border-ink-600',
  retired: 'text-ink-400 bg-ink-800 border-ink-700',
};

export function rankPositionTextClass(rank: number): string {
  if (rank === 1) return 'text-gold-400';
  if (rank <= 3) return 'text-gold-300';
  if (rank <= 5) return 'text-blue-300';
  return 'text-ink-400';
}

export function rankPositionBadgeClass(rank: number): string {
  if (rank === 1) return 'text-gold-300 bg-gold-700/40 border-gold-600/40';
  if (rank <= 3) return 'text-gold-200 bg-gold-800/30 border-gold-700/40';
  if (rank <= 5) return 'text-blue-300 bg-blue-700/40 border-blue-600/40';
  return 'text-ink-300 bg-ink-700 border-ink-600';
}

export const FIGHTER_COUNTRIES = [
  'USA', 'Brazil', 'Mexico', 'Canada', 'Ireland', 'England',
  'Russia', 'Dagestan', 'Poland', 'Nigeria', 'Australia',
  'Japan', 'South Korea', 'Sweden', 'France', 'Cuba',
  'Argentina', 'Germany', 'Georgia', 'Ukraine', 'Kazakhstan',
  'Suriname', 'Netherlands', 'Jamaica', 'Philippines', 'Kyrgyzstan',
];

export const FIGHTER_FIRST_NAMES = [
  'Marcus', 'Diego', 'Connor', 'Khabib', 'Israel', 'Alex', 'Tyron', 'Daniel',
  'Brock', 'Junior', 'Anthony', 'Max', 'Justin', 'Dustin', 'Charles', 'Islam',
  'Khamzat', 'Robert', 'Sean', 'Leon', 'Belal', 'Gilbert', 'Michael', 'Jorge',
  'Rafael', 'Pedro', 'Mateusz', 'Jan', 'Tom', 'Ciryl', 'Alexander', 'Shavkat',
  'Arman', 'Renato', 'Mackenzie', 'Sergei', 'Volkov', 'Petr', 'Aljamain', 'Merab',
];

export const FIGHTER_LAST_NAMES = [
  'Silva', 'Saint Pierre', 'McGregor', 'Nurmagomedov', 'Adesanya', 'Volkanovski',
  'Pereira', 'Jones', 'Cormier', 'Lesnar', 'dos Santos', 'Pettis', 'Holloway',
  'Gaethje', 'Poirier', 'Oliveira', 'Makhachev', 'Chimaev', 'Whittaker', 'Strickland',
  'Edwards', 'Muhammad', 'Burns', 'Chandler', 'Masvidal', 'Fiziev', 'Munhoz',
  'Gamrot', 'Blachowicz', 'Aspinall', 'Gane', 'Volkov', 'Ngannou', 'Yan',
  'Sterling', 'Dvalishvili', 'Sandhagen', 'Font', 'Aldo', ' Cruz',
];

export const PROMOTION_NAMES = [
  { name: 'Kingdom Combat', tier: 1 },
  { name: 'Iron Cage Federation', tier: 1 },
  { name: 'Borough Brawl', tier: 2 },
  { name: 'Pacific Rim MMA', tier: 2 },
  { name: 'Frontier Fighting', tier: 3 },
  { name: 'Continental MMA League', tier: 3 },
  { name: 'Apex Worldwide', tier: 4 },
  { name: 'Global Apex Championship', tier: 5 },
];

// 1 real hour = 1 in-game week; 4 weeks/month, 12 months/year
export const WEEKS_PER_MONTH = 4;
export const WEEKS_PER_YEAR = 48;
export const WEEK_DURATION_MS = 60 * 60 * 1000;

export const STARTING_CASH = 50000;
export const STARTING_REPUTATION = 0;
export const STARTING_CAPACITY = 10;
