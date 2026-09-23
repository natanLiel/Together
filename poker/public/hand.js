// Poker hand evaluation and equity. Runs in the browser (window.PokerHand)
// and in Node (require) so the same code is tested and shipped.
(function (root, factory) {
  if (typeof module === 'object' && module.exports) module.exports = factory();
  else root.PokerHand = factory();
})(typeof self !== 'undefined' ? self : this, function () {
  'use strict';

  const RANKS = '23456789TJQKA';
  const SUITS = 'shdc';
  const SUIT_SYMBOL = { s: '♠', h: '♥', d: '♦', c: '♣' };
  const RANK_NAME = ['Two', 'Three', 'Four', 'Five', 'Six', 'Seven', 'Eight', 'Nine', 'Ten', 'Jack', 'Queen', 'King', 'Ace'];
  const RANK_PLURAL = ['Twos', 'Threes', 'Fours', 'Fives', 'Sixes', 'Sevens', 'Eights', 'Nines', 'Tens', 'Jacks', 'Queens', 'Kings', 'Aces'];
  const CATEGORIES = ['High Card', 'Pair', 'Two Pair', 'Three of a Kind', 'Straight', 'Flush', 'Full House', 'Four of a Kind', 'Straight Flush'];

  // A card is an int 0..51: rank * 4 + suit.
  function parseCard(str) {
    const s = String(str).trim();
    const r = RANKS.indexOf(s[0].toUpperCase() === '1' ? 'T' : s[0].toUpperCase());
    const suitChar = s[s.length - 1].toLowerCase();
    const u = SUITS.indexOf(suitChar);
    if (r < 0 || u < 0) throw new Error('Bad card: ' + str);
    return r * 4 + u;
  }
  const rankOf = (c) => c >> 2;
  const suitOf = (c) => c & 3;
  const cardToString = (c) => RANKS[rankOf(c)] + SUITS[suitOf(c)];

  // Highest straight top-rank in a 13-bit rank mask, or -1. Handles the wheel (A-2-3-4-5).
  function straightTop(mask) {
    for (let top = 12; top >= 4; top--) {
      const need = 0x1f << (top - 4);
      if ((mask & need) === need) return top;
    }
    const wheel = (1 << 12) | 0xf;
    return (mask & wheel) === wheel ? 3 : -1;
  }

  function topRanks(mask, n) {
    const out = [];
    for (let r = 12; r >= 0 && out.length < n; r--) if (mask & (1 << r)) out.push(r);
    return out;
  }

  function score(cat, kickers) {
    let s = cat;
    for (let i = 0; i < 5; i++) s = s * 16 + (kickers[i] != null ? kickers[i] + 1 : 0);
    return s;
  }

  // Evaluates the best hand from 1..7 cards. Returns { score, category, kickers }.
  // Higher score wins; equal scores tie.
  function evaluate(cards) {
    const counts = new Array(13).fill(0);
    const suitMasks = [0, 0, 0, 0];
    const suitCounts = [0, 0, 0, 0];
    let rankMask = 0;
    for (const c of cards) {
      const r = rankOf(c), u = suitOf(c);
      counts[r]++;
      suitMasks[u] |= 1 << r;
      suitCounts[u]++;
      rankMask |= 1 << r;
    }

    let flushSuit = -1;
    for (let u = 0; u < 4; u++) if (suitCounts[u] >= 5) flushSuit = u;

    if (flushSuit >= 0) {
      const sf = straightTop(suitMasks[flushSuit]);
      if (sf >= 0) return { score: score(8, [sf]), category: 8, kickers: [sf] };
    }

    const quads = [], trips = [], pairs = [];
    for (let r = 12; r >= 0; r--) {
      if (counts[r] === 4) quads.push(r);
      else if (counts[r] === 3) trips.push(r);
      else if (counts[r] === 2) pairs.push(r);
    }

    if (quads.length) {
      const q = quads[0];
      const k = topRanks(rankMask & ~(1 << q), 1);
      return { score: score(7, [q, ...k]), category: 7, kickers: [q, ...k] };
    }
    if (trips.length && (trips.length > 1 || pairs.length)) {
      const t = trips[0];
      const p = Math.max(trips[1] != null ? trips[1] : -1, pairs[0] != null ? pairs[0] : -1);
      return { score: score(6, [t, p]), category: 6, kickers: [t, p] };
    }
    if (flushSuit >= 0) {
      const k = topRanks(suitMasks[flushSuit], 5);
      return { score: score(5, k), category: 5, kickers: k };
    }
    const st = straightTop(rankMask);
    if (st >= 0) return { score: score(4, [st]), category: 4, kickers: [st] };
    if (trips.length) {
      const t = trips[0];
      const k = topRanks(rankMask & ~(1 << t), 2);
      return { score: score(3, [t, ...k]), category: 3, kickers: [t, ...k] };
    }
    if (pairs.length >= 2) {
      const [a, b] = pairs;
      const k = topRanks(rankMask & ~(1 << a) & ~(1 << b), 1);
      return { score: score(2, [a, b, ...k]), category: 2, kickers: [a, b, ...k] };
    }
    if (pairs.length === 1) {
      const p = pairs[0];
      const k = topRanks(rankMask & ~(1 << p), 3);
      return { score: score(1, [p, ...k]), category: 1, kickers: [p, ...k] };
    }
    const k = topRanks(rankMask, 5);
    return { score: score(0, k), category: 0, kickers: k };
  }

  function describe(result) {
    const k = result.kickers;
    switch (result.category) {
      case 8: return k[0] === 12 ? 'Royal Flush' : `Straight Flush, ${RANK_NAME[k[0]]} high`;
      case 7: return `Four of a Kind, ${RANK_PLURAL[k[0]]}`;
      case 6: return `Full House, ${RANK_PLURAL[k[0]]} full of ${RANK_PLURAL[k[1]]}`;
      case 5: return `Flush, ${RANK_NAME[k[0]]} high`;
      case 4: return `Straight, ${RANK_NAME[k[0]]} high`;
      case 3: return `Three of a Kind, ${RANK_PLURAL[k[0]]}`;
      case 2: return `Two Pair, ${RANK_PLURAL[k[0]]} and ${RANK_PLURAL[k[1]]}`;
      case 1: return `Pair of ${RANK_PLURAL[k[0]]}`;
      default: return k.length ? `High Card, ${RANK_NAME[k[0]]}` : 'No cards';
    }
  }

  // Chen formula: quick pre-flop strength score for two hole cards.
  function chen(hole) {
    const [a, b] = hole;
    const hi = Math.max(rankOf(a), rankOf(b)), lo = Math.min(rankOf(a), rankOf(b));
    const base = (r) => (r === 12 ? 10 : r === 11 ? 8 : r === 10 ? 7 : r === 9 ? 6 : (r + 2) / 2);
    let pts = base(hi);
    if (hi === lo) pts = Math.max(5, pts * 2);
    if (suitOf(a) === suitOf(b)) pts += 2;
    const gap = hi - lo - 1;
    if (hi !== lo) {
      if (gap === 1) pts -= 1;
      else if (gap === 2) pts -= 2;
      else if (gap === 3) pts -= 4;
      else if (gap >= 4) pts -= 5;
      if (gap <= 1 && hi < 10) pts += 1;
    }
    return Math.ceil(pts);
  }

  function preflopTier(hole) {
    const c = chen(hole);
    if (c >= 12) return { chen: c, tier: 'Premium', note: 'Raise from any position.' };
    if (c >= 10) return { chen: c, tier: 'Strong', note: 'Raise from most positions.' };
    if (c >= 8) return { chen: c, tier: 'Playable', note: 'Good in middle / late position.' };
    if (c >= 6) return { chen: c, tier: 'Speculative', note: 'Late position or cheap multiway pots.' };
    return { chen: c, tier: 'Weak', note: 'Usually a fold.' };
  }

  function handLabel(hole) {
    const [a, b] = hole.slice().sort((x, y) => rankOf(y) - rankOf(x));
    if (rankOf(a) === rankOf(b)) return RANKS[rankOf(a)] + RANKS[rankOf(b)];
    return RANKS[rankOf(a)] + RANKS[rankOf(b)] + (suitOf(a) === suitOf(b) ? 's' : 'o');
  }

  function makeRng(seed) {
    if (seed == null) return Math.random;
    let s = seed >>> 0;
    return function () {
      s = (s + 0x6d2b79f5) >>> 0;
      let t = s;
      t = Math.imul(t ^ (t >>> 15), t | 1);
      t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
      return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
    };
  }

  // Monte Carlo equity for `hero` against `opponents` players.
  // `villains` is an optional list of known opponent hands (each two cards); the rest are random.
  function equity({ hero, board = [], opponents = 1, villains = [], iterations = 5000, seed }) {
    const rng = makeRng(seed);
    const used = new Set([...hero, ...board, ...villains.flat()]);
    if (used.size !== hero.length + board.length + villains.flat().length) throw new Error('Duplicate cards');
    const deck = [];
    for (let c = 0; c < 52; c++) if (!used.has(c)) deck.push(c);
    const randomOpps = Math.max(0, opponents - villains.length);
    const need = (5 - board.length) + randomOpps * 2;
    let win = 0, tie = 0, eq = 0;
    const heroCats = new Array(9).fill(0);
    const villainWins = villains.map(() => 0);

    for (let i = 0; i < iterations; i++) {
      // Partial Fisher-Yates: draw `need` cards from the end of the deck.
      for (let j = 0; j < need; j++) {
        const k = j + Math.floor(rng() * (deck.length - j));
        const t = deck[j]; deck[j] = deck[k]; deck[k] = t;
      }
      let p = 0;
      const full = board.slice();
      while (full.length < 5) full.push(deck[p++]);
      const heroEval = evaluate(hero.concat(full));
      heroCats[heroEval.category]++;
      let best = heroEval.score, bestCount = 1, heroBest = true;
      const vScores = [];
      for (const v of villains) vScores.push(evaluate(v.concat(full)).score);
      for (let o = 0; o < randomOpps; o++) vScores.push(evaluate([deck[p++], deck[p++]].concat(full)).score);
      for (const s of vScores) {
        if (s > best) { best = s; bestCount = 1; heroBest = false; }
        else if (s === best) bestCount++;
      }
      if (heroBest) {
        if (bestCount === 1) win++; else tie++;
        eq += 1 / bestCount;
      }
      for (let v = 0; v < villains.length; v++) if (vScores[v] === best) villainWins[v] += 1 / bestCount;
    }
    return {
      iterations,
      win: win / iterations,
      tie: tie / iterations,
      lose: 1 - (win + tie) / iterations,
      equity: eq / iterations,
      categories: heroCats.map((n) => n / iterations),
      villainEquity: villainWins.map((n) => n / iterations),
    };
  }

  // Cards that move hero to a better hand category on the next street.
  function outs(hero, board) {
    if (board.length < 3 || board.length > 4) return [];
    const used = new Set([...hero, ...board]);
    const now = evaluate(hero.concat(board)).category;
    const boardNow = evaluate(board).category;
    const result = [];
    for (let c = 0; c < 52; c++) {
      if (used.has(c)) continue;
      const next = evaluate(hero.concat(board, [c])).category;
      // Only count it if the improvement is not shared by everyone via the board alone.
      if (next <= now || next <= boardNow || evaluate(board.concat([c])).category >= next) continue;
      // Pairing the board only gives everyone two pair; that's not a real out.
      if (next <= 2 && board.some((b) => rankOf(b) === rankOf(c))) continue;
      result.push(c);
    }
    return result;
  }

  return {
    RANKS, SUITS, SUIT_SYMBOL, CATEGORIES,
    parseCard, cardToString, rankOf, suitOf,
    evaluate, describe, chen, preflopTier, handLabel, equity, outs,
  };
});
