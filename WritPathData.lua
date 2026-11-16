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
  },
  -- flight times in seconds between flight points (taxi node ids), either direction
  flights = {
    { 40, 30, 87 }, { 23, 22, 224 }, { 11, 21, 336 },
  },
}
