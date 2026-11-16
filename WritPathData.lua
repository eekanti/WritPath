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
}
