/**
 * PRD-2.6 F9 versus-card look validation (`look.card`).
 *
 * A card is one `"<frame>|<name>|<sticker>"` string (each slot an item id or
 * empty, at most 48 characters). Frames, names and stickers are the approved
 * versus-card catalogue (17 of each) plus the three skill-only items of each
 * kind (F10 / O80). Ownership is client-side, as for every look.
 */

/** The 17 sold versus-card frame ids plus the 3 skill-only frames. */
export const CARD_FRAME_IDS = [
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
  'pecking',
  'roost',
  'prey',
] as const;

/** The 17 sold versus-card name-style ids plus the 3 skill-only styles. */
export const CARD_NAME_IDS = [
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
  'n_sky',
  'n_thunder',
  'n_marquee',
] as const;

/** The 17 sold versus-card victory-sticker ids plus the 3 skill-only stickers. */
export const CARD_STICKER_IDS = [
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
  's_unstop',
  's_flawless',
  's_topflock',
] as const;

const FRAMES: ReadonlySet<string> = new Set(CARD_FRAME_IDS);
const NAMES: ReadonlySet<string> = new Set(CARD_NAME_IDS);
const STICKERS: ReadonlySet<string> = new Set(CARD_STICKER_IDS);

/**
 * Whether [card] is an absent field, or exactly three `|`-separated slots
 * (frame, name, sticker) of at most 48 characters, where every non-empty
 * slot is a known id of its kind. An empty slot means "not worn".
 */
export function validCard(card: unknown): card is string | undefined {
  if (card === undefined) return true;
  if (typeof card !== 'string' || card.length > 48) return false;
  const slots = card.split('|');
  if (slots.length !== 3) return false;
  const [frame, name, sticker] = slots;
  return (
    (frame === '' || FRAMES.has(frame)) &&
    (name === '' || NAMES.has(name)) &&
    (sticker === '' || STICKERS.has(sticker))
  );
}
