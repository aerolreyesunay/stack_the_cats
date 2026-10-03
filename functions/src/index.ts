// Stack the Cats server: every change to a player's treats, Tuna, Salmon
// and Store items happens here, so a modified app can't give itself any.
//
// One callable, `api`, takes { action, opId, ...params }. Every wallet
// change records its opId on the player (recentOps), which makes retries
// safe and lets the app match its instant on-screen balance to the saved
// one.

import { initializeApp } from 'firebase-admin/app';
import { getDatabase } from 'firebase-admin/database';
import {
  DocumentData,
  DocumentReference,
  FieldValue,
  getFirestore,
  Transaction,
} from 'firebase-admin/firestore';
import { setGlobalOptions } from 'firebase-functions/v2';
import { CallableRequest, HttpsError, onCall } from 'firebase-functions/v2/https';
import * as logger from 'firebase-functions/logger';

import * as eco from './economy';

const rtdbUrl =
  'https://stack-the-cats-9538a-default-rtdb.asia-southeast1.firebasedatabase.app';

initializeApp({ databaseURL: rtdbUrl });
setGlobalOptions({ region: 'asia-southeast1', maxInstances: 10 });

const db = getFirestore();
const rtdb = getDatabase();

/** How many recent opIds each player keeps. */
const recentOpsKept = 40;

/** How long a matched opponent has to open the match (after startAt). */
const joinWindowMs = 12000;

/** Disconnected for longer than this mid-match forfeits it. */
const forfeitAfterMs = 30000;

// ---------- Helpers ----------

function fail(code: 'invalid-argument' | 'failed-precondition' | 'not-found' | 'permission-denied', reason: string): never {
  throw new HttpsError(code, reason, { reason });
}

function str(value: unknown, name: string, max = 64): string {
  if (typeof value !== 'string' || value.length === 0 || value.length > max) {
    fail('invalid-argument', `bad-${name}`);
  }
  return value;
}

function oneOf<T extends string>(value: unknown, options: readonly T[], name: string): T {
  if (typeof value !== 'string' || !options.includes(value as T)) {
    fail('invalid-argument', `bad-${name}`);
  }
  return value as T;
}

function opIdOf(data: Record<string, unknown>): string {
  const opId = str(data.opId, 'opId');
  if (!/^[A-Za-z0-9_:-]{8,64}$/.test(opId)) fail('invalid-argument', 'bad-opId');
  return opId;
}

function int(value: unknown, fallback = 0): number {
  return typeof value === 'number' && Number.isFinite(value) ? Math.trunc(value) : fallback;
}

interface Wallet {
  treats: number;
  tuna: number;
  salmon: number;
}

function walletOf(user: DocumentData): Wallet {
  return { treats: int(user.treats), tuna: int(user.tuna), salmon: int(user.salmon) };
}

/** What a wallet operation reads and changes. [prepare] does all the reads
 * (Firestore transactions read first), then returns the player's changes,
 * other writes and the result. */
interface OpPlan<T> {
  wallet?: Partial<Wallet>; // amounts to add (negative to take)
  user?: Record<string, unknown>; // other fields on the player
  writes?: (tx: Transaction) => void;
  result: T;
}

/** Runs one wallet operation for [uid] in a transaction. Refuses anything
 * that would take a balance below zero. A repeated opId does nothing. */
async function walletOp<T>(
  uid: string,
  opId: string,
  prepare: (tx: Transaction, user: DocumentData, ref: DocumentReference) => Promise<OpPlan<T>>,
): Promise<T | { duplicate: true }> {
  const ref = db.doc(`users/${uid}`);
  return db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    if (!snap.exists) fail('failed-precondition', 'no-wallet');
    const user = snap.data()!;
    const recent: string[] = Array.isArray(user.recentOps) ? user.recentOps : [];
    if (recent.includes(opId)) return { duplicate: true as const };

    const plan = await prepare(tx, user, ref);
    const now = walletOf(user);
    const next: Wallet = {
      treats: now.treats + (plan.wallet?.treats ?? 0),
      tuna: now.tuna + (plan.wallet?.tuna ?? 0),
      salmon: now.salmon + (plan.wallet?.salmon ?? 0),
    };
    if (next.treats < 0) fail('failed-precondition', 'not-enough-treats');
    if (next.tuna < 0) fail('failed-precondition', 'not-enough-tuna');
    if (next.salmon < 0) fail('failed-precondition', 'not-enough-salmon');

    plan.writes?.(tx);
    tx.update(ref, {
      ...plan.user,
      ...next,
      recentOps: [...recent, opId].slice(-recentOpsKept),
    });
    return plan.result;
  });
}

function owns(user: DocumentData, field: 'ownedCats' | 'ownedWallpapers', id: string): boolean {
  return Array.isArray(user[field]) && user[field].includes(id);
}

/** Whether the player owns any cat of [tier] (basic cats are everyone's). */
function ownsTier(user: DocumentData, tier: eco.Tier): boolean {
  if (tier === 'basic') return true;
  const cats: string[] = Array.isArray(user.ownedCats) ? user.ownedCats : [];
  return cats.some((id) => eco.catTiers[id] === tier);
}

// ---------- Actions ----------

type Handler = (uid: string, data: Record<string, unknown>) => Promise<unknown>;

const actions: Record<string, Handler> = {
  // ----- Rewards -----

  async claimDaily(uid, data) {
    const now = Date.now();
    if (!eco.isPlausibleToday(data.today, now)) fail('invalid-argument', 'bad-today');
    const today = data.today;
    return walletOp(uid, opIdOf(data), async (_tx, user) => {
      const last = typeof user.dailyLastClaim === 'string' ? user.dailyLastClaim : null;
      // The date can only move forward.
      if (last !== null && today <= last) fail('failed-precondition', 'already-claimed');
      const status = eco.dailyStatus(last, int(user.dailyDay), today);
      if (!status.claimable) fail('failed-precondition', 'already-claimed');
      const reward = eco.dailyRewards[status.day - 1];
      return {
        wallet: reward,
        user: {
          dailyDay: status.day,
          dailyLastClaim: today,
          dailyClaimedAt: FieldValue.serverTimestamp(),
        },
        result: { ...reward, day: status.day },
      };
    });
  },

  async rewardShare(uid, data) {
    if (!eco.isPlausibleToday(data.today, Date.now())) fail('invalid-argument', 'bad-today');
    const today = data.today;
    return walletOp(uid, opIdOf(data), async (_tx, user) => {
      const count = user.shareDay === today ? int(user.shareCount) : 0;
      if (count >= eco.maxPaidSharesPerDay) fail('failed-precondition', 'daily-limit');
      return {
        wallet: { treats: eco.shareReward },
        user: { shareDay: today, shareCount: count + 1 },
        result: { reward: eco.shareReward },
      };
    });
  },

  async storeAdReward(uid, data) {
    if (!eco.isPlausibleToday(data.today, Date.now())) fail('invalid-argument', 'bad-today');
    const today = data.today;
    return walletOp(uid, opIdOf(data), async (_tx, user) => {
      const count = user.adDay === today ? int(user.adCount) : 0;
      if (count >= eco.maxStoreAdsPerDay) fail('failed-precondition', 'daily-limit');
      return {
        wallet: { treats: eco.storeAdReward },
        user: { adDay: today, adCount: count + 1 },
        result: { reward: eco.storeAdReward },
      };
    });
  },

  // ----- Store -----

  async buyCat(uid, data) {
    const catId = str(data.catId, 'catId');
    const tier = eco.catTiers[catId];
    if (!tier || tier === 'basic') fail('invalid-argument', 'bad-catId');
    return walletOp(uid, opIdOf(data), async (_tx, user) => {
      if (owns(user, 'ownedCats', catId)) fail('failed-precondition', 'already-owned');
      return {
        wallet: { treats: -eco.tierPrice[tier] },
        user: { ownedCats: FieldValue.arrayUnion(catId) },
        result: { ok: true },
      };
    });
  },

  async buyWallpaper(uid, data) {
    const id = str(data.wallpaperId, 'wallpaperId');
    const wallpaper = eco.wallpapers[id];
    if (!wallpaper || wallpaper.price === 0) fail('invalid-argument', 'bad-wallpaperId');
    return walletOp(uid, opIdOf(data), async (_tx, user) => {
      if (owns(user, 'ownedWallpapers', id)) fail('failed-precondition', 'already-owned');
      return {
        wallet: { treats: -wallpaper.price },
        user: { ownedWallpapers: FieldValue.arrayUnion(id), wallpaper: id },
        result: { ok: true },
      };
    });
  },

  /** One watched video towards a video-unlockable cat; the last one the
   * cat's tier needs unlocks it. */
  async watchCatAd(uid, data) {
    const catId = str(data.catId, 'catId');
    const tier = eco.catTiers[catId];
    if (!tier || !eco.adCats.has(catId)) fail('invalid-argument', 'bad-catId');
    return walletOp(uid, opIdOf(data), async (_tx, user) => {
      if (owns(user, 'ownedCats', catId)) fail('failed-precondition', 'already-owned');
      const watched = int(user.catAds?.[catId]) + 1;
      const unlocked = watched >= eco.adVideos[tier];
      return {
        user: {
          [`catAds.${catId}`]: watched,
          ...(unlocked ? { ownedCats: FieldValue.arrayUnion(catId) } : {}),
        },
        result: { watched, needed: eco.adVideos[tier], unlocked },
      };
    });
  },

  /** After watching a video. (Only some wallpapers, and each just once.) */
  async unlockWallpaper(uid, data) {
    const id = str(data.wallpaperId, 'wallpaperId');
    if (!eco.wallpapers[id]?.adUnlockable) fail('invalid-argument', 'bad-wallpaperId');
    return walletOp(uid, opIdOf(data), async (_tx, user) => {
      if (owns(user, 'ownedWallpapers', id)) fail('failed-precondition', 'already-owned');
      return {
        user: { ownedWallpapers: FieldValue.arrayUnion(id), wallpaper: id },
        result: { ok: true },
      };
    });
  },

  // ----- Games -----

  /** Starts a game: a normal one, the Self Challenge (which pays its
   * entry here), or this player's side of a live match (whose result is
   * then decided from the cats counted here). */
  async startGame(uid, data) {
    const mode = oneOf(data.mode, ['normal', 'self', 'match'] as const, 'mode');
    let startedAt = Date.now();
    let matchId: string | null = null;
    let gameRef = db.collection('games').doc();
    if (mode === 'match') {
      matchId = str(data.matchId, 'matchId');
      const match = (await rtdb.ref(`matches/${matchId}`).get()).val();
      if (!match?.players?.[uid]) fail('not-found', 'no-match');
      // The clock starts when the race does.
      startedAt = Math.max(startedAt, int(match.startAt, startedAt));
      gameRef = db.doc(`games/match_${matchId}_${uid}`);
    }
    // Starting a game ends any other: one account can't farm on several
    // phones at once.
    return walletOp(uid, opIdOf(data), async (tx, user) => {
      // A normal game started with an owned premium wallpaper pays double
      // treats at times.
      const wallpaperId = typeof data.wallpaperId === 'string' ? data.wallpaperId : '';
      const payoutBonus =
        mode === 'normal' &&
        eco.wallpapers[wallpaperId]?.payoutBonus === true &&
        owns(user, 'ownedWallpapers', wallpaperId);
      if (mode === 'match' && (await tx.get(gameRef)).exists) {
        return { user: { activeGame: gameRef.id }, result: { gameId: gameRef.id } };
      }
      return {
        wallet: mode === 'self' ? { treats: -eco.selfChallengeCost } : undefined,
        user: { activeGame: gameRef.id },
        writes: (t) =>
          t.create(gameRef, {
            uid,
            mode,
            matchId,
            startedAt,
            score: 0,
            combo: 0,
            ended: false,
            uses: {},
            payoutBonus,
            bonusUntil: -1,
            stats: { n: 0, perfects: 0, gaps: 0, gapSum: 0, gapSumSq: 0 },
            flagged: false,
            createdAt: FieldValue.serverTimestamp(),
          }),
        result: { gameId: gameRef.id },
      };
    });
  },

  /** Cats that landed (in order), with the perfect streak after each, the
   * cat's tier and when it landed (ms of play since the game started). The
   * server works out the treats and fish itself, within the daily limit,
   * and pays nothing for a game that looks machine-played. */
  async landings(uid, data) {
    const gameRef = db.doc(`games/${str(data.gameId, 'gameId', 100)}`);
    const list = data.landings;
    if (!Array.isArray(list) || list.length === 0 || list.length > 60) {
      fail('invalid-argument', 'bad-landings');
    }
    const now = Date.now();
    const bestRef = db.doc(`scores/${uid}`);
    const weekRef = db.doc(`weekly/${eco.weekKey(now)}/scores/${uid}`);
    return walletOp(uid, opIdOf(data), async (tx, user) => {
      const game = (await tx.get(gameRef)).data();
      if (!game || game.uid !== uid) fail('not-found', 'no-game');
      if (game.ended || (user.activeGame && user.activeGame !== gameRef.id)) {
        fail('failed-precondition', 'game-ended');
      }
      const [bestDoc, weekDoc] = await Promise.all([tx.get(bestRef), tx.get(weekRef)]);
      const allTimeBest = int(bestDoc.data()?.best);
      const weekBest = int(weekDoc.data()?.best);
      let score = int(game.score);
      let combo = int(game.combo);
      let treats = 0;
      let tuna = 0;
      let salmon = 0;
      const stats: eco.PlayStats = {
        n: int(game.stats?.n),
        perfects: int(game.stats?.perfects),
        gaps: int(game.stats?.gaps),
        gapSum: Number(game.stats?.gapSum ?? 0),
        gapSumSq: Number(game.stats?.gapSumSq ?? 0),
      };
      let lastT = int(game.lastT, -1);
      let bonusUntil = int(game.bonusUntil, -1);
      for (const landing of list) {
        const next = int(landing?.combo, -1);
        const tier = oneOf(landing?.tier, ['basic', 'special', 'exotic'] as const, 'tier');
        const t = int(landing?.t, -1);
        // A streak only grows one at a time (or starts again).
        if (next !== 0 && next !== 1 && next !== combo + 1) fail('invalid-argument', 'bad-combo');
        if (!ownsTier(user, tier)) fail('invalid-argument', 'bad-tier');
        if (t <= lastT) fail('invalid-argument', 'bad-time');
        if (lastT >= 0) {
          const gap = t - lastT;
          stats.gaps++;
          stats.gapSum += gap;
          stats.gapSumSq += gap * gap;
        }
        lastT = t;
        stats.n++;
        if (next > 0) stats.perfects++;
        combo = next;
        score++;
        if (game.mode === 'self') {
          if (score > eco.selfChallengeGoal) fail('invalid-argument', 'too-many');
          continue;
        }
        if (game.mode === 'match') continue; // matches pay at the end
        let paid = eco.treatsForLanding(combo, score, tier);
        if (game.payoutBonus === true) {
          if (t <= bonusUntil) paid *= eco.payoutBonus.multiplier;
          if (score % eco.payoutBonus.every === 0) bonusUntil = t + eco.payoutBonus.ms;
        }
        treats += paid;
        const fish = eco.fishForMilestone(score);
        if (fish === 'tuna') tuna++;
        if (fish === 'salmon') salmon++;
      }
      // No tower grows faster than a cat every minLandingMs.
      const elapsed = now - int(game.startedAt) + eco.startSlackMs;
      if (score * eco.minLandingMs > elapsed) fail('failed-precondition', 'too-fast');

      // Machine-like play: this game pays nothing more and stays off the
      // leaderboard, and the account is flagged (once per game) for review.
      const flagged = game.flagged === true || eco.looksLikeABot(stats);
      const newlyFlagged = flagged && game.flagged !== true;
      if (flagged) {
        treats = 0;
        tuna = 0;
        salmon = 0;
      }

      // The daily limit on what normal games pay.
      const today = eco.utcDay(now);
      const sameDay = user.earnDay === today;
      const earned = {
        treats: sameDay ? int(user.earnedTreats) : 0,
        tuna: sameDay ? int(user.earnedTuna) : 0,
        salmon: sameDay ? int(user.earnedSalmon) : 0,
      };
      treats = Math.max(0, Math.min(treats, eco.dailyGameCap.treats - earned.treats));
      tuna = Math.max(0, Math.min(tuna, eco.dailyGameCap.tuna - earned.tuna));
      salmon = Math.max(0, Math.min(salmon, eco.dailyGameCap.salmon - earned.salmon));

      // Cats stacked in all games (players from before this was counted
      // start from their best score).
      const lifetime =
        (user.landingsTotal === undefined ? allTimeBest : int(user.landingsTotal)) + list.length;

      // The leaderboard is written only here, from the score counted here.
      const entry = {
        uid,
        name: eco.boardName(user.displayName),
        photoUrl: typeof user.photoUrl === 'string' ? user.photoUrl : null,
        best: score,
        updatedAt: FieldValue.serverTimestamp(),
      };
      const onBoard = game.mode === 'normal' && !flagged;
      return {
        wallet: { treats, tuna, salmon },
        user: {
          landingsTotal: lifetime,
          earnDay: today,
          earnedTreats: earned.treats + treats,
          earnedTuna: earned.tuna + tuna,
          earnedSalmon: earned.salmon + salmon,
          ...(newlyFlagged
            ? { botFlags: int(user.botFlags) + 1, lastBotFlagAt: FieldValue.serverTimestamp() }
            : {}),
        },
        writes: (t) => {
          t.update(gameRef, {
            score,
            combo,
            lastAt: now,
            lastT,
            bonusUntil,
            stats: { ...stats },
            flagged,
          });
          if (onBoard && score > allTimeBest) t.set(bestRef, entry);
          if (onBoard && score > weekBest) t.set(weekRef, entry);
        },
        result: { score, treats, tuna, salmon, flagged },
      };
    });
  },

  /** Revive or realign, paid with treats, a fish or an ad, within the
   * per-game limits. Revive's price comes from the server's own score. */
  async buyUse(uid, data) {
    const gameRef = db.doc(`games/${str(data.gameId, 'gameId', 100)}`);
    const kind = oneOf(data.kind, ['revive', 'realign'] as const, 'kind');
    const payWith = oneOf(data.payWith, ['treats', 'fish', 'ad'] as const, 'payWith');
    return walletOp(uid, opIdOf(data), async (tx, user) => {
      const game = (await tx.get(gameRef)).data();
      if (!game || game.uid !== uid) fail('not-found', 'no-game');
      if (game.ended || game.mode !== 'normal') fail('failed-precondition', 'not-allowed');
      if (user.activeGame && user.activeGame !== gameRef.id) fail('failed-precondition', 'game-ended');
      const used = int(game.uses?.[kind]?.[payWith]);
      if (used >= eco.useLimits[payWith]) fail('failed-precondition', 'limit-reached');
      const cost =
        payWith === 'treats'
          ? { treats: -(kind === 'revive' ? eco.reviveCostFor(int(game.score)) : eco.realignCost) }
          : payWith === 'fish'
            ? kind === 'revive'
              ? { salmon: -1 }
              : { tuna: -1 }
            : {};
      return {
        wallet: cost,
        writes: (t) => t.update(gameRef, { [`uses.${kind}.${payWith}`]: used + 1 }),
        result: { left: eco.useLimits[payWith] - used - 1 },
      };
    });
  },

  /** Ends a game. The Self Challenge pays its Tuna and Salmon here, for
   * the score the server counted. */
  async endGame(uid, data) {
    const gameRef = db.doc(`games/${str(data.gameId, 'gameId', 100)}`);
    return walletOp(uid, opIdOf(data), async (tx) => {
      const game = (await tx.get(gameRef)).data();
      if (!game || game.uid !== uid) fail('not-found', 'no-game');
      if (game.ended) return { result: { tuna: 0, salmon: 0, already: true } };
      const reward =
        game.mode === 'self' && game.flagged !== true
          ? eco.selfChallengeReward(int(game.score))
          : { tuna: 0, salmon: 0 };
      return {
        wallet: reward,
        writes: (t) => t.update(gameRef, { ended: true, endedAt: Date.now() }),
        result: reward,
      };
    });
  },

  // ----- Friends -----

  /** Pays the inviter for each new player who joined with their code. */
  async claimReferrals(uid, data) {
    const query = db.collection('referrals').where('referrer', '==', uid).where('claimed', '==', false);
    return walletOp(uid, opIdOf(data), async (tx) => {
      const pending = await tx.get(query);
      const joiners = await Promise.all(
        pending.docs.map((d) => tx.get(db.doc(`users/${d.id}`))),
      );
      const paid: DocumentReference[] = [];
      const rejected: DocumentReference[] = [];
      pending.docs.forEach((d, i) => {
        const joiner = joiners[i].data();
        const created = joiner?.createdAt?.toMillis?.() ?? 0;
        const referred = d.data().createdAt?.toMillis?.() ?? Date.now();
        // Only genuinely new players who named this inviter...
        if (joiner?.invitedBy !== uid || referred - created >= eco.newPlayerWindowMs) {
          rejected.push(d.ref);
        } else if (int(joiner?.landingsTotal) >= eco.referralMinLandings) {
          // ...once they've really played. Until then it stays waiting.
          paid.push(d.ref);
        }
      });
      return {
        wallet: { treats: paid.length * eco.friendJoinedReward },
        writes: (t) => {
          paid.forEach((ref) => t.update(ref, { claimed: true }));
          rejected.forEach((ref) => t.update(ref, { claimed: true, rejected: true }));
        },
        result: { count: paid.length, waiting: pending.size - paid.length - rejected.length },
      };
    });
  },

  /** Pays the bonus for accepted friend requests, once per friend each. */
  async claimFriendBonuses(uid, data) {
    const query = db.collection('friendships').where('members', 'array-contains', uid);
    return walletOp(uid, opIdOf(data), async (tx) => {
      const all = await tx.get(query);
      const unclaimed = all.docs.filter((d) => {
        const f = d.data();
        return f.friendBonus === true && !(f.rewardsClaimed ?? []).includes(uid);
      });
      // Each pair of players earns the bonus once, ever: unfriending (in
      // the console) and becoming friends again pays nothing more.
      const paidRecords = await Promise.all(
        unclaimed.map((d) => tx.get(db.doc(`friendBonusPaid/${d.id}`))),
      );
      const paid = unclaimed.filter(
        (_, i) => !((paidRecords[i].data()?.paidTo ?? []) as string[]).includes(uid),
      );
      return {
        wallet: { treats: paid.length * eco.friendAcceptedReward },
        writes: (t) => {
          unclaimed.forEach((d) => t.update(d.ref, { rewardsClaimed: FieldValue.arrayUnion(uid) }));
          paid.forEach((d) =>
            t.set(
              db.doc(`friendBonusPaid/${d.id}`),
              { paidTo: FieldValue.arrayUnion(uid) },
              { merge: true },
            ),
          );
        },
        result: {
          friends: paid.map((d) => (d.data().members as string[]).find((m) => m !== uid)),
        },
      };
    });
  },

  // ----- Live matches -----

  /** Takes this player's stake as a wager match begins. */
  async joinMatch(uid, data) {
    const matchId = str(data.matchId, 'matchId');
    const match = (await rtdb.ref(`matches/${matchId}`).get()).val();
    if (!match?.players?.[uid]) fail('not-found', 'no-match');
    const stake = int(match.stake);
    if (stake === 0) return { staked: false };
    if (!eco.wagers.includes(stake)) fail('invalid-argument', 'bad-stake');
    if (match.state !== 'countdown' || Object.keys(match.players).length !== 2) {
      fail('failed-precondition', 'not-joinable');
    }
    const stakeRef = db.doc(`stakes/${matchId}_${uid}`);
    const result = await walletOp(uid, `stake:${matchId}`, async (tx, user) => {
      if ((await tx.get(stakeRef)).exists) return { result: { staked: true } };
      if (int(user.landingsTotal) < eco.wagerMinLandings) fail('failed-precondition', 'wagers-locked');
      return {
        wallet: { treats: -stake },
        writes: (t) => t.create(stakeRef, { uid, matchId, stake, at: FieldValue.serverTimestamp() }),
        result: { staked: true },
      };
    });
    await rtdb.ref(`matches/${matchId}/players/${uid}/staked`).set(true);
    return 'duplicate' in (result as object) ? { staked: true } : result;
  },

  /** Decides a match from both players' live state and pays the prizes,
   * once. Returns { decided: false } while it's still being played. */
  async settleMatch(uid, data) {
    const matchId = str(data.matchId, 'matchId');
    const match = (await rtdb.ref(`matches/${matchId}`).get()).val();
    if (!match?.players?.[uid]) fail('not-found', 'no-match');
    const uids = Object.keys(match.players);
    if (uids.length !== 2) fail('failed-precondition', 'bad-match');

    const settlementRef = db.doc(`settlements/${matchId}`);
    const existing = (await settlementRef.get()).data();
    if (existing) return mine(existing, uid);

    const now = Date.now();
    const startAt = int(match.startAt, 0);
    const players = uids.map((u) => match.players[u]);
    const bothJoined = players.every((p) => p.joined === true);
    const started = bothJoined && startAt > 0 && now >= startAt;

    let outcomes: Record<string, eco.Outcome | 'cancelled'>;
    const forfeited: Record<string, boolean> = {};
    if (!started) {
      // Called off before it began, or someone never turned up.
      const calledOff =
        ['cancelled', 'declined'].includes(match.state) ||
        (startAt > 0 && now > startAt + joinWindowMs);
      if (!calledOff) return { decided: false };
      outcomes = Object.fromEntries(uids.map((u) => [u, 'cancelled' as const]));
    } else {
      // Scores come from the cats each player's app reported to the server
      // (checked there). The live score in the database is only for show;
      // while it's ahead, the last cats may still be on their way.
      const games = await Promise.all(
        uids.map((u) => db.doc(`games/match_${matchId}_${u}`).get()),
      );
      const counted = games.map((g) => int(g.data()?.score));
      for (let i = 0; i < uids.length; i++) {
        const lastAt = int(games[i].data()?.lastAt, int(games[i].data()?.startedAt, startAt));
        if (int(players[i].score) > counted[i] && now - lastAt < 15000) {
          return { decided: false };
        }
      }
      const racers = uids.map((u, i) => {
        const p = players[i];
        const gone =
          p.connected === false && now - int(p.disconnectedAt, now) > forfeitAfterMs;
        // Machine-like play forfeits the match.
        forfeited[u] = p.left === true || gone || games[i].data()?.flagged === true;
        return { score: counted[i], alive: p.alive !== false, forfeited: forfeited[u] };
      });
      const first = eco.outcomeFor(racers[0], racers[1]);
      if (first === 'undecided') return { decided: false };
      const second = eco.outcomeFor(racers[1], racers[0]);
      outcomes = { [uids[0]]: first, [uids[1]]: second };
    }

    const settled = await db.runTransaction(async (tx) => {
      const again = await tx.get(settlementRef);
      if (again.exists) return again.data()!;
      const stakeDocs = await Promise.all(
        uids.map((u) => tx.get(db.doc(`stakes/${matchId}_${u}`))),
      );
      const staked = stakeDocs.map((d) => (d.exists ? int(d.data()!.stake) : 0));
      const bothStaked = staked.every((s) => s > 0);
      const prizes: Record<string, number> = {};
      uids.forEach((u, i) => {
        const outcome = outcomes[u];
        if (outcome === 'cancelled') {
          prizes[u] = staked[i]; // stake back
        } else if (int(match.stake) > 0) {
          // A wager only counts if both really paid in; otherwise refund.
          prizes[u] = bothStaked ? eco.prizeFor(staked[i], outcome, forfeited[u]) : staked[i];
        } else {
          prizes[u] = eco.prizeFor(0, outcome, forfeited[u]);
        }
      });
      const record = { outcomes, prizes, at: FieldValue.serverTimestamp() };
      tx.create(settlementRef, record);
      uids.forEach((u) => {
        if (prizes[u] > 0) {
          tx.update(db.doc(`users/${u}`), { treats: FieldValue.increment(prizes[u]) });
        }
      });
      return record;
    });
    await rtdb
      .ref(`matches/${matchId}/settled`)
      .set({ outcomes: settled.outcomes, prizes: settled.prizes })
      .catch(() => undefined);
    return mine(settled, uid);
  },
};

function mine(settlement: DocumentData, uid: string) {
  return {
    decided: true,
    outcome: settlement.outcomes?.[uid] ?? 'cancelled',
    prize: int(settlement.prizes?.[uid]),
  };
}

/** Turn on (ENFORCE_APP_CHECK=true in functions/.env, then deploy) once
 * the app is on Google Play: then only the real app, on a real phone, can
 * call the server. Until then calls without a valid App Check token are
 * only logged. */
const enforceAppCheck = process.env.ENFORCE_APP_CHECK === 'true';

export const api = onCall(async (request: CallableRequest<unknown>) => {
  const uid = request.auth?.uid;
  if (!uid) fail('permission-denied', 'signed-out');
  if (!request.app) {
    if (enforceAppCheck) fail('permission-denied', 'app-check');
    logger.warn('Call without a valid App Check token', { uid });
  }
  const data = (request.data ?? {}) as Record<string, unknown>;
  const action = actions[str(data.action, 'action')];
  if (!action) fail('invalid-argument', 'bad-action');
  return action(uid, data);
});
