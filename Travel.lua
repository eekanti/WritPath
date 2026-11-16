-- WritPath travel: how to actually get from A to B.
-- A graph of the places you pass through, with travel time as the cost. What you've learned in your own
-- game comes first; the shipped travel facts (TravelFacts.lua) fill in the rest:
--   road crossings between zones   recorded when you ride from one zone into the next, plus the crossings
--                                  RestedXP's leveling guides walk you through
--   boats and zeppelins            recorded when you cross to the other continent by ship
--   flight times                   recorded when you land after a flight, else RestedXP's recorded times
--   your flight paths              recorded at any flight master's map (RestedXP's list, if installed, only
--                                  until WritPath has seen a flight map on that continent)
-- Inside one zone you ride in a straight line. The cheapest path becomes waypoint steps: one per zone
-- crossing, ship or flight. Where WritPath hasn't learned the way yet, the arrow points straight at the stop.

local T = {}
WritPath_Travel = T
local RIDE, FLY, FLIGHT_OVERHEAD, CROSS, SAIL = 9, 28, 45, 5, 300   -- yards/s, yards/s, s, s, s
local LEARN_FP = 20     -- seconds to talk to a new flight master before taking off
local UNKNOWN = 1.3    -- riding straight through zones whose roads WritPath hasn't learned: assume 30% longer
local HOSTILE = 1200   -- extra seconds for a dock in the other faction's town: use it only when nothing else works
-- zones whose dock is in a faction town (classic): Southshore, Menethil, Auberdine, Rut'theran, Theramore,
-- Stormwind / Orgrimmar's and the Undercity's zeppelin towers, Grom'gol
local ALLIANCE_DOCKS = { [1424] = true, [1437] = true, [1439] = true, [1438] = true, [1445] = true, [1453] = true }
local HORDE_DOCKS = { [1411] = true, [1420] = true, [1412] = true }

---------------------------------------------------------------- points
local function HBD() return LibStub and LibStub("HereBeDragons-2.0", true) end

local function MapInfo(m) return m and C_Map.GetMapInfo(m) end

-- caves and city sub-maps belong to the zone around them
local function ZoneOf(m)
  local zoneType = Enum and Enum.UIMapType and Enum.UIMapType.Zone or 3
  local info = MapInfo(m)
  while info and info.mapType and info.mapType > zoneType and info.parentMapID and info.parentMapID > 0 do
    m = info.parentMapID; info = MapInfo(m)
  end
  return m
end
T.ZoneOf = ZoneOf

-- a place: zone map + percent coordinates, plus where that is in the world
function T.Point(map, x, y)
  local hbd = HBD()
  if hbd then
    local wx, wy, inst = hbd:GetWorldCoordinatesFromZone(x / 100, y / 100, map)
    if wx then return { map = map, x = x, y = y, inst = inst, wx = wx, wy = wy } end
  end
  -- a map HereBeDragons doesn't know (Forever's continent maps, new zones): the game's own API, turned into
  -- HereBeDragons' axes when the library is in use (its world x/y are the game's y/x), so every point on the
  -- route map is measured the same way
  local ok, cont, v = pcall(C_Map.GetWorldPosFromMapPos, map, CreateVector2D(x / 100, y / 100))
  if ok and v then
    local a, b = v:GetXY()
    if hbd then a, b = b, a end
    return { map = map, x = x, y = y, inst = cont, wx = a, wy = b }
  end
end

-- seconds for a flight between two flight points (either direction): what it took you, else RestedXP's time
local RXP = WritPath_TravelFacts or {}
local function FlightTime(a, b)
  if not (a and b) then return nil end
  local t = WritPathLearned and WritPathLearned.flights or {}
  local mine = (t[a] and t[a][b]) or (t[b] and t[b][a])
  if mine then return mine end
  for _, f in ipairs(WritPath_Data and WritPath_Data.flights or {}) do   -- recorded by WritPath players
    if (f[1] == a and f[2] == b) or (f[1] == b and f[2] == a) then return f[3] end
  end
  local r = RXP.flightTimes and RXP.flightTimes[UnitFactionGroup("player")] or {}
  return (r[a] and r[a][b]) or (r[b] and r[b][a])
end
T.FlightTime = FlightTime

-- a continent (or bigger) map rather than a zone: what the game reports while you're out at sea
local function IsContinent(m)
  local info = MapInfo(m)
  local contType = Enum and Enum.UIMapType and Enum.UIMapType.Continent or 2
  return info and info.mapType and info.mapType <= contType or false
end
T.IsContinent = IsContinent

function T.PlayerPoint()
  local m = C_Map.GetBestMapForUnit("player"); if not m then return nil end
  local z = ZoneOf(m)
  local p = C_Map.GetPlayerMapPosition(z, "player") or C_Map.GetPlayerMapPosition(m, "player")
  if not p then return nil end
  local x, y = p:GetXY()
  local pt = T.Point(z, x * 100, y * 100)
  if pt and IsContinent(z) then pt.sea = true end
  return pt
end

local function Dist(a, b) return math.sqrt((a.wx - b.wx) ^ 2 + (a.wy - b.wy) ^ 2) end
T.Dist = Dist

---------------------------------------------------------------- flight paths you know
-- Which flight paths you have: WritPath records them itself. Opening any flight master's map lists every
-- flight point on that continent with whether you know it, so one visit per continent is enough, and
-- learning a new one opens the map again. Until WritPath has seen a flight map on a continent, it borrows
-- RestedXP's list for that continent (RXPCData.flightPaths) if RestedXP is installed; after that, never.
-- Where each one is: the flight map itself, or the world map's flight points (C_TaxiMap.GetTaxiNodesForMap
-- works anywhere), turned into zone coordinates once and saved.

local function ContinentOf(m)
  local contType = Enum and Enum.UIMapType and Enum.UIMapType.Continent or 2
  local info = MapInfo(m)
  while info and info.mapType and info.mapType > contType and info.parentMapID and info.parentMapID > 0 do
    m = info.parentMapID; info = MapInfo(m)
  end
  return (info and info.mapType == contType) and m or nil
end

-- the zone under a spot on a continent map (0-1). The game's own lookup first; when that gives back the
-- continent itself (it does on Forever's continent maps), the smallest zone whose outline holds the spot.
local function ZoneAt(cont, cx, cy)
  local here = C_Map.GetMapInfoAtPosition and C_Map.GetMapInfoAtPosition(cont, cx, cy)
  local z = here and ZoneOf(here.mapID)
  if z and not IsContinent(z) then return z end
  if not (C_Map.GetMapChildrenInfo and C_Map.GetMapRectOnMap) then return nil end
  local best, area
  local ok, kids = pcall(C_Map.GetMapChildrenInfo, cont, Enum and Enum.UIMapType and Enum.UIMapType.Zone or 3, false)
  for _, k in ipairs(ok and kids or {}) do
    local ok2, l, r, t, b = pcall(C_Map.GetMapRectOnMap, k.mapID, cont)
    if ok2 and l and cx >= l and cx <= r and cy >= t and cy <= b then
      local a = (r - l) * (b - t)
      if not area or a < area then best, area = k.mapID, a end
    end
  end
  return best
end

-- a point given in one map's coordinates (0-1, may lie outside that map) -> the zone it is in, zone percent
local function PlaceByGame(srcMap, px, py)
  local ok, inst, world = pcall(C_Map.GetWorldPosFromMapPos, srcMap, CreateVector2D(px, py))
  if not (ok and world) then return nil end
  local cont = ContinentOf(srcMap); if not cont then return nil end
  local _, cpos = C_Map.GetMapPosFromWorldPos(inst, world, cont)
  if not cpos then return nil end
  local zone = ZoneAt(cont, cpos:GetXY())
  if not zone then return nil end
  local _, zpos = C_Map.GetMapPosFromWorldPos(inst, world, zone)
  if not zpos then return nil end
  local zx, zy = zpos:GetXY()
  return zone, math.floor(zx * 1000 + 0.5) / 10, math.floor(zy * 1000 + 0.5) / 10
end

local function Place(srcMap, px, py)
  local hbd = HBD(); if not hbd then return PlaceByGame(srcMap, px, py) end
  -- any map HereBeDragons doesn't know (Forever's continent maps 1463/1464, new zones): the game's own API
  local wx, wy, inst = hbd:GetWorldCoordinatesFromZone(px, py, srcMap)
  if not wx then return PlaceByGame(srcMap, px, py) end
  local cont = ContinentOf(srcMap); if not cont then return nil end
  local cx, cy = hbd:GetZoneCoordinatesFromWorld(wx, wy, cont, true)
  if not cx then return PlaceByGame(srcMap, px, py) end
  local zone = ZoneAt(cont, cx, cy)
  if not zone then return nil end
  local zx, zy = hbd:GetZoneCoordinatesFromWorld(wx, wy, zone, true)
  if not zx then return PlaceByGame(srcMap, px, py) end
  return zone, math.floor(zx * 1000 + 0.5) / 10, math.floor(zy * 1000 + 0.5) / 10
end

T.Place = Place

-- RestedXP's world coordinates (HereBeDragons' system) -> percent on a zone map. Uses HereBeDragons when
-- another addon has loaded it, otherwise the game's own map API (HereBeDragons' world x/y are the game's y/x).
local function WorldToZone(zone, inst, hx, hy)
  local hbd = HBD()
  if hbd then
    local zx, zy = hbd:GetZoneCoordinatesFromWorld(hx, hy, zone, true)
    if zx then return zx * 100, zy * 100 end
    return nil
  end
  local ok, _, pos = pcall(C_Map.GetMapPosFromWorldPos, inst, CreateVector2D(hy, hx), zone)
  if ok and pos then local zx, zy = pos:GetXY(); return zx * 100, zy * 100 end
end
T.WorldToZone = WorldToZone

local function ContinentOfFP(f) return f and f.map and ContinentOf(f.map) end

-- The flight paths this character knows: WritPathChar.fp (saved per character), the one place WritPath keeps
-- them. Filled in automatically by what the game shows: every flight map you open, "New flight path
-- discovered!", and each flight you take (you can only fly between flight paths you have). Never removed.
-- Older WritPath versions kept them account-wide; those move to the first character that logs in, once.
-- If RestedXP is installed its list is copied in once as a head start; it's never needed.
local function Char()
  WritPathChar = WritPathChar or {}
  WritPathChar.fp = WritPathChar.fp or {}
  local C = WritPathChar.fp
  if not WritPathChar.migrated then
    WritPathChar.migrated = true
    for id, f in pairs(WritPathLearned and WritPathLearned.fp or {}) do
      if type(f) == "table" and f.own == true then
        C[id] = C[id] or { name = f.name, src = "migrated" }
        f.own = nil
      end
    end
  end
  if not WritPathChar.rxpSeeded and RXPCData and RXPCData.flightPaths then
    WritPathChar.rxpSeeded = true
    for id, name in pairs(RXPCData.flightPaths) do C[id] = C[id] or { name = name, src = "restedxp" } end
  end
  return C
end
T.CharFlightPaths = Char

-- the other faction's flight points can't be yours (the flight map sometimes lists them)
local function OurFaction(id)
  local n = WritPath_Data and WritPath_Data.flightNodes and WritPath_Data.flightNodes[id]
  if not n then return true end
  local mine = UnitFactionGroup("player") == "Horde" and "H" or "A"
  return n[4] == mine or n[4] == "AH"
end

-- record a flight path as yours; true when it's new
function T.MarkKnown(id, name, src)
  if not (id and OurFaction(id)) then return false end
  local C = Char()
  if C[id] then
    -- seen by WritPath itself now: no longer only RestedXP's word for it
    if type(C[id]) == "table" and C[id].src == "restedxp" and src then C[id].src = src end
    return false
  end
  C[id] = { name = name, src = src or "map", t = time and time() or nil }
  T.Reset()
  return true
end

-- id -> name for every flight path you know; second result: how many came from WritPath's own records
local function Known()
  local known, own = {}, 0
  for id, v in pairs(Char()) do
    known[id] = (type(v) == "table" and v.name) or true
    if not (type(v) == "table" and v.src == "restedxp") then own = own + 1 end
  end
  -- flags left in the old account-wide place (older saved data)
  for id, f in pairs(WritPathLearned and WritPathLearned.fp or {}) do
    if type(f) == "table" and f.own == true and not known[id] then known[id] = f.name or true; own = own + 1 end
  end
  return known, own
end

-- where a flight point is. Flight points never move: the fixed table (WritPathData.lua) always wins; only a
-- point it doesn't list (a new one) uses the spot WritPath worked out in game.
local function FlightSpot(id)
  local n = WritPath_Data and WritPath_Data.flightNodes and WritPath_Data.flightNodes[id]
  if n then return n[1], n[2], n[3], n[5] end
  local f = WritPathLearned and WritPathLearned.fp and WritPathLearned.fp[id]
  if type(f) == "table" and f.map and f.x and not IsContinent(f.map) then return f.map, f.x, f.y, f.name end
end
T.FlightSpot = FlightSpot

-- a spot in game world coordinates (x, y as the game's own API gives them) on a continent instance (0 = Eastern
-- Kingdoms, 1 = Kalimdor) -> the zone it is in, zone percent
local function PlaceWorld(inst, wx, wy)
  local v = CreateVector2D(wx, wy)
  for _, cont in ipairs(inst == 0 and { 1415, 1463 } or { 1414, 1464 }) do
    local ok, _, cpos = pcall(C_Map.GetMapPosFromWorldPos, inst, v, cont)
    if ok and cpos then
      local cx, cy = cpos:GetXY()
      if cx >= 0 and cx <= 1 and cy >= 0 and cy <= 1 then
        local zone = ZoneAt(cont, cx, cy)
        if zone and not IsContinent(zone) then
          local ok2, _, zpos = pcall(C_Map.GetMapPosFromWorldPos, inst, v, zone)
          if ok2 and zpos then
            local zx, zy = zpos:GetXY()
            return zone, math.floor(zx * 1000 + 0.5) / 10, math.floor(zy * 1000 + 0.5) / 10
          end
        end
      end
    end
  end
end

-- fill in positions for known flight paths that don't have one yet
local function LocateFlightPaths()
  WritPathLearned.fp = WritPathLearned.fp or {}
  -- repair: a flight point saved on a whole continent map instead of its zone (older versions did this on
  -- Forever) is moved onto its zone, or forgotten so the world map places it again below
  for _, f in pairs(WritPathLearned.fp) do
    if type(f) == "table" and f.map and IsContinent(f.map) then
      local z, x, y
      if f.x and f.y then z, x, y = Place(f.map, f.x / 100, f.y / 100) end
      if z and not IsContinent(z) then f.map, f.x, f.y = z, x, y else f.map, f.x, f.y = nil, nil, nil end
    end
  end
  local known = Known()
  local function Set(id, name, zone, x, y)   -- keeps what's already known about it (whether it's yours)
    local f = WritPathLearned.fp[id]
    if f then f.map, f.x, f.y = zone, x, y; f.name = f.name or name
    else WritPathLearned.fp[id] = { name = name, map = zone, x = x, y = y, src = "map" } end
  end
  local function Missing() for id in pairs(known) do if not (WritPathLearned.fp[id] and WritPathLearned.fp[id].map) then return true end end end
  if Missing() and C_TaxiMap and C_TaxiMap.GetTaxiNodesForMap then
    for _, cont in ipairs({ 1414, 1415, 1463, 1464 }) do   -- the classic continent maps, and Forever's
      local ok, list = pcall(C_TaxiMap.GetTaxiNodesForMap, cont)
      for _, n in ipairs(ok and list or {}) do
        local id = n.nodeID
        if id and known[id] and not (WritPathLearned.fp[id] and WritPathLearned.fp[id].map) and n.position then
          local zone, x, y = Place(cont, n.position:GetXY())
          if zone and not IsContinent(zone) then Set(id, n.name or (type(known[id]) == "string" and known[id]) or nil, zone, x, y) end
        end
      end
    end
  end
  -- RestedXP's list of where every flight point is (game world coordinates, by taxi node id): places any you
  -- know that the game couldn't
  if Missing() then
    for id in pairs(known) do
      if not (WritPathLearned.fp[id] and WritPathLearned.fp[id].map) then
        for inst, list in pairs(RXP.flightWorld or {}) do
          local t = list[id]
          if t then
            local zone, x, y = PlaceWorld(inst, t[1], t[2])
            if zone then Set(id, type(known[id]) == "string" and known[id] or nil, zone, x, y) end
          end
        end
      end
    end
  end
  -- the flight masters' own spots (WritPathData.lua): a known point near one is put exactly on it, and one the
  -- game couldn't place goes to the flight master of the zone its name ends in ("Kargath, Badlands")
  local FM = WritPath_Data and WritPath_Data.flightMasters or {}
  local mine = UnitFactionGroup("player") == "Horde" and "H" or "A"
  local function Ours(m) return m[4] == mine or m[4] == "AH" end
  for id in pairs(known) do
    local f = WritPathLearned.fp[id]
    if f and f.map then
      for _, m in ipairs(FM) do
        if m[1] == f.map and Ours(m) and math.abs(m[2] - f.x) < 4 and math.abs(m[3] - f.y) < 4 then f.x, f.y = m[2], m[3]; break end
      end
    else
      local name = (f and f.name) or (type(known[id]) == "string" and known[id]) or nil
      local zoneName = name and name:match(",%s*([^,]+)$")
      local hit, count = nil, 0
      for _, m in ipairs(FM) do
        local info = zoneName and Ours(m) and MapInfo(m[1])
        if info and info.name and info.name:sub(1, #zoneName) == zoneName then hit, count = m, count + 1 end
      end
      if hit and count == 1 then Set(id, name, hit[1], hit[2], hit[3]) end
    end
  end
end
T.LocateFlightPaths = LocateFlightPaths

-- /writs travel: what WritPath knows about getting around, in a few chat lines
function T.Report()
  LocateFlightPaths()
  local known = Known()
  local placed, lost = {}, {}
  for id, name in pairs(known) do
    local f = WritPathLearned.fp[id]
    local map, _, _, fixedName = FlightSpot(id)
    local label = fixedName or (f and f.name) or (type(name) == "string" and name) or ("node " .. id)
    if map then placed[#placed + 1] = label else lost[#lost + 1] = label end
  end
  table.sort(placed); table.sort(lost)
  local L = WritPathLearned or {}
  local D = WritPath_Data or {}
  local lines = {
    ("Flight paths you know: %d placed on the map%s."):format(#placed, #lost > 0 and (", " .. #lost .. " not placed: " .. table.concat(lost, ", ")) or ""),
    ("Road crossings: %d learned, %d from RestedXP, %d shipped. Ships: %d learned, %d from RestedXP, %d shipped."):format(
      #(L.crossings or {}), #(RXP.exits or {}), #(D.crossings or {}), #(L.transports or {}), #(RXP.ships or {}), #(D.transports or {})),
  }
  if not next(known) then lines[#lines + 1] = "Open any flight master's map once per continent so WritPath learns which flight paths you know." end
  return lines
end

-- at a flight master: record every flight path on the map you can fly to (the way RestedXP does it: the
-- nodes for the zone you're standing in)
-- Both ways the game offers are read, and a flight path is only ever added, never taken away: you can't
-- unlearn one, and the newer API has been seen to under-report on Forever (it listed only two of your Kalimdor
-- flight paths), so trusting its "unreachable" used to drop paths you have.
function T.RecordFlightPaths()
  WritPathLearned.fp = WritPathLearned.fp or {}
  WritPathLearned.fpSeen = WritPathLearned.fpSeen or {}
  local added = 0
  local function Mark(id, name, zone, x, y)
    if T.MarkKnown(id, name, "flight map") then added = added + 1 end
    -- where it is, for a flight point the fixed table doesn't list
    if zone and not IsContinent(zone) and OurFaction(id) then
      local f = WritPathLearned.fp[id] or {}
      f.name = f.name or name
      if not f.map then f.map, f.x, f.y = zone, x, y end
      WritPathLearned.fp[id] = f
    end
  end
  local m = (GetTaxiMapID and GetTaxiMapID()) or C_Map.GetBestMapForUnit("player")
  -- the newer API: node ids, positions and a state
  if m and C_TaxiMap and C_TaxiMap.GetAllTaxiNodes then
    local ok, list = pcall(C_TaxiMap.GetAllTaxiNodes, m)
    local S = Enum and Enum.FlightPathState or { Current = 0, Reachable = 1, Unreachable = 2 }
    for _, n in ipairs(ok and list or {}) do
      if n.nodeID and n.state ~= S.Unreachable then
        local zone, x, y
        if n.position then zone, x, y = Place(m, n.position:GetXY()) end
        Mark(n.nodeID, n.name, zone, x, y)
      end
    end
  end
  -- the classic API: every point on the open flight map by name, and whether you can fly there
  if NumTaxiNodes and TaxiNodeName and TaxiNodeGetType then
    local byName = {}
    for id, n in pairs(WritPath_Data and WritPath_Data.flightNodes or {}) do byName[(n[5] or ""):lower()] = id end
    for id, f in pairs(WritPathLearned.fp) do if type(f) == "table" and f.name then byName[f.name:lower()] = byName[f.name:lower()] or id end end
    for i = 1, NumTaxiNodes() or 0 do
      local name, kind = TaxiNodeName(i), TaxiNodeGetType(i)
      local id = name and byName[name:lower()]
      if id and (kind == "CURRENT" or kind == "REACHABLE") then Mark(id, name) end
    end
  end
  local cont = m and ContinentOf(ZoneOf(m) or m)
  if cont then WritPathLearned.fpSeen[cont] = time() end
  T.Reset()
  return added
end

---------------------------------------------------------------- the graph
local nodes, byZone, cache, roads

function T.Reset() nodes, byZone, cache, roads = nil, nil, nil, nil end

-- riding straight from one zone into another is only allowed when WritPath knows no roads for one of them:
-- between two zones with known roads the way goes over a road, a boat or a flight (a straight line across a
-- border runs into the mountains between Feralas and Un'Goro, Duskwood and Stranglethorn, ...)
local function ZoneName(m) local i = MapInfo(m); return i and i.name or "?" end
local function NoRoad(a, b)
  for _, r in ipairs(WritPath_Data and WritPath_Data.noRoad or {}) do
    if (r[1] == a and r[2] == b) or (r[1] == b and r[2] == a) then return true end
  end
  return false
end
T.NoRoad = NoRoad

local loose = false   -- set while looking for any way at all, when the known roads don't connect two places
local function Direct(za, zb)
  if za == zb then return true end
  if NoRoad(za, zb) then return false end   -- not even when looking for any way at all
  if loose then return true end
  return not (roads and roads[za] and roads[zb])
end
-- leaving the start, or reaching the end, by a straight ride: within that zone, or anywhere when WritPath knows
-- no roads there (so a roadless zone in between can't be used as a way round the rule)
local function Open(home, other)
  if home == other then return true end
  if NoRoad(home, other) then return false end
  if loose then return true end
  return not (roads and roads[home])
end
function T.Nodes() if not nodes then T.Build() end; return nodes end   -- for tests and debugging

local function Add(n)
  nodes[#nodes + 1] = n; n.i = #nodes; n.edges = {}
  byZone[n.zone] = byZone[n.zone] or {}; table.insert(byZone[n.zone], n)
  return n
end
local function Edge(a, b, cost, kind, legs) a.edges[#a.edges + 1] = { to = b, cost = cost, kind = kind, legs = legs } end

function T.Build()
  nodes, byZone, cache, roads = {}, {}, {}, {}
  local L = WritPathLearned or {}
  -- road crossings you've ridden: an exit on this side, an entry at the same spot on the far side, both ways
  for _, c in ipairs(L.crossings or {}) do
    -- an old record taken out at sea (map = a whole continent) isn't a road; an imported one where Forever has
    -- no road isn't either (one you rode yourself has no src, and stays)
    local p = not (IsContinent(c.from) or IsContinent(c.to)) and not (c.src and NoRoad(c.from, c.to)) and T.Point(c.from, c.x, c.y)
    if p then
      local exit = Add({ zone = c.from, p = p, kind = "exit", peer = c.to })
      local entry = Add({ zone = c.to, p = p, kind = "entry", peer = c.from })
      Edge(exit, entry, CROSS, "cross"); Edge(entry, exit, CROSS, "cross")
    end
  end
  -- crossings WritPath players have ridden (WritPathData.lua), both ways
  for _, c in ipairs(WritPath_Data and WritPath_Data.crossings or {}) do
    local p = not (IsContinent(c.from) or IsContinent(c.to)) and not NoRoad(c.from, c.to) and T.Point(c.from, c.x, c.y)
    if p then
      local exit = Add({ zone = c.from, p = p, kind = "exit", peer = c.to })
      local entry = Add({ zone = c.to, p = p, kind = "entry", peer = c.from })
      Edge(exit, entry, CROSS, "cross"); Edge(entry, exit, CROSS, "cross")
    end
  end
  -- mountain paths (WritPathData.lua): the first waypoint to the crossing, both ways, with a guide step for
  -- every waypoint so the arrow follows the path
  for _, c in ipairs(WritPath_Data and WritPath_Data.paths or {}) do
    local pts = {}
    for _, v in ipairs(c.via or {}) do pts[#pts + 1] = T.Point(c.from, v[1], v[2]) end
    local cross = T.Point(c.from, c.x, c.y)
    local ok = cross ~= nil
    for i = 1, #(c.via or {}) do if not pts[i] then ok = false end end
    if ok then
      local all = {}; for _, q in ipairs(pts) do all[#all + 1] = q end; all[#all + 1] = cross
      local len = 0; for i = 2, #all do len = len + Dist(all[i - 1], all[i]) end
      local cost = CROSS + len / RIDE
      local into, back = ZoneName(c.to), ZoneName(c.from)
      local function Way(q, i, n) return { at = q, into = c.from, text = ("{goto} Follow the path through the mountains (%d of %d): |cFF00FF25%.1f, %.1f|r"):format(i, n, q.x, q.y) } end
      -- there: the waypoints, then over the border
      local there = {}
      for i = 2, #pts do there[#there + 1] = Way(pts[i], i, #pts) end
      there[#there + 1] = { at = cross, into = c.to, cross = true, text = "{goto} Ride into |cFF00FF25" .. into .. "|r" }
      local a = Add({ zone = c.from, p = all[1], kind = "exit", peer = c.to, path = true })
      local b = Add({ zone = c.to, p = cross, kind = "entry", peer = c.from, path = true })
      Edge(a, b, cost, "cross", there)
      -- back: over the border, then the waypoints the other way round
      local backLegs = { { at = cross, into = c.from, cross = true, text = "{goto} Ride into |cFF00FF25" .. back .. "|r" } }
      for i = #pts, 1, -1 do backLegs[#backLegs + 1] = Way(pts[i], #pts - i + 1, #pts) end
      local a2 = Add({ zone = c.to, p = cross, kind = "exit", peer = c.from, path = true })
      local b2 = Add({ zone = c.from, p = all[1], kind = "entry", peer = c.to, path = true })
      Edge(a2, b2, cost, "cross", backLegs)
    end
  end
  -- crossings RestedXP's leveling guides use (world coordinates, placed on the zone you leave), both ways
  for _, c in ipairs(RXP.exits or {}) do
    local zx, zy
    if not NoRoad(c[1], c[2]) then zx, zy = WorldToZone(c[1], c[3], c[4], c[5]) end
    local p = zx and T.Point(c[1], zx, zy)
    if p then
      local exit = Add({ zone = c[1], p = p, kind = "exit", peer = c[2] })
      local entry = Add({ zone = c[2], p = p, kind = "entry", peer = c[1] })
      Edge(exit, entry, CROSS, "cross"); Edge(entry, exit, CROSS, "cross")
    end
  end
  -- ships you've taken, one way each (the way back is its own record); ships between the other faction's
  -- towns cost a lot more: guards on both ends
  local hostile = UnitFactionGroup("player") == "Horde" and ALLIANCE_DOCKS or HORDE_DOCKS
  local sailed = {}   -- from..to pairs you've taken yourself: those win over the shipped routes
  local function Sail(from, dock, to, land)
    local cost = SAIL + ((hostile[from] or hostile[to]) and HOSTILE or 0)
    Edge(Add({ zone = from, p = dock, kind = "dock" }), Add({ zone = to, p = land, kind = "land" }), cost, "sail")
  end
  -- a place recorded on a continent map (out at sea) -> the zone it's in
  local function OnZone(m, x, y)
    if not IsContinent(m) then return m, x, y end
    local z, zx, zy = Place(m, x / 100, y / 100)
    return z, zx, zy
  end
  for _, t in ipairs(L.transports or {}) do
    local from, x, y = OnZone(t.from, t.x, t.y)
    local to, tx, ty = OnZone(t.to, t.tx, t.ty)
    local dock, land = from and T.Point(from, x, y), to and T.Point(to, tx, ty)
    if dock and land then Sail(from, dock, to, land); sailed[from .. ">" .. to] = true end
  end
  -- ships WritPath players have recorded (WritPathData.lua), then the ones RestedXP's guides take
  for _, t in ipairs(WritPath_Data and WritPath_Data.transports or {}) do
    local from, x, y = OnZone(t.from, t.x, t.y)
    local to, tx, ty = OnZone(t.to, t.tx, t.ty)
    if from and to and not sailed[from .. ">" .. to] then
      local dock, land = T.Point(from, x, y), T.Point(to, tx, ty)
      if dock and land then Sail(from, dock, to, land); sailed[from .. ">" .. to] = true end
    end
  end
  for _, t in ipairs(RXP.ships or {}) do   -- { from, to, inst, wx, wy, landInst, landWx, landWy }
    if not sailed[t[1] .. ">" .. t[2]] then
      local x, y = WorldToZone(t[1], t[3], t[4], t[5])
      local tx, ty = WorldToZone(t[2], t[6], t[7], t[8])
      local dock, land = x and T.Point(t[1], x, y), tx and T.Point(t[2], tx, ty)
      if dock and land then Sail(t[1], dock, t[2], land) end
    end
  end
  -- flights between any two flight masters you know on the same continent
  local fps = {}
  LocateFlightPaths()
  local known = Known()
  for id in pairs(known) do
    local map, x, y, name = FlightSpot(id)
    local p = map and T.Point(map, x, y)
    if p then fps[#fps + 1] = Add({ zone = map, p = p, kind = "fp", name = name, fpid = id }) end
  end
  -- your faction's flight paths you haven't learned: riding up to one learns it, and you can take off from it
  -- straight away to any you know (never fly to one you don't have)
  local mine = UnitFactionGroup("player") == "Horde" and "H" or "A"
  for id, n in pairs(WritPath_Data and WritPath_Data.flightNodes or {}) do
    if not known[id] and (n[4] == mine or n[4] == "AH") then
      local p = T.Point(n[1], n[2], n[3])
      if p then fps[#fps + 1] = Add({ zone = n[1], p = p, kind = "fp", name = n[5], fpid = id, unlearned = true }) end
    end
  end
  for _, a in ipairs(fps) do
    for _, b in ipairs(fps) do
      if a ~= b and a.p.inst == b.p.inst and not b.unlearned then
        -- the time this flight took you (or RestedXP's time), otherwise a guess from distance; learning first
        -- takes a moment more
        local secs = FlightTime(a.fpid, b.fpid)
        Edge(a, b, (secs and (secs + 15) or (FLIGHT_OVERHEAD + Dist(a.p, b.p) / FLY)) + (a.unlearned and LEARN_FP or 0), "fly")
      end
    end
  end
  -- which zones have known roads (a crossing on either side)
  for _, n in ipairs(nodes) do if n.kind == "exit" or n.kind == "entry" then roads[n.zone] = true end end
  -- riding between any two places in the same zone
  for _, list in pairs(byZone) do
    for _, a in ipairs(list) do
      for _, b in ipairs(list) do
        if a ~= b and a.p.inst == b.p.inst then Edge(a, b, Dist(a.p, b.p) / RIDE, "ride") end
      end
    end
  end
end

-- shortest times from a place to every node (cached per place)
local function From(src)
  local key = src.map .. ":" .. src.x .. ":" .. src.y .. (loose and ":loose" or "")
  if cache[key] then return cache[key] end
  local dist, prev, done = {}, {}, {}
  -- start: ride to any known place on this continent; straight across a zone you haven't learned roads for
  -- costs a bit more, because the straight line may run into hills
  for _, n in ipairs(nodes) do
    if n.p.inst == src.inst and Open(src.map, n.zone) then dist[n.i] = Dist(src, n.p) / RIDE * (n.zone == src.map and 1 or UNKNOWN) end
  end
  while true do
    local u, best
    for i, d in pairs(dist) do if not done[i] and (not best or d < best) then u, best = i, d end end
    if not u then break end
    done[u] = true
    for _, e in ipairs(nodes[u].edges) do
      local nd = best + e.cost
      if not dist[e.to.i] or nd < dist[e.to.i] then dist[e.to.i], prev[e.to.i] = nd, { u, e } end
    end
  end
  cache[key] = { dist = dist, prev = prev }
  return cache[key]
end

-- seconds from a to b, and the last node before riding to b (nil when riding straight there)
local Time
function T.Time(a, b)
  local best, via, r = Time(a, b)
  if not best and a and b and a.inst == b.inst then
    -- the known roads don't connect these two: the old way (straight across, a bit slower) is all there is
    loose = true
    best, via, r = Time(a, b)
    loose = false
  end
  if not best then return 900 end   -- another continent and no ship learned yet: a rough guess
  return best, via, r
end
function Time(a, b)
  if not (a and b) then return 600 end
  if not nodes then T.Build() end
  -- straight there, or over the known roads, ships and flights and then straight to the stop
  local best = (a.inst == b.inst and Direct(a.map, b.map)) and Dist(a, b) / RIDE * (a.map == b.map and 1 or UNKNOWN) or nil
  local via
  local r = From(a)
  for _, n in ipairs(nodes) do
    local d = r.dist[n.i]
    if d and n.p.inst == b.inst and Open(b.map, n.zone) then
      d = d + Dist(n.p, b) / RIDE * (n.zone == b.map and 1 or UNKNOWN)
      if not best or d < best then best, via = d, n end
    end
  end
  return best, via, r
end


-- zeppelins and boats by where they leave from and where they land: { kind, where to board, where it lands }
local SHIP_NAMES = {
  [1411] = { [1434] = { "zeppelin", "the zeppelin tower outside Orgrimmar", "Grom'gol Base Camp" },
             [1420] = { "zeppelin", "the zeppelin tower outside Orgrimmar", "the Undercity zeppelin tower, Tirisfal Glades" } },
  [1420] = { [1434] = { "zeppelin", "the zeppelin tower outside the Undercity", "Grom'gol Base Camp" },
             [1411] = { "zeppelin", "the zeppelin tower outside the Undercity", "the Orgrimmar zeppelin tower, Durotar" } },
  [1434] = { [1411] = { "zeppelin", "the Grom'gol zeppelin tower", "the Orgrimmar zeppelin tower, Durotar" },
             [1420] = { "zeppelin", "the Grom'gol zeppelin tower", "the Undercity zeppelin tower, Tirisfal Glades" },
             [1413] = { "boat", "the Booty Bay dock", "Ratchet, The Barrens" } },
  [1413] = { [1434] = { "boat", "the Ratchet dock", "Booty Bay, Stranglethorn Vale" } },
  [1456] = { [1458] = { "zeppelin", "the Thunder Bluff zeppelin", "the Undercity" } },
  [1458] = { [1456] = { "zeppelin", "the Undercity zeppelin", "Thunder Bluff" } },
  [1454] = { [1418] = { "zeppelin", "the Orgrimmar zeppelin", "the Badlands" } },
  [1418] = { [1454] = { "zeppelin", "the Badlands zeppelin", "Orgrimmar" } },
  [2548] = { [1446] = { "boat", "the Powderfuse Port dock", "Steamwheedle Port, Tanaris" } },
  [1446] = { [2548] = { "boat", "the Steamwheedle Port dock", "Powderfuse Port, Riverglades" } },
}
local function ShipText(from, to)
  local n = SHIP_NAMES[from] and SHIP_NAMES[from][to]
  if not n then return "{boat} Take the boat or zeppelin to |cFF00FF25" .. ZoneName(to) .. "|r" end
  return ("{%s} Go to %s and take the %s to |cFF00FF25%s|r"):format(n[1] == "zeppelin" and "zeppelin" or "boat", n[2], n[1], n[3])
end
T.ShipText = ShipText

-- the waypoints on the way from a to b: { kind, at = point, into = zone, text }
function T.Legs(a, b)
  local _, via, r = T.Time(a, b)
  local legs = {}
  if not via then
    if a and b and a.inst ~= b.inst then legs[1] = { kind = "unknown", into = b.map } end
    return legs
  end
  local chain, i = {}, via.i
  while i and r.prev[i] do table.insert(chain, 1, { from = nodes[r.prev[i][1]], e = r.prev[i][2], to = nodes[i] }); i = r.prev[i][1] end
  -- the first known place the route rides to: if it's a road crossing and the route doesn't go over it as an
  -- edge, it still passes that border there
  local first = chain[1] and chain[1].from or via
  if (first.kind == "exit" or first.kind == "entry") and not (chain[1] and chain[1].e.kind == "cross") then
    local into = first.kind == "exit" and first.peer or first.zone
    legs[#legs + 1] = { kind = "cross", at = first.p, into = into, text = "{goto} Ride into |cFF00FF25" .. ZoneName(into) .. "|r" }
  end
  for _, c in ipairs(chain) do
    local k = c.e.kind
    if k == "cross" and c.e.legs then   -- a mountain path: start of the path, its waypoints, the border
      if not c.e.legs[1].cross then
        legs[#legs + 1] = { kind = "cross", at = c.from.p, into = c.from.zone,
                            text = ("{goto} Go to the path through the mountains: |cFF00FF25%.1f, %.1f|r"):format(c.from.p.x, c.from.p.y) }
      end
      for _, l in ipairs(c.e.legs) do legs[#legs + 1] = { kind = "cross", at = l.at, into = l.into, text = l.text } end
    elseif k == "cross" then
      legs[#legs + 1] = { kind = "cross", at = c.from.p, into = c.to.zone,
                          text = "{goto} Ride into |cFF00FF25" .. ZoneName(c.to.zone) .. "|r" }
    elseif k == "sail" then
      legs[#legs + 1] = { kind = "sail", at = c.from.p, into = c.to.zone,
                          text = ShipText(c.from.zone, c.to.zone) }
    elseif k == "fly" then
      local secs = FlightTime(c.from.fpid, c.to.fpid)
      local town = function(n) return (n or ""):match("^([^,]+)") or n end
      local mins = secs and (" (" .. math.floor(secs / 60 + 0.5) .. " min)") or ""
      if c.from.unlearned then   -- a flight path you don't have yet: learn it, then take off
        legs[#legs + 1] = { kind = "fly", at = c.from.p, into = c.to.zone, fp = c.from.name, fpid = c.from.fpid, learn = true,
                            text = "{fp} Learn the flight path at |cFF00FF25" .. (town(c.from.name) or "the flight master") .. "|r, then fly to |cFF00FF25"
                                   .. (town(c.to.name) or ZoneName(c.to.zone)) .. "|r" .. mins }
      else
        legs[#legs + 1] = { kind = "fly", at = c.from.p, into = c.to.zone, fp = c.from.name, fpid = c.from.fpid,
                            text = "{fly} Fly from |cFF00FF25" .. (c.from.name or "here") .. "|r to |cFF00FF25" .. (c.to.name or ZoneName(c.to.zone)) .. "|r" .. mins }
      end
    end
  end
  -- two crossings at the same spot (a border straight back out) say nothing useful twice
  for j = #legs, 2, -1 do
    if legs[j].kind == "cross" and legs[j - 1].kind == "cross" and Dist(legs[j].at, legs[j - 1].at) < 30 then table.remove(legs, j - 1) end
  end
  return legs
end

-- /writs leg: everything WritPath weighed for one leg, for finding out why a route looks wrong
function T.Explain(a, b)
  if not nodes then T.Build() end
  local out = {}
  local function P(p) return p and ("%s %.1f,%.1f inst %s world %.0f,%.0f"):format(tostring(p.map), p.x or -1, p.y or -1, tostring(p.inst), p.wx or 0, p.wy or 0) or "?" end
  local function N(n) return ("%s %s %.1f,%.1f%s"):format(n.kind, tostring(n.zone), n.p.x or -1, n.p.y or -1, n.name and (" " .. n.name) or (n.peer and (" ->" .. n.peer) or "")) end
  out[#out + 1] = "from " .. P(a) .. " | to " .. P(b)
  local count = {}
  for _, n in ipairs(nodes) do count[n.kind] = (count[n.kind] or 0) + 1 end
  local parts = {}; for k, v in pairs(count) do parts[#parts + 1] = k .. " " .. v end; table.sort(parts)
  out[#out + 1] = "map: " .. #nodes .. " places (" .. table.concat(parts, ", ") .. ")"
  if a and b and a.inst == b.inst then
    out[#out + 1] = ("straight: %d s (%d yd)"):format(math.floor(Dist(a, b) / RIDE * (a.map == b.map and 1 or UNKNOWN)), math.floor(Dist(a, b)))
  else out[#out + 1] = "straight: different continent" end
  local best, via, r = T.Time(a, b)
  out[#out + 1] = ("best: %s s%s"):format(tostring(best and math.floor(best)), via and (" via " .. N(via)) or " (straight)")
  if via then
    local i, chain = via.i, {}
    while i and r.prev[i] do local pr = r.prev[i]; table.insert(chain, 1, pr[2].kind .. " " .. N(nodes[i])); i = pr[1] end
    if i then table.insert(chain, 1, "start at " .. N(nodes[i])) end
    out[#out + 1] = "route: " .. table.concat(chain, " | ")
  end
  local function Nearest(p, kinds, k)
    local list = {}
    for _, n in ipairs(nodes) do if kinds[n.kind] and p and n.p.inst == p.inst then list[#list + 1] = { n = n, d = Dist(n.p, p) } end end
    table.sort(list, function(x, y) return x.d < y.d end)
    local s = {}
    for j = 1, math.min(k, #list) do s[#s + 1] = ("%s (%d yd)"):format(N(list[j].n), math.floor(list[j].d)) end
    return #s > 0 and table.concat(s, "; ") or "none"
  end
  out[#out + 1] = "flight points near start: " .. Nearest(a, { fp = true }, 3)
  out[#out + 1] = "flight points near end: " .. Nearest(b, { fp = true }, 3)
  out[#out + 1] = "docks near start: " .. Nearest(a, { dock = true }, 3)
  out[#out + 1] = "landings near end: " .. Nearest(b, { land = true }, 3)
  return out
end

-- the nearest flight path you have to a place, within maxYards (id, yards, name)
function T.NearKnown(p, maxYards)
  if not p then return nil end
  local best, bd, bn
  for id, name in pairs((Known())) do
    local map, x, y, fixed = FlightSpot(id)
    local q = map and T.Point(map, x, y)
    if q and q.inst == p.inst then
      local d = Dist(q, p)
      if d <= maxYards and (not bd or d < bd) then best, bd, bn = id, d, fixed or (type(name) == "string" and name) end
    end
  end
  return best, bd, bn
end

-- flight points of your faction in a zone that you haven't learned, nearest first from a place in it
function T.UnlearnedNear(p, maxYards)
  if not p then return nil end
  local known = Known()
  local mine = UnitFactionGroup("player") == "Horde" and "H" or "A"
  local best, bd
  for id, n in pairs(WritPath_Data and WritPath_Data.flightNodes or {}) do
    if not known[id] and n[1] == p.map and (n[4] == mine or n[4] == "AH") then
      local q = T.Point(n[1], n[2], n[3])
      local d = q and q.inst == p.inst and Dist(q, p)
      if d and d <= maxYards and (not bd or d < bd) then best, bd = { id = id, map = n[1], x = n[2], y = n[3], name = n[5] }, d end
    end
  end
  return best, bd
end

function T.KnownFlightPaths()
  local known, own = Known()
  local n = 0; for _ in pairs(known) do n = n + 1 end
  return n, own
end

function T.Learned()
  local L = WritPathLearned or {}
  local f = 0; for _, row in pairs(L.flights or {}) do for _ in pairs(row) do f = f + 1 end end
  return #(L.crossings or {}), #(L.transports or {}), f
end

---------------------------------------------------------------- learning the way as you travel
-- Every half second WritPath notes where you are. Changing zone a few yards from where you were is a road
-- crossing. Changing continent without a flight, a dungeon, a hearthstone, a portal or dying is a ship: the
-- dock is where you last stood waiting. Landing after a flight records how long it took.
local REC = { last = nil, still = nil, history = {}, flight = nil, teleport = 0 }
local NEAR_CROSS, NEAR_FP = 250, 120

local function Near(list, test) for _, e in ipairs(list) do if test(e) then return e end end end

local function RecordCrossing(a, b)
  WritPathLearned.crossings = WritPathLearned.crossings or {}
  local hit = Near(WritPathLearned.crossings, function(c)
    if not (c.from == a.map and c.to == b.map) then return false end
    local q = T.Point(c.from, c.x, c.y)
    return q and Dist(q, a) < 80
  end)
  if hit then hit.n = (hit.n or 1) + 1; return end
  table.insert(WritPathLearned.crossings, { from = a.map, to = b.map, x = math.floor(a.x * 10 + 0.5) / 10,
                                            y = math.floor(a.y * 10 + 0.5) / 10, n = 1, t = time() })
  T.Reset()
end

local function RecordShip(dock, land)
  WritPathLearned.transports = WritPathLearned.transports or {}
  local hit = Near(WritPathLearned.transports, function(t)
    if not (t.from == dock.map and t.to == land.map) then return false end
    local q = T.Point(t.from, t.x, t.y)
    return q and Dist(q, dock) < 150
  end)
  if hit then hit.n = (hit.n or 1) + 1; return end
  table.insert(WritPathLearned.transports, { from = dock.map, x = math.floor(dock.x * 10 + 0.5) / 10, y = math.floor(dock.y * 10 + 0.5) / 10,
                                             to = land.map, tx = math.floor(land.x * 10 + 0.5) / 10, ty = math.floor(land.y * 10 + 0.5) / 10,
                                             n = 1, t = time() })
  T.Reset()
end

-- the flight point of your faction you're standing at (within maxYards), known or not
function T.NearestNode(p, maxYards)
  if not p then return nil end
  local best, bd
  for id, n in pairs(WritPath_Data and WritPath_Data.flightNodes or {}) do
    if OurFaction(id) then
      local q = T.Point(n[1], n[2], n[3])
      if q and q.inst == p.inst then
        local d = Dist(q, p)
        if d <= (maxYards or NEAR_FP) and (not bd or d < bd) then best, bd = id, d end
      end
    end
  end
  return best, bd
end

local function NearestFP(p)
  if not p then return nil end
  local best, bd
  local known = Known()
  for id in pairs(known) do
    local map, x, y = FlightSpot(id)
    if map then
      local q = T.Point(map, x, y)
      if q and q.inst == p.inst then
        local d = Dist(q, p)
        if d < NEAR_FP and (not bd or d < bd) then best, bd = id, d end
      end
    end
  end
  return best
end

local function RecordFlight(a, b, secs)
  WritPathLearned.flights = WritPathLearned.flights or {}
  WritPathLearned.flights[a] = WritPathLearned.flights[a] or {}
  local old = WritPathLearned.flights[a][b]
  WritPathLearned.flights[a][b] = math.floor(old and (old + secs) / 2 or secs)
  T.Reset()
end

local function Poll()
  if not WritPathLearned then return end
  local now = GetTime()
  local p = T.PlayerPoint()
  local taxi = UnitOnTaxi("player") and true or false
  local dead = UnitIsDeadOrGhost and UnitIsDeadOrGhost("player")
  local inside = IsInInstance and IsInInstance()
  local last = REC.last

  -- flights: from the flight master you took off at to the one you landed at. You can only fly between flight
  -- paths you have, so both ends are yours.
  if taxi and not REC.onTaxi then
    local from = T.NearestNode(last, NEAR_FP) or NearestFP(last)
    if from then T.MarkKnown(from, nil, "flight") end
    REC.flight = { from = from, t = now }
  end
  if not taxi and REC.onTaxi and REC.flight and p then
    local to = T.NearestNode(p, NEAR_FP) or NearestFP(p)
    if to then T.MarkKnown(to, nil, "flight") end
    if REC.flight.from and to and to ~= REC.flight.from then RecordFlight(REC.flight.from, to, now - REC.flight.t) end
    REC.flight = nil
  end
  REC.onTaxi = taxi
  if not p or inside or p.sea then return end

  local clean = not taxi and not dead and not (last and last.taxi) and now - REC.teleport > 30
  if last and clean and p.map ~= last.map then
    if p.inst == last.inst then
      if Dist(p, last) < NEAR_CROSS and now - last.t < 5 then RecordCrossing(last, p) end
    elseif REC.still and now - REC.still.t < 600 then
      RecordShip(REC.still, p)   -- a ship: from where you last stood waiting
    end
  end

  -- where you last stood still for ten seconds (waiting at a dock looks like this)
  if last and Dist(p, last) < 2 then
    REC.stillSince = REC.stillSince or now
    if now - REC.stillSince >= 10 then REC.still = { map = p.map, x = p.x, y = p.y, inst = p.inst, wx = p.wx, wy = p.wy, t = now } end
  else
    REC.stillSince = nil
  end
  p.t, p.taxi = now, taxi
  REC.last = p
end


---------------------------------------------------------------- hearthstone and teleports
-- What takes you somewhere in one cast: the hearthstone (and a shaman's Astral Recall) to where it's bound, a
-- mage's city teleports (with a Rune of Teleportation), a druid's Teleport: Moonglade. The planner puts each on the
-- legs where it saves the most time, as its cooldown allows.
local HEARTH, RUNE, RECALL, MOONGLADE = 6948, 17031, 556, 18960
local MAGE = { [3567] = "Orgrimmar", [3563] = "Undercity", [3566] = "Thunder Bluff",
               [3561] = "Stormwind", [3562] = "Ironforge", [3565] = "Darnassus" }
local function ItemCount(id)
  return (C_Item and C_Item.GetItemCount and C_Item.GetItemCount(id)) or (GetItemCount and GetItemCount(id)) or 0
end
local function KnowsSpell(id) return (IsPlayerSpell and IsPlayerSpell(id)) or (IsSpellKnown and IsSpellKnown(id)) or false end
local function Left(start, dur)
  if not start or start == 0 or not dur or dur <= 1.5 then return 0 end   -- 1.5: just the global cooldown
  return math.max(0, start + dur - GetTime())
end
local function SpellLeft(id)
  if C_Spell and C_Spell.GetSpellCooldown then
    local c = C_Spell.GetSpellCooldown(id)
    if type(c) == "table" then return Left(c.startTime, c.duration), c.duration end
  end
  if GetSpellCooldown then local s, d = GetSpellCooldown(id); return Left(s, d), d end
  return 0
end
local function ItemLeft(id)
  local f = (C_Container and C_Container.GetItemCooldown) or GetItemCooldown
  if f then local s, d = f(id); return Left(s, d), d end
  return 0
end
-- cooldowns as the game shows them while they run (talents and gear change them), else the usual ones
local function Cooldown(key, seen, default)
  WritPathChar = WritPathChar or {}
  WritPathChar.cd = WritPathChar.cd or {}
  if seen and seen > 60 then WritPathChar.cd[key] = seen end
  return WritPathChar.cd[key] or default
end
-- a town's flight point stands in for a spot not recorded yet (the inn is rarely far from it)
local function TownSpot(name)
  if not name then return nil end
  for id, n in pairs(WritPath_Data and WritPath_Data.flightNodes or {}) do
    if OurFaction(id) and n[5] and n[5]:match("^([^,]+)") == name then return T.Point(n[1], n[2], n[3]) end
  end
end
-- where the hearthstone takes you: recorded when you set it or land, else the bind town's flight point
function T.HearthSpot()
  local name = GetBindLocation and GetBindLocation()
  local h = WritPathChar and WritPathChar.hearth
  if h and h.map and (not name or h.name == name) then return T.Point(h.map, h.x, h.y), h.name end
  local p = TownSpot(name)
  if p then return p, name, true end
end
function T.SaveHearth()
  local p = T.PlayerPoint()
  local name = GetBindLocation and GetBindLocation()
  if p and not p.sea and name then
    WritPathChar = WritPathChar or {}
    WritPathChar.hearth = { name = name, map = p.map, x = math.floor(p.x * 10 + 0.5) / 10, y = math.floor(p.y * 10 + 0.5) / 10, t = time() }
  end
end
function T.Teleports()
  local list = {}
  local hs, hsName = T.HearthSpot()
  if hs and ItemCount(HEARTH) > 0 then
    local left, d = ItemLeft(HEARTH)
    list[#list + 1] = { key = "hearth", text = "Use your Hearthstone", dest = hs, destName = hsName, ready = left,
                        cd = Cooldown("hearth", d, 3600), cast = 25 }
  end
  if hs and KnowsSpell(RECALL) then
    local left, d = SpellLeft(RECALL)
    list[#list + 1] = { key = "recall", text = "Cast Astral Recall", dest = hs, destName = hsName, ready = left,
                        cd = Cooldown("recall", d, 900), cast = 25 }
  end
  local runes = ItemCount(RUNE)
  if runes > 0 then
    for spell, town in pairs(MAGE) do
      local p = KnowsSpell(spell) and TownSpot(town)
      if p then list[#list + 1] = { key = "mage" .. spell, text = "Cast Teleport: " .. town, dest = p, destName = town,
                                    ready = 0, cd = 0, cast = 25, rune = true, runes = runes } end
    end
  end
  if KnowsSpell(MOONGLADE) then
    local m, x, y = FlightSpot(UnitFactionGroup("player") == "Horde" and 69 or 49)
    local p = m and T.Point(m, x, y)
    if p then list[#list + 1] = { key = "moonglade", text = "Cast Teleport: Moonglade", dest = p, destName = "Moonglade",
                                  ready = (SpellLeft(MOONGLADE)), cd = 0, cast = 20 } end
  end
  return list
end

local HOME = ERR_DEATHBIND_SUCCESS_S and ERR_DEATHBIND_SUCCESS_S:gsub("%%s", "(.+)") or "(.+) is now your home%."
local rec = CreateFrame("Frame")
rec:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
rec:RegisterEvent("PLAYER_ENTERING_WORLD")
rec:RegisterEvent("CHAT_MSG_SYSTEM")
rec:SetScript("OnEvent", function(_, event, unit, _, spellID)
  if event == "PLAYER_ENTERING_WORLD" then return end
  if event == "CHAT_MSG_SYSTEM" then
    -- "X is now your home.": you're standing at the innkeeper
    if type(unit) == "string" and unit:match(HOME) then C_Timer.After(0.5, T.SaveHearth) end
    return
  end
  if unit ~= "player" then return end
  local name = spellID and ((C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(spellID)) or (GetSpellInfo and GetSpellInfo(spellID)))
  if name and (name:find("Hearthstone") or name:find("Teleport") or name:find("Portal") or name:find("Astral Recall")) then
    REC.teleport = GetTime()   -- what follows isn't a road or a ship
    -- landed from a hearthstone: that's where it's bound
    if name:find("Hearthstone") or name:find("Astral Recall") then C_Timer.After(8, T.SaveHearth) end
  end
end)
local acc = 0
rec:SetScript("OnUpdate", function(_, e) acc = acc + e; if acc >= 0.5 then acc = 0; Poll() end end)
T.Recorder = { Poll = Poll, State = REC }
