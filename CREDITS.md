# WritPath credits

WritPath is licensed CC BY-NC-SA 4.0 (see LICENSE) and ships no other addon's code or art. Its data is facts about the game:
where customers and flight masters stand, where zones meet, where boats leave, how long flights take. These were
gathered from the public sources below, refined by what players record in game, or read at runtime from other addons you have.

## Travel facts (TravelFacts.lua)

Zone crossings, boat and zeppelin routes, flight point positions and flight times, compiled from public sources,
among them RestedXP's free WoW: Forever guides and flight data (https://www.restedxp.com/). RestedXP does not
endorse WritPath. What you learn in your own game always wins over this file.

`networkTimes` (50 flight times RestedXP's list lacks) were worked out by deanyo from the lengths of the game's flight
paths in **Polestar**'s WoW: Forever data (GPL-3.0, https://github.com/fitzforge/polestar, `data/forever/travel.json`),
2026-11-18. Only these facts were used; no Polestar code or files are included.

`transports` in TravelFacts.lua (every boat, zeppelin and airship: where each docks, seconds riding each way and the
average wait) is from Polestar's `addon/Polestar/Nav/TravelData.lua`, built from WoW: Forever's transport tables,
2026-11-21. Again only the facts (dock spots, names, times) were used.

## Writ customers (WritDB.lua)

Which NPC takes each Craftsman's Writ, and in which zone, was gathered on 2026-11-14 and 2026-11-15 from:

- **Wowhead**: "Craftsman's Writs: Recipes, Rewards & Routes - WoW: Forever" by Serenal, and its reader comments
  (Nyatui, Drush, Domi98, EmmyBear, bubblebeard, Veru, HansHagbard, zebburr, Nagatoro, Slapthat, Moneybagz).
  https://www.wowhead.com/forever/guide/professions/craftsmans-writs-overview-recipes-rewards
- **Wowhead** item and quest tooltips (writ names, tiers, quests, requested items).
- **wowforever.gg** atlas NPC pages (customer coordinates). https://wowforever.gg/
- **QuestieDB** (GPL-3.0, https://github.com/Questie/Questie): which NPC takes each writ quest and where that
  NPC stands, read from its WoW Forever data on 2026-11-15 and again on 2026-11-24 (28 more Artisan and Expert
  writs; customers marked `src = "questie"`). Only these facts were used; no QuestieDB code or files are included.
- **QuestieDB** again for where each flight master stands (WritPathData.lua, `flightMasters`), used to place
  the flight points you know when the game can't (2026-11-16).
- **Polestar** (GPL-3.0, https://github.com/fitzforge/polestar): which NPC five writ quests end at and where that
  NPC stands, from its WoW: Forever quest and NPC data, contributed by deanyo on 2026-11-18 (customers marked
  `src = "polestar"`). Only these facts were used; no Polestar code or files are included.
- **Bind on Forever** (https://bindonforever.com/), quest pages built from a newer QuestieDB build, for a few
  writs the installed QuestieDB didn't have yet.
- Your own game: map pins of writs you accepted (WritPathLearned).

## Ships recorded by WritPath players (WritPathData.lua)

Trips taken in game with WritPath's recorder and shipped as a starting point (2026-11-15): the Riverglades boat
both ways (Powderfuse Port <-> Steamwheedle Port), the Thunder Bluff - Undercity and Orgrimmar - Badlands zeppelins, road crossings (Barrens <-> Thousand Needles, Mulgore <->
Thunder Bluff, Undercity -> Tirisfal) and three flight times. Nothing in this file is copied from another addon.

## Map roads (WritPathRoads.lua)

Roads and trails for 43 outdoor zones, traced by hand (2026-11-19) from the classic zone maps as Wowhead serves them
(wow.zamimg.com), and for Forever's own zones from guildorder.com's WoW: Forever maps. Only the positions along each
road are kept, as map coordinates; no map images ship with WritPath.

## Flight points (WritPathData.lua, `flightNodes`)

Every flight point by taxi node id, with its zone and exact spot: ids, names and factions from public node lists
(RestedXP's among them), spots from QuestieDB's flight masters, and city flight masters plus a few QuestieDB lacks filled in by hand
(2026-11-16). Flight points never move, so WritPath always takes their spot from this table.

## Roads, ships and flight times (WritPathLearned)

Learned in your own game as you travel: zone crossings you ride through, ships you take, and how long
your flights take. What you've learned always wins over the RestedXP data above.

## Optional addons WritPath works with (read at runtime, not copied)

- **Auctionator** (optional): its prices through its public API (`Auctionator.API.v1`) when its scan is newer than
  WritPath's own, and its saved full-scan time.
- **EllesmereUI**: window style through its public skinning API (`EllesmereUI.RegisterSkin`).
- **HereBeDragons**: map coordinate conversion, when another addon has loaded the library. Without it WritPath
  uses the game's own map API (C_Map), so RestedXP's crossings and ships work either way.
- **RestedXP**: until WritPath has seen a flight master's map on a continent, it reads which flight paths
  your character knows from RestedXP's saved variables (`RXPCData.flightPaths`), if RestedXP is installed.

## Art

- The navigation arrow (Media/arrow.tga) was drawn for WritPath.
- Icons are the game's own (Interface/Icons, GossipFrame and Minimap textures).
