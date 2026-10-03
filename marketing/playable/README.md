# Stack the Cats: playable and video ads

A 30-cat taste of the Self Challenge, built from the game's own cats, physics,
cushion sway and stability meter. At 15 and 25 cats the game pauses for a
"Download free" popup ("Keep playing" carries on). It ends on a "Play free"
card that opens the Play Store, with no "Try again": one try per ad view.

```
node marketing/playable/build.mjs    # playable ads
node marketing/playable/record.mjs   # video (needs Chrome and ffmpeg)
```

Output in `marketing/playable/dist/`:

| File | Use |
| --- | --- |
| `stack-the-cats-meta.html` | Meta (Facebook / Instagram) playable ad: upload as is. |
| `stack-the-cats-google.zip` | Google Ads App campaign playable / AdMob: upload as an HTML5 asset. |
| `preview.html` | Open in a browser to play it. Add `?demo` to watch it play itself. |
| `stack-the-cats-video.mp4` | 1080x1920 (9:16) video for Reels, Stories, TikTok, Shorts. |

The playable calls `FbPlayableAd.onCTAClick()` on Meta, `ExitApi.exit()` on
Google, `mraid.open()` on other networks, and opens the store link otherwise.

Edit the ad in `src/playable.html`. The demo's moves are in `Demo.plan` (where
each cat lands, as a share of a cat's width) and its captions in `Demo.landed`.
