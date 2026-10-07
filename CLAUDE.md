# Stack the Cats

A cozy cat-stacking game: tap to drop swinging cats onto a tower and keep it balanced. Built with Flutter and Flame. It's a personal project by JCAN Studios (Aerol Unay).

- **Personal project.** Use only aerol.unay@gmail.com for commits, accounts and anything public. Never mention any employer or work account.
- **Android first.** The `ios/` folder exists, but iOS hasn't been set up.
- **Free, ad-supported, no in-app purchases.**

## Stack

| Part | What |
| --- | --- |
| App | Flutter + Flame (`lib/`), package `com.jcanstudios.stackthecats` |
| Sign-in | Firebase Auth: Google, Facebook, and anonymous for kids' mode |
| Data | Firestore (players, scores, friends) and Realtime Database (presence, live matches) |
| Server | One Cloud Function, `api` (callable, `asia-southeast1`, Node 22, TypeScript in `functions/src/`) |
| Anti-cheat | Firebase App Check |
| Ads | Google AdMob (`lib/ads/`) |
| Updates | Google Play in-app updates (`in_app_update`, `lib/services/app_update_service.dart`), from build 5 |
| Firebase project | `stack-the-cats-9538a` (Blaze plan, $1/month budget alert) |
| Website | https://jcanstudios.github.io/stack-the-cats/ (privacy policy, delete-data page); `app-ads.txt` at the domain root |

## Code map

- `lib/game/`: the game itself (`stack_game.dart`, `cat.dart`), with swing, physics and tower balance
- `lib/services/`: player, game session, leaderboards, friends, age gate, server API client
- `lib/challenge/`: live 1-on-1 matches (friends or random) and their rules
- `lib/economy/`, `lib/store/`: treats, Tuna/Salmon, invites, cats and wallpapers catalog
- `lib/screens/`, `lib/ui/`: screens, overlays and dialogs. In-game buttons are `ui/hud_button.dart` (and `AttentionPulse`); the first-time button walkthrough is `ui/hud_tour.dart`
- `functions/src/index.ts`: every server action (start game, landings, revive, matches, friends bonus and so on)
- `functions/src/economy.ts`: the economy rules (prices, rewards, limits), which are the source of truth
- `firestore.rules`, `database.rules.json`: security rules
- `marketing/play-store/`: store listing text and form answers (`listing.md`), icon, feature graphic, screenshots

## How the economy works (important)

The **server owns the wallet**. The app can't change treats, Tuna, Salmon or owned items itself, and the Firestore rules refuse it. The app reports cat landings and the server works out rewards.

So any change to prices, rewards or limits must be made in `functions/src/economy.ts` (and the matching client display code), then **redeployed**.

## Player names (privacy)

- Anyone who isn't a friend sees **"First L."** (first name and last initial): leaderboards, random matches, friend requests and online status. The rule is `boardName` in `functions/src/economy.ts` and `publicName` in `lib/services/public_name.dart`; keep the two the same.
- **Full names** are only in `profiles/{uid}`, which only the player and their friends can read (`firestore.rules`). The leaderboard swaps in full names for friends and the player themself (`LeaderboardService.withFullNames`). Friend-to-friend challenges use full names.
- Kids only ever show their made-up name ("Sleepy Kitten 42").

## Kids' mode

There's a neutral birth-year screen on first launch (`lib/services/age_gate.dart`). Players under 13 get:
- an anonymous account with a made-up name, and no Google or Facebook sign-in
- no friends, invites, live matches or wagers
- child-directed AdMob ads (rated G, not personalised)

This is required by Google Play's Families policy, because the app targets ages 6 and up. Don't add features that collect data from kids or let them interact with others.

## Commands

```sh
# Run / test the app
flutter run
flutter test

# Release bundle for Google Play (signed with the upload key)
flutter build appbundle --release
# -> build/app/outputs/bundle/release/app-release.aab

# Server tests (Firebase emulators; JAVA_HOME = Android Studio's jbr)
cd functions && npm test

# Deploy server + rules together (run from project root)
firebase deploy --only functions,firestore:rules,database
```

- `firebase login` has to be run by the user in their own terminal.
- **Every Play upload needs a higher build number** in `pubspec.yaml` (`1.0.0+5` → `1.0.0+6` and so on). The part before `+` (`1.0.0`) is the version players see; it's a label and can stay the same, but the build number must always go up and never resets.
- A bundle already uploaded to one track (say Internal testing) is in Play's library: use **Add from library** on other tracks instead of uploading it again ("Version code already used").
- If Gradle fails with "PKIX path building failed" / SSL errors while downloading new libraries, that's Claude's sandboxed shell, not the project: run the build in your own terminal.
- Debug builds use Google's test ad IDs, and release builds use the real ones (`lib/ads/ad_service.dart`). Never tap real ads on your own device. Add test devices in AdMob instead.

## Signing and secrets

- The upload keystore is `android/upload-keystore.jks`, with passwords in `android/key.properties`. Both are gitignored. **Never commit or print them. Back them up somewhere safe.**
- Google Play re-signs the app with its own **app signing key**. Its SHA-1 (`B2:E4:CC:…:FC:95`) is registered in Firebase, and its Facebook key hash (`suTMkke7pPEKXln5qR60HifB/JU=`) is in the Meta developer dashboard. Without these, sign-in fails in Play-installed builds.
- Key hashes registered with Facebook: debug, upload and Play signing (all three are needed).

## Launch status (as of 2026-10-07)

- Play Console: personal developer account "JCAN Studios".
- **Closed testing (Alpha):** approved 2026-10-07; 6 testers opted in that day. Build 4 sent for review 2026-10-07.
- **Builds:** 3 = best score above the score, button walkthrough, Realign nudge, new buttons. 4 = "First L." names for non-friends (server and rules deployed 2026-10-07). 5 = in-app update prompt (code done and committed; the bundle still has to be built and uploaded). Updates can only prompt players who already have build 5 or later.
- Players without the prompt get updates the normal Play Store way (auto-update or Manage apps).
- **Next:** get to **12+ real testers** (Android and Gmail) through the opt-in link. They must stay opted in for **14 days in a row**, and then you can apply for production. Your own accounts shouldn't count toward the 12.
- **AdMob:** payment profile done, account verification pending. Link the app to the store in AdMob only **after** it's public in production. Until then, no real ads are served.
- Play review sign-in account: `jcan.stackthecatsreview@gmail.com` (the password is only in Play Console).
- Store category: Casual. Tags: Arcade, Casual, Physics-based. Assets are labelled as AI-generated.

## Ideas for later

- Testers say treats feel limited. The daily cap (2000 treats from games) is probably not being hit; basic-cat Purrfects pay 0 and streaks start at the 4th Purrfect, so normal play earns slowly. An idea: pay 2 per basic Purrfect, start streaks at the 3rd, maybe raise the cap to 3000. Keep a cap: it bounds bots that slip past the bot checks (and protects wagers). Check `earnedTreats`/`earnDay` in `users/{id}` first. Match prizes (Friendly and wagers) don't count toward the cap.
- Report and block players (leaderboards and matches). Google's content rating questions asked about this.
- Firebase Analytics for retention (update the Data safety form and keep it out of kids' mode).
- An iOS version once Android has shown it can earn money.

## Working style

- Write plainly and briefly. Explain Play Console, Firebase and AdMob steps one at a time, so they can be followed while clicking through the console.
- Commit messages: a short subject in sentence case without a trailing period (for example "Kids' mode for players under 13"), plus a body when useful.
- Ask before deleting data, deploying, or changing anything in Play Console, Firebase or AdMob.
