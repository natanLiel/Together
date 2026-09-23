# Poker Night ♠️♥️♣️♦️

This app keeps track of friendly home poker nights. It is not a poker game. It records who bought in for how much, who's up, who pays whom, and everyone's results over time.

## Run it

```
cd poker
npm start            # http://localhost:3000
npm test
```

You need Node 18 or newer. There are no packages to install. Data is saved to `poker/data/db.json`; set `DATA_DIR` or `DATA_FILE` to keep it somewhere else, and `PORT` to change the port.

To use it with friends, host it at a public address, for example Render, Railway, Fly.io or a small VPS. Use `npm start` as the start command and point `DATA_DIR` at a persistent disk. On a phone, choose "Add to Home Screen" and it opens like a normal app.

## How a night works

1. **Log in**: name + 4–6 digit PIN. You stay logged in on that phone.
2. **Open a table**: pick the currency (₪ NIS, $ USD, € EUR, £ GBP), the chip value (1×1 … 1×5, meaning one chip is worth 1–5 money, or any other value), and the **entry options**. These become the buy-in buttons every player sees.
3. **Invite**: share the link (one tap to WhatsApp) or the 6-letter code. Whoever opened the table is the **host** for the night.
4. **Buy in**: players tap an amount. Their request waits until the host approves it (or declines it). The host's own entries, and entries the host adds for someone else, go straight in.
5. **Cash out**: each player enters their final chip count. The host can set or fix anyone's count. The app warns when cash-outs don't match the pot.
6. **End the night**: results are locked and the app works out **who pays whom** with as few payments as possible. Anyone involved can mark a payment as paid.

### Who can do what

| | Host | Player |
|---|---|---|
| Request a buy-in at their own table | ✓ (auto-approved) | ✓ (needs approval) |
| Approve / decline requests | ✓ | |
| Edit or delete entries | ✓ | Withdraw own *pending* request only |
| Add an entry for someone else | ✓ | |
| Set final chips | anyone's | own |
| Remove player, edit table, new invite link, end / reopen / delete night, hand over hosting | ✓ | |

Players can only add to tables they've joined. After a night ends, nothing changes unless the host reopens it.

## Also included

- **Share standings**: a WhatsApp-ready summary (live or final) with medals, buy-ins, cash-outs and the settle-up list. One tap to copy or send.
- **Stats**: leaderboard of everyone you've played with, plus a hall of fame (biggest winner, best night, best win rate, hottest streak, most nights). Each player page has total profit, win rate, average per night, ROI, best and worst night, current streak, a profit-over-time chart and the list of nights. Nights in different currencies are never added together.
- **Badges**: 🔥 winning streak, 🧊 losing streak, 🦈 shark, 🎖️ regular, 📈 big ROI.
- **Hand checker**: pick your cards and the board. It shows the made hand, pre-flop strength (Chen score), your chance to win against 1–8 players (simulated), your outs, and what your hand is likely to end up as. Add an opponent's exact cards to settle "who was ahead?" arguments.
- **Blinds timer**: levels and minutes per level you can change, keeps the screen awake, beeps when blinds go up.

## Layout

```
server.js           HTTP server (Node built-ins only)
lib/api.js          routes, auth, permissions
lib/logic.js        balances, settle-up, stats (pure functions)
lib/store.js        JSON-file storage with atomic writes
public/             the web app (index.html, app.js, style.css, hand.js)
test/               node:test suites
```
