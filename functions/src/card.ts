/**
 * PRD-2.6 F9 versus-card look validation (`look.card`).
 *
 * A card is one `"<frame>|<name>|<sticker>"` string (each slot an item id or
 * empty, at most 48 characters). The wave-0 server skeleton deliberately
 * rejects every defined value until the F9 allow-list lands, so the schema
 * and rules stay compatible with 2.5 clients while the card task can change
 * only this module.
 */
export function validCard(card: unknown): card is undefined {
  return card === undefined;
}
