# Forgery: Forged Delivery Receipts and the Forger's Quill

Research only, not built. Written 2026-11-19 00:23 (local time). Prices from the AH scan of 2026-11-18 17:35.

## What it is

Each faction's **Uncertified Scribe** sells two items for Merchant's Favor:

| | Forged Delivery Receipt | Forger's Quill |
|---|---|---|
| Item id | 262902 | 262896 |
| Cost | 15 Merchant's Favor | 15 Merchant's Favor |
| Needs | Friendly with your supply faction | Honored |
| What it does | Turns an empty Waylaid Crate into a **Notarized Shipping Container** (item 262917). Handed in at your camp's crate clerk: **50 reputation and 1 silver**. | Rewrites an unwanted writ into a random writ of the same tier. |
| Limit | None: no daily limit, no travel beyond the camp | Used up either way; does not reset a delivered order's daily limit |

Scribes:

- Horde: **Kurvelk Shadowhoof** (NPC 256672), west of the Crossroads, The Barrens 49.8, 30.0
- Alliance: **Dianne Softstep** (NPC 256742), Three Corners 9.1, 76.5

Supply factions: Durotar Supply and Logistics (Horde), Azeroth Commerce Authority (Alliance). Ranks: 3,000 Neutral to
Friendly, 6,000 to Honored, 12,000 to Revered, 21,000 to Exalted. Receipts per step: 120 to Honored (1,800 Favor), 240
to Revered (3,600), 420 to Exalted (6,300).

## Price comparison (scan of 2026-11-18 17:35, 376 items)

Pouches from the money log: Journeyman 34s 6c (13 seen), Expert 72s 67c (48 seen), Artisan 74s 56c (WritPath's guess,
none opened).

| Source | Cost per rep (after pouch) | 6,000 rep |
|---|---|---|
| Cheapest writs (Mechanical Repair Kit, Quickdraw Quiver, Mithril Frag Bomb, Goblin Land Mine...) | 0 to 25 copper | ~6 to 15g, if enough orders exist |
| Median writ (Earthen Silk Belt) | 71 copper | ~43g |
| Receipt, Favor already owned | ~0 copper (crate 1s, 1s back) | ~4g of crates |
| Receipt, Favor earned for it | 69 copper | ~46g+ |

Workings for one receipt:

- Cheapest empty Waylaid Crate: 1s (Expert Ore). 271 empty crates listed; the cheapest 120 cost ~4g (the 120th at 6s 70c).
- Cheapest Favor: Expert Textiles crate 3s + filling 39s 20c, minus silver back, for 15 Favor = ~2s 31c per Favor
  (lowest listing only; 1,800 Favor would go deeper into the AH and cost more).
- Receipt = crate + 15 Favor - 1s back = 34s 66c with earned Favor = 69 copper per rep.
- 67 of the 136 priced writs (writ and item both listed) beat a receipt bought with earned Favor; 1 beats one bought
  with Favor already owned.

Takeaways:

- Cheap writs stay 3 to 7 times cheaper than receipts. Writs first.
- Earning Favor only to buy receipts is break-even with a middling writ, but needs no travel and has no daily limit.
- Spare Favor turned into receipts is nearly free rep (the cost is the recipes the Favor won't buy).

## Plan if it's built later

Rep planner, from Friendly up:

1. Writs first, cheapest per rep (as now).
2. Then receipts using Favor already owned (currency 3402).
3. Then receipts with earned Favor, priced by the Favor planner's cost per Favor, only to fill the gap above the daily
   writ limit or where they beat the remaining writs.
4. Guide: a stop at the scribe, empty crates on the shopping list, hand-in at the camp (Planner.lua's camp auto
   hand-in already accepts titles with "Shipping Container").

Leave the Forger's Quill out of plans: its result is random. At most suggest rerolling an owned writ whose item is
very expensive.

To check in game first:

- Does a receipt work on any empty Waylaid Crate, or only some?
- Can WritPath read the supply faction standing on Forever (faction id, API)?
- The exact hand-in NPC for the Notarized Shipping Container.

## Sources

- ConquestCapped, WoW Forever Craftsman's Writs Guide (updated 2026-11-15):
  https://conquestcapped.com/guides/wow-forever/wow-forever-craftsmans-writs/
- Mobalytics, Merchant's Favour and Waylaid Crate guide:
  https://mobalytics.gg/wow-forever/profile/medieval-marty/guides/merchant-s-favour-and-waylaid-crate-full-guide
- Item and NPC ids: Wowhead WoW: Forever search (https://www.wowhead.com/forever/)

To rerun the comparison on a newer scan (needs the fengari package on NODE_PATH):

    node research/comparecost.js "<WoW>/_forever_/WTF/Account/<account>/SavedVariables/WritPath.lua" .
