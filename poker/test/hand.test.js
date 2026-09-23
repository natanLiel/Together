'use strict';
const test = require('node:test');
const assert = require('node:assert');
const PH = require('../public/hand.js');

const cards = (s) => s.split(' ').map(PH.parseCard);
const name = (s) => PH.describe(PH.evaluate(cards(s)));
const score = (s) => PH.evaluate(cards(s)).score;

test('names every hand category', () => {
  assert.equal(name('As Ks Qs Js Ts 2d 3c'), 'Royal Flush');
  assert.equal(name('9h 8h 7h 6h 5h Ad Ac'), 'Straight Flush, Nine high');
  assert.equal(name('9c 9d 9h 9s 2c'), 'Four of a Kind, Nines');
  assert.equal(name('Kc Kd Kh 7s 7c'), 'Full House, Kings full of Sevens');
  assert.equal(name('Ah 9h 7h 4h 2h Kd'), 'Flush, Ace high');
  assert.equal(name('Ts 9d 8c 7h 6s'), 'Straight, Ten high');
  assert.equal(name('Qc Qd Qh 5s 2c'), 'Three of a Kind, Queens');
  assert.equal(name('Jc Jd 4h 4s Ac'), 'Two Pair, Jacks and Fours');
  assert.equal(name('Ac Ad 7h 4s 2c'), 'Pair of Aces');
  assert.equal(name('Ac Td 7h 4s 2c'), 'High Card, Ace');
});

test('wheel is a five-high straight and loses to six-high', () => {
  assert.equal(name('As 2d 3c 4h 5s'), 'Straight, Five high');
  assert.ok(score('6s 2d 3c 4h 5s') > score('As 2d 3c 4h 5s'));
});

test('kickers and best-five selection', () => {
  assert.ok(score('Ac Ad Kh 4s 2c') > score('Ac Ad Qh 4s 2c'));
  // Three pairs: only the best two plus the best kicker count.
  assert.equal(score('Kc Kd 9h 9s 5c 5d 2h'), score('Kc Kd 9h 9s 5c 5d 3h'));
  // Two sets make a full house with the higher set on top.
  assert.equal(name('8c 8d 8h 3s 3c 3d Ad'), 'Full House, Eights full of Threes');
  // Flush beats a straight present in the same seven cards.
  assert.equal(name('2h 3h 4h 5d 6h 9h Ks'), 'Flush, Nine high');
});

test('equity: aces are big favourites against a random hand, and known matchups are sane', () => {
  const aa = PH.equity({ hero: cards('As Ah'), opponents: 1, iterations: 4000, seed: 7 });
  assert.ok(aa.equity > 0.8 && aa.equity < 0.9, `AA equity ${aa.equity}`);
  const flip = PH.equity({ hero: cards('Qs Qh'), villains: [cards('Ac Kd')], opponents: 1, iterations: 6000, seed: 3 });
  assert.ok(flip.equity > 0.52 && flip.equity < 0.6, `QQ vs AKo ${flip.equity}`);
  const river = PH.equity({ hero: cards('As Ks'), board: cards('Qs Js Ts 2d 3c'), villains: [cards('Ah Kh')], iterations: 10 });
  assert.equal(river.win, 1);
  const chop = PH.equity({ hero: cards('2c 3d'), board: cards('As Ks Qs Js Ts'), villains: [cards('4c 5d')], iterations: 10 });
  assert.equal(chop.tie, 1);
  assert.equal(chop.equity, 0.5);
});

test('outs on a flush draw', () => {
  const outs = PH.outs(cards('Ah Kh'), cards('7h 4h 2c'));
  const hearts = outs.filter((c) => PH.suitOf(c) === 1);
  assert.equal(hearts.length, 9);
});

test('pre-flop tiers', () => {
  assert.equal(PH.preflopTier(cards('As Ad')).tier, 'Premium');
  assert.equal(PH.preflopTier(cards('7s 2d')).tier, 'Weak');
  assert.equal(PH.handLabel(cards('Kd As')), 'AKo');
});

test('outs ignore cards that only pair the board', () => {
  const outs = PH.outs(cards('As Ah'), cards('Kd Qc 7s')).map(PH.cardToString).sort();
  assert.deepEqual(outs, ['Ac', 'Ad']);
});
