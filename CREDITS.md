# WritPath credits

WritPath ships no other addon's code or art. It does include pathing data adapted from RestedXP (below),
under RestedXP's license. Everything else is facts gathered from public community sources, or something
WritPath reads from another addon at runtime when you have it installed.

## RestedXP pathing data (RXPData.lua)

**Adapted from RestedXP (RXPGuides), https://www.restedxp.com/**, licensed under Creative Commons
Attribution-NonCommercial-ShareAlike 4.0 International (CC BY-NC-SA 4.0,
https://creativecommons.org/licenses/by-nc-sa/4.0/).

- Zone crossings mined from RestedXP's WoW Forever leveling guides (waypoints in a row, in different zones,
  under 400 yards apart).
- Boat and zeppelin trips the guides take (the dock from each "Take the boat/zeppelin" step, the landing from the
  dock the trip back leaves from). Added 2026-11-15.
- RestedXP's recorded flight times between flight points.

RXPData.lua is adapted material and is shared under the same CC BY-NC-SA 4.0 license: credit RestedXP,
no commercial use, and share any changes to it under the same terms. WritPath uses this data only where it
hasn't learned the way in your own game. RestedXP does not endorse WritPath.

## Writ customers (WritDB.lua)

Which NPC takes each Craftsman's Writ, and in which zone, was gathered on 2026-11-14 and 2026-11-15 from:

- **Wowhead**: "Craftsman's Writs: Recipes, Rewards & Routes - WoW: Forever" by Serenal, and its reader comments
  (Nyatui, Drush, Domi98, EmmyBear, bubblebeard, Veru, HansHagbard, zebburr, Nagatoro, Slapthat, Moneybagz).
  https://www.wowhead.com/forever/guide/professions/craftsmans-writs-overview-recipes-rewards
- **Wowhead** item and quest tooltips (writ names, tiers, quests, requested items).
- **wowforever.gg** atlas NPC pages (customer coordinates). https://wowforever.gg/
- **QuestieDB** (GPL-3.0, https://github.com/Questie/Questie): which NPC takes each writ quest and where that
  NPC stands, read from its WoW Forever data on 2026-11-15 (customers marked `src = "questie"`). Only these facts
  were used; no QuestieDB code or files are included.
- **Bind on Forever** (https://bindonforever.com/), quest pages built from a newer QuestieDB build, for a few
  writs the installed QuestieDB didn't have yet.
- Your own game: map pins of writs you accepted (WritPathLearned).

## Ships recorded by WritPath players (WritPathData.lua)

Trips taken in game with WritPath's recorder and shipped as a starting point (2026-11-15): the Riverglades boat
between Powderfuse Port and Steamwheedle Port. Nothing in this file is copied from another addon.

## Roads, ships and flight times (WritPathLearned)

Learned in your own game as you travel: zone crossings you ride through, ships you take, and how long
your flights take. What you've learned always wins over the RestedXP data above.

## Optional addons WritPath works with (read at runtime, not copied)

- **Auctionator**: prices through its public API (`Auctionator.API.v1`), and its saved full-scan time.
- **EllesmereUI**: window style through its public skinning API (`EllesmereUI.RegisterSkin`).
- **HereBeDragons**: map coordinate conversion, when another addon has loaded the library. Without it WritPath
  uses the game's own map API (C_Map), so RestedXP's crossings and ships work either way.
- **RestedXP**: until WritPath has seen a flight master's map on a continent, it reads which flight paths
  your character knows from RestedXP's saved variables (`RXPCData.flightPaths`), if RestedXP is installed.

## Art

- The navigation arrow (Media/arrow.tga) was drawn for WritPath.
- Icons are the game's own (Interface/Icons, GossipFrame and Minimap textures).
