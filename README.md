# WritPath

A World of Warcraft: Forever addon for Craftsman's Writs (Durotar Supply and Logistics / merchant reputation).

- **Buy writs:** set a rep target and get the cheapest and the fastest set of writs to reach it, priced live from
  your Auctionator scan, never two writs for the same customer in one day.
- **My writs:** the writs you already have, in the shortest hand-in order.
- **Guided route:** a RestedXP-style step list with an arrow, flight paths, zone crossings and boats.
- **Buying help:** "Send to Auctionator" makes a shopping list; at the auction house a "Writ shopping" panel buys
  the list one click at a time, with a price cap.
- **Money:** what each writ cost and what its coin pouch paid, per plan.
- **Learns as you play:** customer spots at turn-in, roads you ride, boats you take, flight times and which
  flight paths you know.

## Screenshots

Mockups with example data (open [mockups/writpath-mockup.html](mockups/writpath-mockup.html) in a browser to click
through it; add `#buy` to the address to start on the Buy writs plan).

![Buy writs: cheapest and fastest plans, the guide and the auction house panel](mockups/writpath-buy-writs.png)

![My writs: the writs you have, in hand-in order](mockups/writpath-my-writs.png)

## Install

1. On GitHub, click **Code > Download ZIP** and unzip it.
2. The folder inside is called `WritPath-main`: **rename it to `WritPath`** (WoW only loads an addon whose folder
   matches its `.toc` name).
3. Put it in `World of Warcraft/_forever_/Interface/AddOns/`, so you have `AddOns/WritPath/WritPath.toc`.
   (The `mockups` folder is only for this page; the game ignores it.)

Everything WritPath needs is in this folder. Optional addons it uses when you have them:

- **Auctionator**: needed for prices, so for "Buy writs" and the auction house buying panel. Do a full scan in
  Auctionator first. "My writs" (ordering writs you already have) works without it.
- **EllesmereUI**: WritPath's windows take its look; otherwise they use a plain dark style.

First time: open any flight master's map once on each continent, so WritPath learns which flight paths you know.
Roads, boats and flight times you use are learned as you travel.

## How to use

### Before you start

1. **Scan the auction house with Auctionator** (a full scan). WritPath prices everything from that scan, and the
   planner shows how old it is in the top right ("Last full AH scan: 4 h ago"). Rescan if it's old.
2. **Open a flight master's map once on each continent.** That's how WritPath learns which flight paths you know.
   Until then routes can't use flights (`/writs travel` shows what it knows).
3. Find the **minimap button** (a note icon). Left-click shows or hides the guide window; right-click opens the
   planner. The guide window's header has the same buttons: map icon = My writs, coin icon = Buy writs,
   bag icon = money report, red X = Clear.

### The one rule: one writ per customer per day

Each customer takes one writ a day. Writs that go to the same customer count as one, so WritPath never plans
two for the same customer on the same day; extra writs are listed as "Tomorrow" and kept for another day.

### Plan: My writs (the writs you already have)

Open the planner and pick **My writs**. It lists every writ in your bags or quest log in the fastest hand-in order
from where you stand, with the customer, the zone and the travel time. Click **Start route** to follow it.

### Plan: Buy writs (reach a rep target)

1. Pick **Buy writs**, type a **Rep target** (for example 1000) and press **Plan**.
2. Two plans appear:
   - **Cheapest**: the least gold that reaches the target.
   - **Fastest**: the shortest trip that reaches the target (it may cost more). It's never slower than Cheapest.
   Each card shows the cost, the time, the rep and the net gold (coin pouches minus what you spend).
   Your own writs are always used first.
3. Click a card to see its writs. "yours" means you already have it; a price means it has to be bought.
4. **Include customers known by zone only** lets WritPath use customers whose exact spot isn't known yet (it
   learns the spot when you accept the writ). Leave it off for the most reliable routes.
5. If the target can't be reached today, the plan says how close you can get and why.
6. Click **Start route**. This sets the guide, starts tracking the plan's money, and makes the shopping list.
   (**Send to Auctionator** also makes a "WritPath" shopping list in Auctionator, if you'd rather buy there.)

### Buy: the Writ shopping panel at the auction house

Open the auction house and a **Writ shopping** panel opens beside it with the plan's list (it only opens while a
plan has something left to buy).

- It shows the cheapest offer for the next item. Click **Buy** for gear and writs (one click), or **Get price**
  then **Confirm** for potions and other stackable goods (the game needs two clicks for those).
- **Skip** leaves an item for later.
- If the price is more than 25% over what the plan expected, it stops and asks first. That includes an item only
  sold as a whole stack bigger than you need ("Only sold as a stack of 6: you need 1").
- While you look at one item, the next few are already being looked up, so the next one is usually ready at once.
- Purchases that go to your mailbox count as yours straight away.
- **When you close the auction house**, the route is rebuilt from what you actually bought: writs you didn't
  get drop out, missing items become a shopping step, and chat says what changed.

Then right-click each writ in your bags to accept it.

### Follow the guide

The guide window shows the next steps, and an arrow on screen points to the current one with the distance.

- **Fly** steps finish when you take the flight.
- **Road crossings and docks** finish once you're within 200 yards. If you take another road and reach a later
  one first, the guide catches up.
- **Customer** steps finish only when you hand the writ in.
- **Learn the flight path** steps appear after a customer when a flight path you don't have is close by; they
  finish when you open that flight master's map (`/writs next` skips one you don't want).
- After each hand-in, the rest of the trip is worked out again from where you stand, with everything WritPath
  knows by then, and chat says what's next.
- If a step gets stuck, `/writs next` skips it and `/writs back` undoes that.

The footer under the guide shows the running plan's money: **cost** (what you actually paid once you've bought,
plus anything still to buy; the planned cost is shown next to it), **pouches** from turn-ins so far, and **net**.
The bag icon prints every turn-in's cost and pouch in chat.

**Clear** (the button in the planner, or the red X in the guide header) clears the route, the plan and its shopping
list after asking. What WritPath has learned stays.

### What WritPath learns as you play

- **Customer spots**: the map pin when you accept a writ, and your exact spot when you hand one in. Customers
  that were "zone only" become exact.
- **Roads, boats and zeppelins** you ride, and **flight times** of flights you take.
- **Flight paths you know**, each time you open a flight master's map.

It starts from what ships with it (customer spots from community sources and QuestieDB, RestedXP's roads, boats
and flight points, and trips other WritPath players recorded), and what you learn always wins.

### Slash commands

| Command | What it does |
|---|---|
| `/writs` | Show or hide the guide window |
| `/writs plan` (or `/writs mine`) | Planner on My writs |
| `/writs buy` | Planner on Buy writs |
| `/writs money` | Every turn-in's cost and pouch, in chat |
| `/writs clear` | Clear the route, the plan and its shopping list (no confirm) |
| `/writs travel` | Which flight paths are known and placed, and how many roads and ships WritPath knows |
| `/writs leg` | Why the way to the next customer looks the way it does (times, route, nearest flight points and docks); also saved for a `/reload` |
| `/writs why` | Why some writs aren't in plans (no price, customer unknown, ...) |
| `/writs scan` | Read the map pins of the writs you've accepted |
| `/writs next` / `/writs back` | Skip the current guide step / undo the last skip |
| `/writs reset` | Start the guide's steps over |

### Troubleshooting

- **The route walks everywhere**: run `/writs travel`. If flight paths are missing or "not placed", open a flight
  master's map and plan again.
- **"No AH price"** or writs missing from plans: rescan with Auctionator; `/writs why` gives the reasons.
- **The Writ shopping panel doesn't open**: it only opens while a running plan still has something to buy.
- **A customer's spot is wrong**: accept the writ (its map pin corrects it) or hand it in (your spot is saved).

## License

CC BY-NC-SA 4.0. Includes pathing data adapted from RestedXP (CC BY-NC-SA 4.0). See [CREDITS.md](CREDITS.md)
and [LICENSE](LICENSE).
