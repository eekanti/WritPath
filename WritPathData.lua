-- Travel data recorded in game by WritPath players and shipped with WritPath (2026-11-15).
-- Only trips taken in game go here; nothing is copied from another addon.
-- transports: { from zone, x, y (the dock), to zone, tx, ty (where you land) }. A map that is a whole continent
-- (1414 Kalimdor, 1415 Eastern Kingdoms) means the spot was recorded at sea; WritPath finds the zone itself.
WritPath_Data = {
  transports = {
    -- the Riverglades boat, ridden 2026-11-15: Powderfuse Port to Steamwheedle Port (Tanaris)
    { from = 2548, x = 80.5, y = 55.0, to = 1414, tx = 60.7, ty = 79.4 },
    -- the same boat back: Steamwheedle Port to Powderfuse Port (not ridden yet: the same two docks)
    { from = 1414, x = 60.7, y = 79.4, to = 2548, tx = 80.5, ty = 55.0 },
  },
}
