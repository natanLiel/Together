# Together

One connection at a time.

A dating app built on a single constraint: you hold **one slot**. Until you close it, nothing else opens. No inbox of half-conversations, no reject button, no scoreboard.

## Run it

Open `index.html`. That's the whole thing — one self-contained file, no build step, no server, no network. Add it to your home screen on iOS or Android and it runs full-screen as an installed app.

```
index.html            the entire app, offline-capable (photos embedded)
manifest.json         installable web-app metadata
app-icon.png          512×512 app icon
apple-touch-icon.png  iOS home-screen icon
mark.svg              the rings, as vector
```

## Test roster

Six people with real photographs, so the profile card can be judged with faces rather than placeholders.

| | | |
|---|---|---|
| Maya, 28 | Tel Aviv | 5 photos |
| Noa, 31 | Ramat Gan | 5 photos |
| Shira, 26 | Jaffa | 5 photos |
| Itai, 30 | Florentin | 3 photos |
| Yonatan, 33 | Ramat Aviv | 4 photos |
| Adam, 27 | Bat Yam | 6 photos |

Maya is the hard-wired connection — she carries her photograph through the chat header, the match screen, the video date and the who-liked-you list.

Two further written profiles, Tamar (34) and Roi (36), sit in `PEOPLE_AWAITING_PHOTOS` with their prompts and tags intact. They are out of the browsable pool only because they have no photographs yet; moving them back is a one-line change.

Your own profile and the video-date self-view are deliberately blank. The signed-in user shouldn't wear a face that is also browsable as a candidate.

## How the app works

**One slot.** A connection occupies it until one of you ends things. Ending starts a one-hour undo window — reachable from the chat, never buried in settings.

**One ring a week.** A ring puts you at the top of someone's list. It is the only way to signal real intent, and its scarcity is the point. More can be bought; the weekly one is free.

**Three questions each.** After a mutual like, you each pick three questions for the other from six categories, or write your own. Chat opens once you have both taken your turn. **Answering and skipping count the same, and neither of you is told which the other chose** — so a skip costs nothing and reveals nothing.

**Per-item reactions.** You react to the specific photo or the specific answer that caught you, not to a person as a whole. Those replies travel with your ring and surface in the chat when it opens, so the conversation starts from something real.

**Moving on is silent.** The cross means *next profile*. Nothing is sent, and they are never told.

**Video dates** are built in, with a shared this-or-that prompt to break the first silence.

**Hebrew and English**, with full right-to-left mirroring.

## Design system

Restyled from the original build; flows, states and copy are unchanged.

| | |
|---|---|
| Ground | `#14101A` plum-black |
| Rose | `#E0759A` |
| Light rose | `#F0A8C2` |
| Plum | `#B07AC8` |
| Ink on rose | `#1A0E16` |
| Primary action | `linear-gradient(150deg, #F0A8C2, #E0759A 52%, #B07AC8)` |
| Surfaces | `rgba(255,255,255,.10)` + `blur(30px)`, hairline `rgba(255,255,255,.14)` |
| Type | Instrument Serif throughout |

**Rules that hold everywhere.**

- All interface copy is lowercase. Anything another person wrote is italic.
- The primary gradient is reserved for the single main action on a screen — never two.
- Anything sitting on the rose fill takes the dark ink `#1A0E16`, never white. White on rose measures 2.92:1; the ink measures 6.42:1.
- Controls that float on a photograph use dark glass — `rgba(20,16,26,.6)` + `blur(14px)` + a hairline inset ring — never light glass, which cannot clear 3:1 over skin.
- Destructive actions are outlined with a white label and always name their verb, so colour is never the only signal.
- Every shape is a pill or a 22–30px radius. Nothing is square.
- Nothing is set below 12.5px.

**The mark** is two circles, centreline radius 100, stroke 25.6, centres 138.8 apart — a separation-to-radius ratio of 1.388, which is the interlock. `mark.svg` is the reference; don't eyeball it.

## Not production

Data is in-memory and resets on reload. Pricing is placeholder. There is no backend, no auth, and no real matching — the recommendation copy is written, not computed.
