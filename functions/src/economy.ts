// The game's prices and rewards, checked on the server.
//
// Keep these the same as the app's (lib/economy/treats.dart,
// lib/store/catalog.dart and lib/store/wallpapers.dart).

export type Tier = 'basic' | 'special' | 'exotic';
export type Fish = 'tuna' | 'salmon';
export type PayWith = 'treats' | 'fish' | 'ad';

// ---------- Spending ----------
export const realignCost = 250;

/** 250 for towers up to 50 cats, then 3 more for every cat above that. */
export function reviveCostFor(score: number): number {
  return 250 + 3 * Math.max(0, score - 50);
}

// ---------- Earning ----------
/** Daily sign-in rewards for day 1-7 of a streak: treats, then a Tuna on
 * day 6 and a Salmon on day 7. */
export const dailyRewards: { treats: number; tuna: number; salmon: number }[] = [
  { treats: 10, tuna: 0, salmon: 0 },
  { treats: 20, tuna: 0, salmon: 0 },
  { treats: 50, tuna: 0, salmon: 0 },
  { treats: 100, tuna: 0, salmon: 0 },
  { treats: 200, tuna: 0, salmon: 0 },
  { treats: 0, tuna: 1, salmon: 0 },
  { treats: 0, tuna: 0, salmon: 1 },
];

export const perfectStreakStart = 3;
export const perfectStreakReward = 10;
export const stackMilestone = 50;
export const stackMilestoneReward = 50;

export const shareReward = 1;
export const maxPaidSharesPerDay = 50;
export const friendJoinedReward = 200;
export const friendAcceptedReward = 5;

/** A video in the Store when short of treats, a few times a day. */
export const storeAdReward = 100;
export const maxStoreAdsPerDay = 10;

/** New players' accounts this young can earn their inviter a bonus. */
export const newPlayerWindowMs = 7 * 24 * 60 * 60 * 1000;

// ---------- Tuna and Salmon ----------
/** A Tuna every 100 cats, a Salmon instead every 200 (normal games). */
export function fishForMilestone(score: number): Fish | null {
  if (score <= 0) return null;
  if (score % 200 === 0) return 'salmon';
  if (score % 100 === 0) return 'tuna';
  return null;
}

/** Treats for a landing, given the perfect streak after it (0 if it wasn't
 * perfect), the score after it and the landed cat's tier. */
export function treatsForLanding(combo: number, score: number, tier: Tier): number {
  let earned = 0;
  const perfect = combo > 0;
  const inStreak = combo > perfectStreakStart;
  if (inStreak) {
    earned +=
      tier === 'basic'
        ? perfectStreakReward
        : tier === 'special'
          ? perfectStreakReward + 3
          : perfectStreakReward * 2;
  } else if (perfect) {
    earned += tier === 'basic' ? 0 : tier === 'special' ? 1 : 5;
  }
  if (score > 0 && score % stackMilestone === 0 && fishForMilestone(score) === null) {
    earned += stackMilestoneReward;
  }
  return earned;
}

// ---------- Revive / realign limits (per game) ----------
export const useLimits: Record<PayWith, number> = { treats: 2, fish: 3, ad: 3 };

// ---------- Self Challenge ----------
export const selfChallengeCost = 25;
export const selfChallengeGoal = 100;

export function selfChallengeReward(score: number): { tuna: number; salmon: number } {
  if (score >= selfChallengeGoal) return { tuna: 1, salmon: 1 };
  if (score >= 75) return { tuna: 0, salmon: 1 };
  if (score >= 50) return { tuna: 1, salmon: 0 };
  return { tuna: 0, salmon: 0 };
}

// ---------- Live matches ----------
export const friendlyPrizes = { win: 30, lose: 10, draw: 20 };
export const wagers = [100, 200, 300, 500];

/** A tower can't grow faster than one cat per this long. In the game each
 * cat takes at least about 0.7 s (the pause before it appears, the drop
 * and the landing), so faster claims are rejected. */
export const minLandingMs = 600;

/** A new player must stack this many cats before their inviter is paid
 * (so fresh accounts made just to enter a code earn nothing). */
export const referralMinLandings = 100;

/** Treat wagers unlock after stacking this many cats in total (so
 * throwaway accounts can't pass their welcome treats to another). */
export const wagerMinLandings = 200;

/** Allowance for a game's first cats landing before the server heard the
 * game start. */
export const startSlackMs = 8000;

// ---------- Store ----------
export const catTiers: Record<string, Tier> = {
  ginger: 'basic',
  grey: 'basic',
  black: 'special',
  white: 'special',
  cream: 'special',
  brown: 'special',
  tuxedo: 'special',
  russianBlue: 'special',
  calico: 'special',
  orangeWhite: 'special',
  silverTabby: 'special',
  siamese: 'exotic',
  bengal: 'exotic',
  scottishFold: 'exotic',
  maineCoon: 'exotic',
  sphynx: 'exotic',
  ragdoll: 'exotic',
  snowBengal: 'exotic',
};

export const tierPrice: Record<Tier, number> = { basic: 0, special: 300, exotic: 500 };

/** Cats that can also be unlocked with videos (two per paid tier), and
 * how many videos each tier takes. */
export const adCats = new Set(['tuxedo', 'orangeWhite', 'siamese', 'ragdoll']);
export const adVideos: Record<Tier, number> = { basic: 0, special: 3, exotic: 5 };

/** [payoutBonus]: premium, see payoutBonus below. */
export const wallpapers: Record<
  string,
  { price: number; adUnlockable: boolean; payoutBonus?: boolean }
> = {
  classic: { price: 0, adUnlockable: false },
  polka: { price: 100, adUnlockable: true },
  plaid: { price: 100, adUnlockable: false },
  garden: { price: 100, adUnlockable: true },
  fishy: { price: 100, adUnlockable: false },
  dusk: { price: 100, adUnlockable: false },
  paws: { price: 100, adUnlockable: true },
  hearts: { price: 100, adUnlockable: false },
  checks: { price: 100, adUnlockable: false },
  crowns: { price: 500, adUnlockable: false, payoutBonus: true },
  blossom: { price: 500, adUnlockable: false, payoutBonus: true },
};

/** Premium wallpapers: in a normal game started with one, every 50 cats
 * opens a window of 20 s of play in which landings pay double treats (not
 * fish; the daily limit still applies). */
export const payoutBonus = { every: 50, ms: 20000, multiplier: 2 };

// ---------- Daily streak ----------

/** Where a player is in the 7-day streak, as in the app's DailyStatus. */
export function dailyStatus(
  lastClaim: string | null | undefined,
  lastDay: number,
  today: string,
): { day: number; claimable: boolean } {
  if (lastClaim === today) {
    return { day: Math.min(7, Math.max(1, lastDay)), claimable: false };
  }
  const continues = lastClaim === previousDay(today) && lastDay >= 1 && lastDay < 7;
  return { day: continues ? lastDay + 1 : 1, claimable: true };
}

/** 'yyyy-mm-dd' of the day before [day]. */
export function previousDay(day: string): string {
  const [y, m, d] = day.split('-').map(Number);
  const t = new Date(Date.UTC(y, m - 1, d - 1));
  return t.toISOString().slice(0, 10);
}

/** Whether [day] ('yyyy-mm-dd', the phone's local date) can be today
 * somewhere on Earth right now (UTC-12 to UTC+14). */
export function isPlausibleToday(day: unknown, nowMs: number): day is string {
  if (typeof day !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(day)) return false;
  const earliest = new Date(nowMs - 12 * 3600 * 1000).toISOString().slice(0, 10);
  const latest = new Date(nowMs + 14 * 3600 * 1000).toISOString().slice(0, 10);
  return day >= earliest && day <= latest;
}

// ---------- Match results ----------

export type Outcome = 'undecided' | 'win' | 'lose' | 'draw';

export interface Racer {
  score: number;
  alive: boolean;
  forfeited: boolean;
}

/** Who has won, from [me]'s side. Same rules as the app's outcomeFor. */
export function outcomeFor(me: Racer, them: Racer): Outcome {
  if (me.forfeited && them.forfeited) return 'draw';
  if (them.forfeited) return 'win';
  if (me.forfeited) return 'lose';
  if (!them.alive && me.score > them.score) return 'win';
  if (!me.alive && them.score > me.score) return 'lose';
  if (!me.alive && !them.alive) {
    if (me.score > them.score) return 'win';
    if (me.score < them.score) return 'lose';
    return 'draw';
  }
  return 'undecided';
}

/** Treats a player gets for [outcome]. A wager's stakes were taken at the
 * start, so the winner gets both back and a draw returns each stake. */
export function prizeFor(stake: number, outcome: Outcome, forfeited: boolean): number {
  if (stake > 0) {
    if (outcome === 'win') return stake * 2;
    if (outcome === 'draw') return stake;
    return 0;
  }
  if (forfeited) return 0; // left the match: no consolation prize
  if (outcome === 'win') return friendlyPrizes.win;
  if (outcome === 'lose') return friendlyPrizes.lose;
  if (outcome === 'draw') return friendlyPrizes.draw;
  return 0;
}

// ---------- Leaderboard ----------

/** The weekly leaderboard's id, e.g. '2026-W40' (ISO weeks, UTC), as in
 * the app's LeaderboardWeek.key. */
export function weekKey(nowMs: number): string {
  const d = new Date(nowMs);
  const day = Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate());
  const weekday = new Date(day).getUTCDay() || 7; // Monday 1 ... Sunday 7
  const thursday = day + (4 - weekday) * 86400000;
  const year = new Date(thursday).getUTCFullYear();
  const week = Math.floor((thursday - Date.UTC(year, 0, 1)) / 86400000 / 7) + 1;
  return `${year}-W${String(week).padStart(2, '0')}`;
}

/** A name for the leaderboard (as the app shows it). */
/** Kids' mode accounts (anonymous) go by a made-up name like "Sleepy
 * Kitten 42", worked out from the account id, the same as the app's
 * KidName.forUid. */
const kidAdjectives = [
  'Sleepy', 'Fluffy', 'Happy', 'Brave', 'Tiny', 'Speedy', 'Sunny', 'Cozy',
  'Jolly', 'Snowy', 'Lucky', 'Bouncy', 'Silly', 'Clever', 'Gentle', 'Mighty',
];
const kidNouns = [
  'Kitten', 'Tabby', 'Whiskers', 'Paws', 'Mittens', 'Purrball', 'Tiger', 'Pebble',
  'Biscuit', 'Muffin', 'Noodle', 'Pumpkin', 'Socks', 'Button', 'Pudding', 'Mochi',
];

export function kidName(uid: string): string {
  // FNV-1a, 32 bits.
  let h = 2166136261;
  for (let i = 0; i < uid.length; i++) {
    h ^= uid.charCodeAt(i);
    h = Math.imul(h, 16777619) >>> 0;
  }
  return `${kidAdjectives[h % 16]} ${kidNouns[(h >>> 4) % 16]} ${10 + ((h >>> 8) % 90)}`;
}

/** How a player shows to people who aren't their friends: first name and
 * the initial of the last name ("Aerol U."). Friends see the full name
 * (from profiles). The same as the app's publicName. */
export function boardName(name: unknown): string {
  const words = typeof name === 'string' ? name.trim().split(/\s+/).filter(Boolean) : [];
  if (words.length === 0) return 'Cat stacker';
  const first = Array.from(words[0]).slice(0, 30).join('');
  if (words.length === 1) return first;
  const initial = Array.from(words[words.length - 1])[0].toUpperCase();
  return `${first} ${initial}.`;
}

// ---------- Anti-bot ----------

/** The most normal games can pay one account per day (UTC). Beyond it,
 * games still count for the leaderboard but pay nothing until tomorrow. */
export const dailyGameCap = { treats: 2000, tuna: 3, salmon: 2 };

/** A game is judged machine-played once it has this many cats and... */
export const botMinLandings = 50;
/** ...this share of them were Purrfect (people manage far fewer)... */
export const botPerfectRate = 0.9;
/** ...or the time between cats hardly varies at all (a metronome). */
export const botTimingSpread = 0.02;

/** 'yyyy-mm-dd' in UTC, for the daily game limit. */
export function utcDay(nowMs: number): string {
  return new Date(nowMs).toISOString().slice(0, 10);
}

/** Running numbers for spotting machine play in one game. */
export interface PlayStats {
  n: number; // cats
  perfects: number;
  gaps: number; // time gaps between cats measured
  gapSum: number;
  gapSumSq: number;
}

export function looksLikeABot(s: PlayStats): boolean {
  if (s.n < botMinLandings) return false;
  if (s.perfects / s.n >= botPerfectRate) return true;
  if (s.gaps < botMinLandings - 1) return false;
  const mean = s.gapSum / s.gaps;
  const variance = Math.max(0, s.gapSumSq / s.gaps - mean * mean);
  return mean > 0 && Math.sqrt(variance) / mean < botTimingSpread;
}
