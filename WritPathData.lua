-- Travel data recorded in game by WritPath players and shipped with WritPath (2026-11-15).
-- Only trips taken in game go here; nothing is copied from another addon. What you learn in your own game
-- always wins over this file.
-- A map that is a whole continent (1414 Kalimdor, 1415 Eastern Kingdoms) means the spot was recorded at sea;
-- WritPath finds the zone itself.
WritPath_Data = {
  -- ships: { from zone, x, y (the dock), to zone, tx, ty (where you land) }
  transports = {
    -- the Riverglades boat, both ways: Powderfuse Port (Riverglades) <-> Steamwheedle Port (Tanaris)
    { from = 2548, x = 80.5, y = 55.0, to = 1414, tx = 60.7, ty = 79.4 },
    { from = 1446, x = 68.5, y = 23.3, to = 1415, tx = 62.6, ty = 66.7 },
    -- zeppelins: Thunder Bluff -> Undercity, Orgrimmar -> Badlands (ridden), and back (not ridden yet: same towers)
    { from = 1456, x = 41.3, y = 55.9, to = 1458, tx = 84.6, ty = 16.3 },
    { from = 1458, x = 84.6, y = 16.3, to = 1456, tx = 41.3, ty = 55.9 },
    { from = 1454, x = 59.4, y = 37.0, to = 1418, tx = 48.2, ty = 8.6 },
    { from = 1418, x = 48.2, y = 8.6, to = 1454, tx = 59.4, ty = 37.0 },
  },
  -- zone pairs with no road between them on Forever (later versions of the game added one): imported or guide
  -- data that says otherwise is ignored, unless you ride across yourself
  noRoad = {
    { 1433, 1435 },   -- Redridge Mountains / Swamp of Sorrows: only the mountain path below (2026-11-16)
  },
  -- paths that wind through mountains: waypoints on the "from" zone's map, in order, then the crossing
  paths = {
    -- Redridge Mountains -> Swamp of Sorrows (player, 2026-11-16): 77.1, 33.5, then 64.6, 24.2, then over at 94.3, 59.4
    { from = 1433, to = 1435, via = { { 77.1, 33.5 }, { 64.6, 24.2 } }, x = 94.3, y = 59.4 },
  },
  -- road crossings ridden: { from zone, to zone, x, y } (the spot on the zone you leave)
  crossings = {
    { from = 1413, to = 1441, x = 47.7, y = 95.4 },   -- The Barrens -> Thousand Needles
    { from = 1441, to = 1413, x = 40.3, y = 29.6 },   -- Thousand Needles -> The Barrens
    { from = 1456, to = 1412, x = 40.6, y = 12.1 },   -- Thunder Bluff -> Mulgore (lift)
    { from = 1412, to = 1456, x = 39.8, y = 29.2 },   -- Mulgore -> Thunder Bluff (lift)
    { from = 1458, to = 1420, x = 66.3, y = 0.8 },    -- Undercity -> Tirisfal Glades
    { from = 1431, to = 1434, x = 44.8, y = 84.6 },   -- Duskwood -> Stranglethorn Vale (the road south)
  },
  -- flight times in seconds between flight points (taxi node ids), either direction
  flights = {
    { 40, 30, 87 }, { 23, 22, 224 }, { 11, 21, 336 },
  },
  -- where every flight master stands (QuestieDB's WoW Forever data, GPL-3.0: facts only, 2026-11-16):
  -- { zone, x, y, faction (H, A or AH) }. A safety net for placing the flight points you know.
  flightMasters = {
    { 1413, 44.5, 59.1, "H" },   -- Omusa Thunderhorn, Wind Rider Master
    { 1413, 63.1, 37.2, "AH" },   -- Bragok, Flight Master
    { 1417, 45.7, 46.1, "A" },   -- Cedrik Prose, Gryphon Master
    { 1417, 73.0, 32.7, "H" },   -- Urda, Wind Rider Master
    { 1418, 4.0, 44.8, "H" },   -- Gorrik, Wind Rider Master
    { 1419, 65.5, 24.3, "A" },   -- Alexandra Constantine, Gryphon Master
    { 1421, 45.6, 42.6, "H" },   -- Karos Razok, Bat Handler
    { 1422, 42.9, 85.1, "A" },   -- Bibilfaz Featherwhistle, Gryphon Master
    { 1423, 70.5, 47.5, "H" },   -- Georgia, Bat Handler
    { 1423, 71.8, 49.6, "A" },   -- Khaelyn Steelwing, Gryphon Master
    { 1424, 49.3, 52.3, "A" },   -- Darla Harris, Gryphon Master
    { 1424, 60.1, 18.6, "H" },   -- Zarise, Bat Handler
    { 1425, 11.1, 46.1, "A" },   -- Guthrum Thunderfist, Gryphon Master
    { 1425, 81.7, 81.8, "H" },   -- Gorkas, Wind Rider Master
    { 1427, 34.8, 30.9, "H" },   -- Grisha, Wind Rider Master
    { 1427, 37.9, 30.9, "A" },   -- Lanie Reed, Gryphon Master
    { 1428, 65.7, 24.2, "H" },   -- Vahgruk, Wind Rider Master
    { 1428, 84.3, 68.3, "A" },   -- Borgus Stoutarm, Gryphon Master
    { 1431, 77.5, 44.3, "A" },   -- Felicia Maline, Gryphon Master
    { 1432, 33.9, 51.0, "A" },   -- Thorgrum Borrelson, Gryphon Master
    { 1434, 26.9, 77.1, "H" },   -- Gringer, Wind Rider Master
    { 1434, 27.5, 77.8, "A" },   -- Gyll, Gryphon Master
    { 1434, 32.5, 29.4, "H" },   -- Thysta, Wind Rider Master
    { 1435, 46.1, 54.8, "H" },   -- Breyk, Wind Rider Master
    { 1436, 56.5, 52.6, "A" },   -- Thor, Gryphon Master
    { 1437, 9.5, 59.7, "A" },   -- Shellei Brondir, Gryphon Master
    { 1438, 58.4, 94.0, "A" },   -- Vesprystus, Hippogryph Master
    { 1439, 36.3, 45.6, "A" },   -- Caylais Moonfeather, Hippogryph Master
    { 1440, 12.2, 33.8, "H" },   -- Andruk, Wind Rider Master
    { 1440, 34.4, 48.0, "A" },   -- Daelyshia, Hippogryph Master
    { 1440, 73.2, 61.6, "H" },   -- Vhulgra, Wind Rider Master
    { 1441, 45.1, 49.1, "H" },   -- Nyse, Wind Rider Master
    { 1442, 36.4, 7.2, "A" },   -- Teloren, Hippogryph Master
    { 1442, 45.1, 59.8, "H" },   -- Tharm, Wind Rider Master
    { 1443, 21.6, 74.1, "H" },   -- Thalon, Wind Rider Master
    { 1443, 64.7, 10.5, "A" },   -- Baritanas Skyriver, Hippogryph Master
    { 1444, 30.2, 0.0, "A" },   -- Fyldren Moonfeather, Hippogryph Master
    { 1444, 75.5, 44.4, "H" },   -- Shyn, Wind Rider Master
    { 1445, 35.6, 31.9, "H" },   -- Shardi, Wind Rider Master
    { 1445, 67.5, 51.3, "A" },   -- Baldruc, Gryphon Master
    { 1446, 51.0, 29.3, "A" },   -- Bera Stonehammer, Gryphon Master
    { 1446, 51.6, 25.4, "H" },   -- Bulkrek Ragefist, Wind Rider Master
    { 1447, 11.9, 77.6, "A" },   -- Jarrodenus, Hippogryph Master
    { 1447, 22.0, 49.6, "H" },   -- Kroum, Wind Rider Master
    { 1448, 34.4, 54.0, "H" },   -- Brakkar, Wind Rider Master
    { 1448, 62.5, 24.2, "A" },   -- Mishellena, Hippogryph Master
    { 1449, 45.2, 5.8, "AH" },   -- Gryfe, Flight Master
    { 1450, 32.1, 66.6, "H" },   -- Faustron, Wind Rider Master
    { 1450, 44.1, 45.2, "AH" },   -- Silva Fil'naveth, Darnassus Flight Master
    { 1450, 44.3, 45.9, "AH" },   -- Bunthen Plainswind, Thunder Bluff Flight Master
    { 1450, 48.1, 67.3, "A" },   -- Sindrayl, Hippogryph Master
    { 1451, 48.7, 36.7, "H" },   -- Runk Windtamer, Wind Rider Master
    { 1451, 50.6, 34.5, "A" },   -- Cloud Skydancer, Hippogryph Master
    { 1452, 60.5, 36.3, "H" },   -- Yugrek, Wind Rider Master
    { 1452, 62.3, 36.6, "A" },   -- Maethrya, Hippogryph Master
    { 1453, 71.3, 72.2, "A" },   -- Dungar Longdrink, Gryphon Master
    { 1454, 45.1, 63.9, "H" },   -- Doras, Wind Rider Master
    { 1456, 47.0, 49.8, "H" },   -- Tal, Wind Rider Master
  },
  -- every flight point, by the game's taxi node id: { zone, x, y, faction, name as the flight map shows it }.
  -- Flight points never move, so WritPath always takes their spot from here; your game only says which you know.
  -- Built 2026-11-16 from RestedXP's node list (ids, names, factions) and QuestieDB's flight masters (spots),
  -- with city flight masters and a few QuestieDB lacks filled in by hand.
  flightNodes = {
    [2] = { 1453, 71.3, 72.2, "A", "Stormwind, Elwynn" },   -- Dungar Longdrink
    [4] = { 1436, 56.5, 52.6, "A", "Sentinel Hill, Westfall" },   -- Thor
    [5] = { 1433, 30.6, 59.4, "A", "Lakeshire, Redridge" },   -- Ariena Stormfeather
    [6] = { 1455, 55.5, 47.8, "A", "Ironforge, Dun Morogh" },   -- Gryth Thurden
    [7] = { 1437, 9.5, 59.7, "A", "Menethil Harbor, Wetlands" },   -- Shellei Brondir
    [8] = { 1432, 33.9, 51.0, "A", "Thelsamar, Loch Modan" },   -- Thorgrum Borrelson
    [10] = { 1421, 45.6, 42.6, "H", "The Sepulcher, Silverpine Forest" },   -- Karos Razok
    [11] = { 1458, 63.2, 48.6, "H", "Undercity, Tirisfal" },   -- Michael Garrett
    [12] = { 1431, 77.5, 44.3, "A", "Darkshire, Duskwood" },   -- Felicia Maline
    [13] = { 1424, 60.1, 18.6, "H", "Tarren Mill, Hillsbrad" },   -- Zarise
    [14] = { 1424, 49.3, 52.3, "A", "Southshore, Hillsbrad" },   -- Darla Harris
    [16] = { 1417, 45.7, 46.1, "A", "Refuge Pointe, Arathi" },   -- Cedrik Prose
    [17] = { 1417, 73.0, 32.7, "H", "Hammerfall, Arathi" },   -- Urda
    [18] = { 1434, 26.9, 77.1, "H", "Booty Bay, Stranglethorn" },   -- Gringer
    [19] = { 1434, 27.5, 77.8, "A", "Booty Bay, Stranglethorn" },   -- Gyll
    [20] = { 1434, 32.5, 29.4, "H", "Grom'gol, Stranglethorn" },   -- Thysta
    [21] = { 1418, 4.0, 44.8, "H", "Kargath, Badlands" },   -- Gorrik
    [22] = { 1456, 47.0, 49.8, "H", "Thunder Bluff, Mulgore" },   -- Tal
    [23] = { 1454, 45.1, 63.9, "H", "Orgrimmar, Durotar" },   -- Doras
    [25] = { 1413, 51.5, 30.3, "H", "Crossroads, The Barrens" },   -- Devrak
    [26] = { 1439, 36.3, 45.6, "A", "Auberdine, Darkshore" },   -- Caylais Moonfeather
    [27] = { 1438, 58.4, 94.0, "A", "Rut'theran Village, Teldrassil" },   -- Vesprystus
    [28] = { 1440, 34.4, 48.0, "A", "Astranaar, Ashenvale" },   -- Daelyshia
    [29] = { 1442, 45.1, 59.8, "H", "Sun Rock Retreat, Stonetalon Mountains" },   -- Tharm
    [30] = { 1441, 45.1, 49.1, "H", "Freewind Post, Thousand Needles" },   -- Nyse
    [31] = { 1444, 89.5, 45.8, "A", "Thalanaar, Feralas" },   -- Thyssiana
    [32] = { 1445, 67.5, 51.3, "A", "Theramore, Dustwallow Marsh" },   -- Baldruc
    [33] = { 1442, 36.4, 7.2, "A", "Stonetalon Peak, Stonetalon Mountains" },   -- Teloren
    [37] = { 1443, 64.7, 10.5, "A", "Nijel's Point, Desolace" },   -- Baritanas Skyriver
    [38] = { 1443, 21.6, 74.1, "H", "Shadowprey Village, Desolace" },   -- Thalon
    [39] = { 1446, 51.0, 29.3, "A", "Gadgetzan, Tanaris" },   -- Bera Stonehammer
    [40] = { 1446, 51.6, 25.4, "H", "Gadgetzan, Tanaris" },   -- Bulkrek Ragefist
    [41] = { 1444, 30.2, 43.2, "A", "Feathermoon, Feralas" },   -- Fyldren Moonfeather
    [42] = { 1444, 75.5, 44.4, "H", "Camp Mojache, Feralas" },   -- Shyn
    [43] = { 1425, 11.1, 46.1, "A", "Aerie Peak, The Hinterlands" },   -- Guthrum Thunderfist
    [44] = { 1447, 22.0, 49.6, "H", "Valormok, Azshara" },   -- Kroum
    [45] = { 1419, 65.5, 24.3, "A", "Nethergarde Keep, Blasted Lands" },   -- Alexandra Constantine
    [48] = { 1448, 34.4, 54.0, "H", "Bloodvenom Post, Felwood" },   -- Brakkar
    [49] = { 1450, 48.1, 67.3, "A", "Nighthaven, Moonglade" },   -- Sindrayl
    [52] = { 1452, 62.3, 36.6, "A", "Everlook, Winterspring" },   -- Maethrya
    [53] = { 1452, 60.5, 36.3, "H", "Everlook, Winterspring" },   -- Yugrek
    [55] = { 1445, 35.6, 31.9, "H", "Brackenwall Village, Dustwallow Marsh" },   -- Shardi
    [56] = { 1435, 46.1, 54.8, "H", "Stonard, Swamp of Sorrows" },   -- Breyk
    [58] = { 1440, 12.2, 33.8, "H", "Zoram'gar Outpost, Ashenvale" },   -- Andruk
    [61] = { 1440, 73.2, 61.6, "H", "Splintertree Post, Ashenvale" },   -- Vhulgra
    [64] = { 1447, 11.9, 77.6, "A", "Talrendis Point, Azshara" },   -- Jarrodenus
    [65] = { 1448, 62.5, 24.2, "A", "Talonbranch Glade, Felwood" },   -- Mishellena
    [66] = { 1422, 42.9, 85.1, "A", "Chillwind Camp, Western Plaguelands" },   -- Bibilfaz Featherwhistle
    [67] = { 1423, 71.8, 49.6, "A", "Light's Hope Chapel, Eastern Plaguelands" },   -- Khaelyn Steelwing
    [68] = { 1423, 70.5, 47.5, "H", "Light's Hope Chapel, Eastern Plaguelands" },   -- Georgia
    [69] = { 1450, 44.3, 45.9, "H", "Nighthaven, Moonglade" },   -- Bunthen Plainswind
    [70] = { 1428, 65.7, 24.2, "H", "Flame Crest, Burning Steppes" },   -- Vahgruk
    [71] = { 1428, 84.3, 68.3, "A", "Morgan's Vigil, Burning Steppes" },   -- Borgus Stoutarm
    [72] = { 1451, 48.7, 36.7, "H", "Cenarion Hold, Silithus" },   -- Runk Windtamer
    [73] = { 1451, 50.6, 34.5, "A", "Cenarion Hold, Silithus" },   -- Cloud Skydancer
    [74] = { 1427, 37.9, 30.9, "A", "Thorium Point, Searing Gorge" },   -- Lanie Reed
    [75] = { 1427, 34.8, 30.9, "H", "Thorium Point, Searing Gorge" },   -- Grisha
    [76] = { 1425, 81.7, 81.8, "H", "Revantusk Village, The Hinterlands" },   -- Gorkas
    [77] = { 1413, 44.5, 59.1, "H", "Camp Taurajo, The Barrens" },   -- Omusa Thunderhorn
    [79] = { 1449, 45.2, 5.8, "AH", "Marshal's Refuge, Un'Goro Crater" },   -- Gryfe
    [80] = { 1413, 63.1, 37.2, "AH", "Ratchet, The Barrens" },   -- Bragok
    [3203] = { 2548, 57.9, 44.8, "H", "Rog'mar, Riverglades" },   -- Grakna (Forever)
  },
}
