// Runs against the Firebase emulators:
//   firebase emulators:exec --only auth,functions,firestore,database "node --test functions/test/"
import assert from 'node:assert/strict';
import { before, describe, test } from 'node:test';

import { initializeApp } from 'firebase-admin/app';
import { getDatabase } from 'firebase-admin/database';
import { getFirestore } from 'firebase-admin/firestore';

const project = 'stack-the-cats-9538a';
const rtdbUrl = 'https://stack-the-cats-9538a-default-rtdb.asia-southeast1.firebasedatabase.app';
const fnUrl = `http://127.0.0.1:5001/${project}/asia-southeast1/api`;
const firestoreRest = `http://127.0.0.1:8080/v1/projects/${project}/databases/(default)/documents`;

process.env.FIRESTORE_EMULATOR_HOST ??= '127.0.0.1:8080';
process.env.FIREBASE_DATABASE_EMULATOR_HOST ??= '127.0.0.1:9000';
process.env.FIREBASE_AUTH_EMULATOR_HOST ??= '127.0.0.1:9099';

initializeApp({ projectId: project, databaseURL: rtdbUrl });
const db = getFirestore();
const rtdb = getDatabase();

let opCounter = 0;
const op = () => `test-op-${Date.now()}-${opCounter++}`;
const today = new Date().toISOString().slice(0, 10);

async function newPlayer(treats = 300) {
  const res = await fetch(
    'http://127.0.0.1:9099/identitytoolkit.googleapis.com/v1/accounts:signUp?key=fake',
    {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({ email: `p${Date.now()}${opCounter++}@test.dev`, password: 'secret12', returnSecureToken: true }),
    },
  );
  const { idToken, localId } = await res.json();
  await db.doc(`users/${localId}`).set({ treats, dailyDay: 0, dailyLastClaim: null, createdAt: new Date() });
  const call = async (action, params = {}) => {
    const r = await fetch(fnUrl, {
      method: 'POST',
      headers: { 'content-type': 'application/json', authorization: `Bearer ${idToken}` },
      body: JSON.stringify({ data: { action, opId: op(), ...params } }),
    });
    const body = await r.json();
    if (body.error) {
      const err = new Error(body.error.details?.reason ?? body.error.message);
      err.reason = body.error.details?.reason ?? body.error.message;
      throw err;
    }
    return body.result;
  };
  const wallet = async () => (await db.doc(`users/${localId}`).get()).data();
  return { uid: localId, idToken, call, wallet };
}

const rejects = (promise, reason) => assert.rejects(promise, (e) => e.reason === reason);

describe('wallet', () => {
  test('daily reward once a day', async () => {
    const p = await newPlayer();
    assert.deepEqual(await p.call('claimDaily', { today }), { reward: 10, day: 1 });
    await rejects(p.call('claimDaily', { today }), 'already-claimed');
    assert.equal((await p.wallet()).treats, 310);
  });

  test('a repeated opId is applied once', async () => {
    const p = await newPlayer();
    const opId = op();
    for (let i = 0; i < 2; i++) {
      await fetch(fnUrl, {
        method: 'POST',
        headers: { 'content-type': 'application/json', authorization: `Bearer ${p.idToken}` },
        body: JSON.stringify({ data: { action: 'storeAdReward', opId, today } }),
      });
    }
    assert.equal((await p.wallet()).treats, 400);
  });

  test('store video capped per day', async () => {
    const p = await newPlayer(0);
    for (let i = 0; i < 10; i++) await p.call('storeAdReward', { today });
    await rejects(p.call('storeAdReward', { today }), 'daily-limit');
    assert.equal((await p.wallet()).treats, 1000);
  });

  test('buying needs enough treats and can only happen once', async () => {
    const p = await newPlayer(350);
    await p.call('buyCat', { catId: 'siamese' });
    await rejects(p.call('buyCat', { catId: 'siamese' }), 'already-owned');
    await rejects(p.call('buyCat', { catId: 'bengal' }), 'not-enough-treats');
    await rejects(p.call('buyCat', { catId: 'ginger' }), 'bad-catId');
    const w = await p.wallet();
    assert.equal(w.treats, 50);
    assert.deepEqual(w.ownedCats, ['siamese']);
  });

  test('wallpaper by ad only for ad wallpapers', async () => {
    const p = await newPlayer(0);
    await p.call('unlockWallpaper', { wallpaperId: 'polka' });
    await rejects(p.call('unlockWallpaper', { wallpaperId: 'plaid' }), 'bad-wallpaperId');
    assert.equal((await p.wallet()).wallpaper, 'polka');
  });

  test('exchange needs a fish', async () => {
    const p = await newPlayer(0);
    await rejects(p.call('exchangeFish', { fish: 'tuna' }), 'not-enough-tuna');
    await db.doc(`users/${p.uid}`).update({ salmon: 1 });
    await p.call('exchangeFish', { fish: 'salmon' });
    const w = await p.wallet();
    assert.equal(w.treats, 375);
    assert.equal(w.salmon, 0);
  });
});

/** Pretends the game started [ms] ago, so landings aren't "too fast". */
const ageGame = (gameId, ms) => db.doc(`games/${gameId}`).update({ startedAt: Date.now() - ms });
// When each cat landed: 0.7-1.1 s apart, like a person playing.
let clock = 0;
const basic = (combo) => ({ combo, tier: 'basic', t: (clock += 700 + Math.floor(Math.random() * 400)) });

describe('games', () => {
  test('landings pay the same treats as the app, plus fish', async () => {
    const p = await newPlayer(0);
    const { gameId } = await p.call('startGame', { mode: 'normal' });
    await ageGame(gameId, 120000);
    // 50 plain landings: the 50-cat milestone (50 treats).
    await p.call('landings', { gameId, landings: Array.from({ length: 50 }, () => basic(0)) });
    // 50 more, the last 5 perfect: streak pays 10 at combo 4 and 5; the
    // 100th cat gives a Tuna instead of 50 treats.
    const more = Array.from({ length: 45 }, () => basic(0));
    for (let c = 1; c <= 5; c++) more.push(basic(c));
    const r = await p.call('landings', { gameId, landings: more });
    assert.deepEqual(r, { score: 100, treats: 20, tuna: 1, salmon: 0, flagged: false });
    const w = await p.wallet();
    assert.equal(w.treats, 70);
    assert.equal(w.tuna, 1);
  });

  test('impossible streaks, unowned tiers and speed are refused', async () => {
    const p = await newPlayer(0);
    const { gameId } = await p.call('startGame', { mode: 'normal' });
    await rejects(p.call('landings', { gameId, landings: [basic(5)] }), 'bad-combo');
    await rejects(p.call('landings', { gameId, landings: [{ combo: 0, tier: 'exotic' }] }), 'bad-tier');
    await rejects(
      p.call('landings', { gameId, landings: Array.from({ length: 60 }, () => basic(0)) }),
      'too-fast',
    );
  });

  test('revive limits and price from the server score', async () => {
    const p = await newPlayer(2000);
    const { gameId } = await p.call('startGame', { mode: 'normal' });
    await ageGame(gameId, 120000);
    await p.call('landings', { gameId, landings: Array.from({ length: 60 }, () => basic(0)) });
    // 60 cats: 280 per revive; 50 treats were earned at 50 cats.
    await p.call('buyUse', { gameId, kind: 'revive', payWith: 'treats' });
    await p.call('buyUse', { gameId, kind: 'revive', payWith: 'treats' });
    await rejects(p.call('buyUse', { gameId, kind: 'revive', payWith: 'treats' }), 'limit-reached');
    for (let i = 0; i < 3; i++) await p.call('buyUse', { gameId, kind: 'realign', payWith: 'ad' });
    await rejects(p.call('buyUse', { gameId, kind: 'realign', payWith: 'ad' }), 'limit-reached');
    await rejects(p.call('buyUse', { gameId, kind: 'realign', payWith: 'fish' }), 'not-enough-tuna');
    assert.equal((await p.wallet()).treats, 2000 + 50 - 2 * 280);
  });

  test('self challenge: entry fee and reward at the end', async () => {
    const p = await newPlayer(100);
    const { gameId } = await p.call('startGame', { mode: 'self' });
    await ageGame(gameId, 120000);
    await p.call('landings', { gameId, landings: Array.from({ length: 60 }, () => basic(0)) });
    await p.call('landings', { gameId, landings: Array.from({ length: 20 }, () => basic(0)) });
    await rejects(p.call('buyUse', { gameId, kind: 'revive', payWith: 'ad' }), 'not-allowed');
    assert.deepEqual(await p.call('endGame', { gameId }), { tuna: 0, salmon: 1 });
    await p.call('endGame', { gameId }); // twice pays once
    const w = await p.wallet();
    assert.equal(w.treats, 75); // no treats from landings
    assert.equal(w.salmon, 1);
    assert.equal(w.tuna ?? 0, 0);
  });
});

describe('anti-bot', () => {
  test('normal games pay at most the daily limit', async () => {
    const p = await newPlayer(0);
    await db.doc(`users/${p.uid}`).update({
      earnDay: today,
      earnedTreats: 1995,
      earnedTuna: 3,
    });
    const { gameId } = await p.call('startGame', { mode: 'normal' });
    await ageGame(gameId, 120000);
    // 100 cats: 50 treats at 50 cats and a Tuna at 100.
    const first = await p.call('landings', { gameId, landings: Array.from({ length: 50 }, () => basic(0)) });
    assert.equal(first.treats, 5);
    const r = await p.call('landings', { gameId, landings: Array.from({ length: 50 }, () => basic(0)) });
    assert.equal(r.tuna, 0);
    const w = await p.wallet();
    assert.equal(w.treats, 5);
    assert.equal(w.earnedTreats, 2000);
    // Still on the leaderboard.
    assert.equal((await db.doc(`scores/${p.uid}`).get()).data().best, 100);
  });

  test('nearly all Purrfect: the game pays nothing and is flagged', async () => {
    const p = await newPlayer(0);
    const { gameId } = await p.call('startGame', { mode: 'normal' });
    await ageGame(gameId, 120000);
    const perfect = Array.from({ length: 60 }, (_, i) => basic(i + 1));
    const r = await p.call('landings', { gameId, landings: perfect });
    assert.equal(r.flagged, true);
    assert.equal(r.treats, 0);
    const w = await p.wallet();
    assert.equal(w.treats, 0);
    assert.equal(w.botFlags, 1);
    assert.equal((await db.doc(`scores/${p.uid}`).get()).exists, false);
  });

  test('tapping like a metronome is flagged', async () => {
    const p = await newPlayer(0);
    const { gameId } = await p.call('startGame', { mode: 'normal' });
    await ageGame(gameId, 120000);
    const start = clock;
    const steady = Array.from({ length: 60 }, (_, i) => ({ combo: 0, tier: 'basic', t: start + (i + 1) * 800 }));
    clock = start + 61 * 800;
    assert.equal((await p.call('landings', { gameId, landings: steady })).flagged, true);
  });

  test('a real player is not flagged', async () => {
    const p = await newPlayer(0);
    const { gameId } = await p.call('startGame', { mode: 'normal' });
    await ageGame(gameId, 120000);
    // A third Purrfect, in short streaks.
    const mixed = Array.from({ length: 90 }, (_, i) => basic(i % 3 === 2 ? 1 : 0));
    const r = await p.call('landings', { gameId, landings: mixed.slice(0, 60) });
    assert.equal(r.flagged, false);
    assert.equal((await p.call('landings', { gameId, landings: mixed.slice(60) })).flagged, false);
  });

  test('only the newest game on an account can earn', async () => {
    const p = await newPlayer(0);
    const first = await p.call('startGame', { mode: 'normal' });
    await ageGame(first.gameId, 120000);
    const second = await p.call('startGame', { mode: 'normal' });
    await rejects(
      p.call('landings', { gameId: first.gameId, landings: [basic(0)] }),
      'game-ended',
    );
    await ageGame(second.gameId, 120000);
    await p.call('landings', { gameId: second.gameId, landings: [basic(0)] });
  });
});

describe('matches', () => {
  async function match(a, b, stake, startedAgoMs = 60000) {
    const ref = rtdb.ref('matches').push();
    const player = (name) => ({ name, score: 0, alive: true, joined: true, connected: true, left: false });
    await ref.set({
      seed: 1,
      state: 'countdown',
      stake,
      startAt: Date.now() - startedAgoMs,
      players: { [a.uid]: player('A'), [b.uid]: player('B') },
    });
    return ref;
  }

  /** [p] stacks [cats] in the match (reported to the server), then shows
   * [shown] as their live score and maybe falls. */
  async function race(p, ref, cats, { fell = false, shown = cats } = {}) {
    const { gameId } = await p.call('startGame', { mode: 'match', matchId: ref.key });
    await ageGame(gameId, 60000);
    if (cats > 0) {
      await p.call('landings', { gameId, landings: Array.from({ length: cats }, () => basic(0)) });
    }
    await ref.child(`players/${p.uid}`).update({ score: shown, alive: !fell });
  }

  /** A player with enough cats stacked to wager. */
  const veteran = async (treats) => {
    const p = await newPlayer(treats);
    await db.doc(`users/${p.uid}`).update({ landingsTotal: 500 });
    return p;
  };

  test('wager: both stake, winner takes both, settled once', async () => {
    const a = await veteran(300);
    const b = await veteran(300);
    const ref = await match(a, b, 200);
    await a.call('joinMatch', { matchId: ref.key });
    await a.call('joinMatch', { matchId: ref.key }); // no double stake
    await b.call('joinMatch', { matchId: ref.key });
    assert.equal((await a.wallet()).treats, 100);
    assert.deepEqual(await a.call('settleMatch', { matchId: ref.key }), { decided: false });
    await race(a, ref, 12, { fell: true });
    await race(b, ref, 13);
    const [ra, rb] = await Promise.all([
      a.call('settleMatch', { matchId: ref.key }),
      b.call('settleMatch', { matchId: ref.key }),
    ]);
    assert.deepEqual(ra, { decided: true, outcome: 'lose', prize: 0 });
    assert.deepEqual(rb, { decided: true, outcome: 'win', prize: 400 });
    assert.equal((await a.wallet()).treats, 100);
    assert.equal((await b.wallet()).treats, 500);
  });

  test('wagers are locked until 200 cats are stacked', async () => {
    const a = await newPlayer(300);
    const b = await veteran(300);
    const ref = await match(a, b, 100);
    await rejects(a.call('joinMatch', { matchId: ref.key }), 'wagers-locked');
    assert.equal((await a.wallet()).treats, 300);
  });

  test('a faked live score is ignored', async () => {
    const a = await newPlayer(0);
    const b = await newPlayer(0);
    const ref = await match(a, b, 0);
    await race(a, ref, 20, { fell: true });
    // b reported 5 cats to the server but shows 999 and falls.
    await race(b, ref, 5, { fell: true, shown: 999 });
    // While b's shown score is ahead, the server waits for the last cats...
    assert.deepEqual(await a.call('settleMatch', { matchId: ref.key }), { decided: false });
    // ...but not for ever.
    await db.doc(`games/match_${ref.key}_${b.uid}`).update({ lastAt: Date.now() - 20000 });
    const r = await a.call('settleMatch', { matchId: ref.key });
    assert.deepEqual(r, { decided: true, outcome: 'win', prize: 30 });
    assert.equal((await b.wallet()).treats, 10);
  });

  test('wager with an opponent who never paid is refunded', async () => {
    const a = await veteran(300);
    const b = await veteran(300);
    const ref = await match(a, b, 100);
    await a.call('joinMatch', { matchId: ref.key });
    await ref.child(`players/${b.uid}`).update({ left: true, alive: false });
    const r = await a.call('settleMatch', { matchId: ref.key });
    assert.equal(r.outcome, 'win');
    assert.equal(r.prize, 100);
    assert.equal((await a.wallet()).treats, 300);
  });

  test('a no-show gets the stake back', async () => {
    const a = await veteran(300);
    const b = await veteran(300);
    const ref = await match(a, b, 100, 20000);
    await a.call('joinMatch', { matchId: ref.key });
    await ref.child(`players/${b.uid}/joined`).set(false);
    const r = await a.call('settleMatch', { matchId: ref.key });
    assert.deepEqual(r, { decided: true, outcome: 'cancelled', prize: 100 });
    assert.equal((await a.wallet()).treats, 300);
  });

  test('friendly prizes; leaving forfeits the consolation', async () => {
    const a = await newPlayer(0);
    const b = await newPlayer(0);
    const ref = await match(a, b, 0);
    await race(a, ref, 3, { fell: true });
    await ref.child(`players/${b.uid}`).update({ left: true, alive: false });
    const r = await a.call('settleMatch', { matchId: ref.key });
    assert.deepEqual(r, { decided: true, outcome: 'win', prize: 30 });
    assert.equal((await b.wallet()).treats, 0);
  });
});

describe('leaderboard and invites', () => {
  test('the server writes the best score from the cats it counted', async () => {
    const p = await newPlayer(0);
    await db.doc(`users/${p.uid}`).update({ displayName: 'Tester' });
    const { gameId } = await p.call('startGame', { mode: 'normal' });
    await ageGame(gameId, 120000);
    await p.call('landings', { gameId, landings: Array.from({ length: 30 }, () => basic(0)) });
    const best = (await db.doc(`scores/${p.uid}`).get()).data();
    assert.equal(best.best, 30);
    assert.equal(best.name, 'Tester');
    assert.equal((await p.wallet()).landingsTotal, 30);
  });

  test('a pair of friends earns the bonus once, even if re-friended', async () => {
    const a = await newPlayer(0);
    const b = await newPlayer(0);
    const pair = [a.uid, b.uid].sort();
    const ref = db.doc(`friendships/${pair.join('_')}`);
    const befriend = () =>
      ref.set({ members: pair, friendBonus: true, rewardsClaimed: [], createdAt: new Date() });
    await befriend();
    assert.equal((await a.call('claimFriendBonuses')).friends.length, 1);
    // Unfriended in the console, then friends again.
    await ref.delete();
    await befriend();
    assert.equal((await a.call('claimFriendBonuses')).friends.length, 0);
    assert.equal((await a.wallet()).treats, 5);
    // The other player still gets their one bonus.
    assert.equal((await b.call('claimFriendBonuses')).friends.length, 1);
  });

  test('the inviter is paid only once the new player has stacked 100 cats', async () => {
    const inviter = await newPlayer(0);
    const joiner = await newPlayer(0);
    await db.doc(`users/${joiner.uid}`).update({ invitedBy: inviter.uid });
    await db.doc(`referrals/${joiner.uid}`).set({
      referrer: inviter.uid,
      code: 'ABCDEF',
      claimed: false,
      createdAt: new Date(),
    });
    assert.equal((await inviter.call('claimReferrals')).count, 0);
    await db.doc(`users/${joiner.uid}`).update({ landingsTotal: 100 });
    assert.equal((await inviter.call('claimReferrals')).count, 1);
    assert.equal((await inviter.call('claimReferrals')).count, 0);
    assert.equal((await inviter.wallet()).treats, 200);
  });
});

describe('rules', () => {
  test('the app cannot write the leaderboard', async () => {
    const p = await newPlayer(300);
    const res = await fetch(`${firestoreRest}/scores/${p.uid}`, {
      method: 'PATCH',
      headers: { 'content-type': 'application/json', authorization: `Bearer ${p.idToken}` },
      body: JSON.stringify({ fields: { uid: { stringValue: p.uid }, best: { integerValue: '9999' } } }),
    });
    assert.equal(res.status, 403);
  });

  test('the app cannot change its own treats', async () => {
    const p = await newPlayer(300);
    const res = await fetch(
      `${firestoreRest}/users/${p.uid}?updateMask.fieldPaths=treats`,
      {
        method: 'PATCH',
        headers: { 'content-type': 'application/json', authorization: `Bearer ${p.idToken}` },
        body: JSON.stringify({ fields: { treats: { integerValue: '99999' } } }),
      },
    );
    assert.equal(res.status, 403);
  });

  test('the app can still pick a wallpaper it owns', async () => {
    const p = await newPlayer(300);
    const patch = (id) =>
      fetch(`${firestoreRest}/users/${p.uid}?updateMask.fieldPaths=wallpaper`, {
        method: 'PATCH',
        headers: { 'content-type': 'application/json', authorization: `Bearer ${p.idToken}` },
        body: JSON.stringify({ fields: { wallpaper: { stringValue: id } } }),
      });
    assert.equal((await patch('plaid')).status, 403);
    await p.call('buyWallpaper', { wallpaperId: 'plaid' });
    assert.equal((await patch('classic')).status, 200);
    assert.equal((await patch('plaid')).status, 200);
  });
});

before(async () => {
  // Wait for the functions emulator to load the code.
  for (let i = 0; i < 30; i++) {
    try {
      const r = await fetch(fnUrl, { method: 'POST', headers: { 'content-type': 'application/json' }, body: '{"data":{}}' });
      if (r.status < 500) return;
    } catch {
      // not up yet
    }
    await new Promise((r) => setTimeout(r, 1000));
  }
});
