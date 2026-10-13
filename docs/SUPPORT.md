# Flappy Spikes support script

Owner and Claude use this when answering support mail (PRD-2.3 §22.5). Support
address: hello@duoleads.com. The website's support page is
https://flappyspikes.com/support.

## Gift codes

Gift codes are Google Play promo codes (Apple offer codes once the iPhone
version is out) for one of three products:

| Product | Gives |
|---|---|
| `gift_coins_10000` | 10,000 coins |
| `gift_noads_coins_10000` | No Ads + 10,000 coins (the coins only once, ever) |
| `no_ads` | No Ads + its usual 1,000 bonus coins |

The player redeems a code in the game (Settings → Redeem code), anywhere in the
Play Store, or with "Redeem code" in Google's purchase sheet. The gift arrives
the next time the game is on a menu, with a "A GIFT FOR YOU!" popup.

Codes are made by Claude in Play Console on the owner's request (Monetize →
Promotions → promo codes). Every batch is logged in
[`promo_codes_log.md`](promo_codes_log.md) — **never the codes themselves**.
Google Play allows 500 promo codes per quarter for all one-time products
together; a code stops working at the end of the quarter it was made in.

## Rules (Google Play and Apple forbid rewarding ratings or reviews)

Google treats it as incentivized when *"a user is offered money, goods, or the
equivalent in exchange for"* a rating or review.

- **Fine:** an unconditional "sorry, here's a little gift" code, sent in a
  reply to a **support email**.
- **Fine:** a public reply to a bad review that only points to support
  ("Sorry about that! Please mail hello@duoleads.com and we'll help"), with
  **no code** in the reply.
- **Never:** a gift that depends on changing, improving or removing a review or
  rating.
- **Never:** asking for a review or rating in the same message as a gift.
- **Never:** posting codes publicly, selling them, or offering them in exchange
  for anything.
- **Each code goes to one person.** It is used once, and it expires at the end
  of the quarter.

## Reply template (support email, unconditional gift)

> Hi! Sorry about the trouble with Flappy Spikes. As a small thank-you for
> letting us know, here is a gift code: `<code>`. Open the game, go to
> Settings → Redeem code (or redeem it in the Play Store), and the gift
> arrives the next time you're on the menu. It works once and expires at the
> end of the quarter. Happy flapping!

Do not mention ratings or reviews in this message.
