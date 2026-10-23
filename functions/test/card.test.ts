/** PRD-2.6 F9 versus-card `look.card` validation (pure, no emulator writes). */
import assert from 'node:assert/strict';
import { CARD_FRAME_IDS, CARD_NAME_IDS, CARD_STICKER_IDS, validCard } from '../src/card.js';
import { validLook } from '../src/schema.js';
import { checkRun } from '../src/timeline.js';
import { LOOK, makeRun } from './helpers.js';

const SKILL_FRAMES = ['pecking', 'roost', 'prey'];
const SKILL_NAMES = ['n_sky', 'n_thunder', 'n_marquee'];
const SKILL_STICKERS = ['s_unstop', 's_flawless', 's_topflock'];
const VERSUS_FRAMES = [
  'f_bubblegum',
  'f_tape',
  'f_checker',
  'f_eggshell',
  'f_stitch',
  'f_hazard',
  'f_spikes',
  'f_feathers',
  'f_hoops',
  'f_pinball',
  'f_deepsea',
  'f_neon',
  'f_laurel',
  'f_magma',
  'f_storm',
  'f_wings',
  'f_orbit',
];
const VERSUS_NAMES = [
  'n_tangerine',
  'n_ocean',
  'n_grass',
  'n_cherry',
  'n_grape',
  'n_midnight',
  'n_bubble',
  'n_candy',
  'n_comic',
  'n_sunset',
  'n_spiky',
  'n_rainbow',
  'n_gold',
  'n_flappy',
  'n_glitch',
  'n_fire',
  'n_stardust',
];
const VERSUS_STICKERS = [
  's_gg',
  's_thumbs',
  's_heart',
  's_wow',
  's_kaching',
  's_spiked',
  's_pow',
  's_nailed',
  's_bye',
  's_hatch',
  's_zoom',
  's_hot',
  's_medal',
  's_piggy',
  's_disco',
  's_champ',
  's_fireworks',
];

describe('PRD-2.6 F9 look.card validation', () => {
  it('exports the 17 versus-card ids per kind plus the 3 skill ids per kind', () => {
    for (const [ids, versus, skill, label, prefix] of [
      [CARD_FRAME_IDS, VERSUS_FRAMES, SKILL_FRAMES, 'frames', 'f_'],
      [CARD_NAME_IDS, VERSUS_NAMES, SKILL_NAMES, 'names', 'n_'],
      [CARD_STICKER_IDS, VERSUS_STICKERS, SKILL_STICKERS, 'stickers', 's_'],
    ] as const) {
      assert.deepEqual(ids.slice(0, 17), versus, `${label}: the approved versus-card ids`);
      assert.deepEqual(ids.slice(17), skill, `${label}: the skill-only ids`);
      assert.ok(versus.every((id) => id.startsWith(prefix)), `${label} prefix`);
      assert.equal(ids.filter((id) => (versus as readonly string[]).includes(id)).length, 17, label);
      assert.equal(ids.filter((id) => skill.includes(id as never)).length, 3, label);
      assert.equal(ids.length - skill.length, 17, label);
      assert.equal(new Set(ids).size, ids.length, `${label} ids are unique`);
      assert.equal(ids.length, 20, label);
    }
  });

  it('accepts a full card, single-slot cards, empty slots and every skill id', () => {
    for (const card of [
      'f_orbit|n_fire|s_fireworks',
      '|n_ocean|',
      '||',
      'f_bubblegum||',
      '|n_tangerine|',
      '||s_gg',
      'pecking||',
      '|n_marquee|',
      '||s_topflock',
    ]) {
      assert.equal(validCard(card), true, card);
      assert.equal(validLook({ ...LOOK, card }), true, card);
    }
    for (const frame of SKILL_FRAMES) assert.equal(validCard(`${frame}||`), true, frame);
    for (const name of SKILL_NAMES) assert.equal(validCard(`|${name}|`), true, name);
    for (const sticker of SKILL_STICKERS) assert.equal(validCard(`||${sticker}`), true, sticker);
    assert.equal(validCard(undefined), true);
    // Every sold and skill id is accepted in its own slot.
    for (const frame of CARD_FRAME_IDS) assert.equal(validCard(`${frame}||`), true, frame);
    for (const name of CARD_NAME_IDS) assert.equal(validCard(`|${name}|`), true, name);
    for (const sticker of CARD_STICKER_IDS) assert.equal(validCard(`||${sticker}`), true, sticker);
  });

  it('rejects wrong slot kinds, unknown ids, 1 or 3 pipes and non-strings', () => {
    for (const bad of [
      'n_fire|f_orbit|s_fireworks',
      'f_orbit|s_fireworks|n_fire',
      'f_orbit|n_fire|f_orbit',
      'f_unknown||',
      '|n_unknown|',
      '||s_unknown',
      'F_ORBIT||',
      'f_orbit|n_fire',
      'f_orbit|n_fire|s_fireworks|',
      'f_orbit||n_fire|s_fireworks',
      'f_orbit n_fire s_fireworks',
      '',
      null,
      7,
      {},
      [],
    ]) {
      assert.equal(validCard(bad), false, String(bad));
    }
    assert.equal(validCard('f_orbit|n_fire|s_fireworks|'), false);
    assert.equal(validCard(`f_orbit|n_fire|${'s_'.padEnd(48, 'x')}`), false);
    assert.equal(validCard('x'.repeat(49)), false);
  });

  it('caps the card at 48 characters', () => {
    const longest = 'f_checker|n_midnight|s_fireworks';
    assert.ok(longest.length <= 48);
    assert.equal(validCard(longest), true);
    assert.equal(validCard('f_checker|n_midnight|s_fireworks '.padEnd(49, ' ')), false);
    assert.equal(validCard('x'.repeat(49)), false);
  });
});

describe('PRD-2.6 F9 validLook and checkRun', () => {
  it('a 2.5 look without card stays valid', () => {
    assert.equal(validLook({ ...LOOK }), true);
    assert.equal(validLook({ ...LOOK, card: undefined }), true);
    assert.equal(validLook({ bird: 'classic', gear: 'none', hat: 'none', hoop: 'pink', trail: 'flame' }), true);
    assert.equal(validLook({ ...LOOK, card: 'f_orbit|n_fire|s_fireworks' }), true);
    assert.equal(validLook({ ...LOOK, card: 'bad' }), false);
    assert.equal(validLook({ ...LOOK, card: 7 }), false);
    assert.equal(validLook({ ...LOOK, extra: 'x' }), false);
  });

  it('checkRun rejects an invalid card through validLook', () => {
    assert.equal(checkRun(makeRun({ look: { ...LOOK, card: 'f_orbit|n_fire|s_fireworks' } }), 99), null);
    assert.equal(checkRun(makeRun({ look: { ...LOOK, card: 'f_orbit|n_fire' } }), 99), 'shape');
    assert.equal(checkRun(makeRun({ look: { ...LOOK, card: 'f_orbit|f_orbit|s_fireworks' } }), 99), 'shape');
    assert.equal(checkRun(makeRun({ look: { ...LOOK, card: 7 as never } }), 99), 'shape');
  });
});
