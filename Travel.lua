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
-- Prefer flights: riding counts RIDE_BIAS times as long when routes are compared, so a long ride only beats a
-- flight when it's clearly faster (the ride's estimate is straight lines between borders; real roads wind,
-- and a flight needs no steering). A Felwood -> Desolace route once rode two zones to save a minute on paper.
local RIDE_BIAS = 1.05   -- 1.15.2: was 1.25 before the traced roads and your own mount speed made ride times honest
-- Riding speed: the fastest mount WritPath has seen you ride (GetUnitSpeed's run speed while mounted, saved per
-- character in WritPathChar.mountBest, so planning on foot in town still uses it); otherwise RIDE. 1.16.4: it was
-- the LAST mount you rode, so a slow mount, a slow or a short speed buff changed every plan. mountSpeed is that old
-- value, used only until a best speed is known.
local DEFAULT_RIDE = RIDE
local function MountSpeed()
  local c = WritPathChar
  local v = c and (c.mountBest or c.mountSpeed)
  return (type(v) == "number" and v > 7) and v or nil
end
local builtSpeed
local function SetRide() builtSpeed = MountSpeed() or DEFAULT_RIDE; RIDE = builtSpeed / RIDE_BIAS end
SetRide()
local LEARN_FP = 20     -- seconds to talk to a new flight master before taking off
local FLY_GUESS, FLIGHT_GUESS_OVERHEAD = 20.9, 36   -- a flight with no known time: straight yards/s, s (fitted)
local UNKNOWN = 1.3    -- riding straight through zones whose roads WritPath hasn't learned: assume 30% longer
local HOSTILE = 1200   -- extra seconds for riding into the other faction's capital: only when the stop is inside
-- zones whose dock is in a faction town (classic): Southshore, Menethil, Auberdine, Rut'theran, Theramore,
-- Stormwind / Orgrimmar's and the Undercity's zeppelin towers, Grom'gol, and the capitals themselves
local ALLIANCE_DOCKS = { [1424] = true, [1437] = true, [1439] = true, [1438] = true, [1445] = true, [1453] = true,
                         [1455] = true, [1457] = true }
local HORDE_DOCKS = { [1411] = true, [1420] = true, [1412] = true, [1454] = true }
-- the other faction's capitals: riding in costs HOSTILE (guards), so routes go round them unless the stop is inside
local ALLIANCE_CITIES = { [1453] = true, [1455] = true, [1457] = true }   -- Stormwind, Ironforge, Darnassus
local HORDE_CITIES = { [1454] = true, [1456] = true, [1458] = true }      -- Orgrimmar, Thunder Bluff, Undercity
local hostileCity = {}

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
  local rxp = (r[a] and r[a][b]) or (r[b] and r[b][a])
  if rxp then return rxp end
  -- pairs RestedXP's list lacks: the length of the game's flight paths between them (Polestar's network)
  local n = RXP.networkTimes and RXP.networkTimes[UnitFactionGroup("player")] or {}
  return (n[a] and n[a][b]) or (n[b] and n[b][a])
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
  local function Ours(m) return m[4] == mine or m[4] == "AH" end   -- "D": druids only, never a place to learn a flight path
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
  local trusted, once = 0, 0
  for _, c in ipairs(L.paths or {}) do if (c.n or 1) >= 2 then trusted = trusted + 1 else once = once + 1 end end
  lines[#lines + 1] = ("Winding paths to a border: %d shipped, %d learned (ridden twice), %d ridden once."):format(
    #(D.paths or {}), trusted, once)
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
local builtLevel   -- the player level the route map was built for (dangerous roads depend on it)
local roadZone = {}       -- zones with learned roads (checkpoints): off-road riding there counts OFFROAD slower
local ROAD_RUNS, OFFROAD, ROAD_ACCESS = 3, 1.3, 5   -- runs before a step is road; off-road penalty; access every 5 spots

function T.Reset() nodes, byZone, cache, roads, roadZone = nil, nil, nil, nil, {} end
local function Ride(zone) return roadZone[zone] and OFFROAD or 1 end   -- straight riding inside a zone

-- Checkpoint hexes: the world is tiled with hexagons HEX yards across (flat side to flat side, pointy top), named
-- "continent:q:r" (axial coordinates). All 6 neighbours share an edge and are the same distance away, so a road at
-- any angle runs through them the same way every time.
local HEX = 50
local HEXR = HEX / math.sqrt(3)   -- centre to corner
local HEXDIR = { { 1, 0 }, { 1, -1 }, { 0, -1 }, { -1, 0 }, { -1, 1 }, { 0, 1 } }
local function HexOf(wx, wy)
  local q = (math.sqrt(3) / 3 * wx - wy / 3) / HEXR
  local r = (2 / 3 * wy) / HEXR
  local x, z = q, r
  local y = -x - z
  local rx, ry, rz = math.floor(x + 0.5), math.floor(y + 0.5), math.floor(z + 0.5)
  local dx, dy, dz = math.abs(rx - x), math.abs(ry - y), math.abs(rz - z)
  if dx > dy and dx > dz then rx = -ry - rz elseif dy > dz then ry = -rx - rz else rz = -rx - ry end
  return rx, rz
end
local function HexKey(p) local q, r = HexOf(p.wx, p.wy); return p.inst .. ":" .. q .. ":" .. r end
local function HexNeighbours(key)
  local inst, q, r = key:match("^(.-):(%-?%d+):(%-?%d+)$")
  if not inst then return {} end
  q, r = tonumber(q), tonumber(r)
  local out = {}
  for _, d in ipairs(HEXDIR) do out[#out + 1] = inst .. ":" .. (q + d[1]) .. ":" .. (r + d[2]) end
  return out
end
T.HexKey, T.HexNeighbours = HexKey, HexNeighbours

-- Dangerous stretches, for your level. Each hex remembers the hostile mobs seen from it on writ routes (l/h: lowest
-- and highest level, s: a "??" mob, e: an elite) and the levels of players who died there (dl/dh). A hex is
-- dangerous for you when it has mobs DANGER_LEVELS or more above you (or a skull, or an elite at your level or
-- above), or when someone of about your level or higher died there.
local DANGER_LEVELS = 3
local function PlayerLevel() return WritPath_Open(UnitLevel, "player") or 60 end
local function Dangerous(cell, lvl)
  if not cell then return false end
  if cell.s then return true end
  if cell.h and (cell.h >= lvl + DANGER_LEVELS or (cell.e and cell.h >= lvl)) then return true end
  if (cell.d or 0) > 0 and cell.dh and cell.dh >= lvl - 2 then return true end
  return false
end
T.Dangerous = Dangerous
-- the danger along a straight ride from a to b (same continent): a warning line for the guide, or nil
local function DangerAlong(a, b)
  local R = WritPathLearned and WritPathLearned.roads
  if not (a and b and a.wx and b.wx and R and R.v == 2 and R.cells and a.inst == b.inst) then return nil end
  local lvl = PlayerLevel()
  local len = math.sqrt((b.wx - a.wx) ^ 2 + (b.wy - a.wy) ^ 2)
  local n = math.max(1, math.floor(len / 25))
  local seen, hi, elite, skull, deaths, count = {}, nil, false, false, 0, 0
  for i = 0, n do
    local t = i / n
    local k = HexKey({ inst = a.inst, wx = a.wx + (b.wx - a.wx) * t, wy = a.wy + (b.wy - a.wy) * t })
    if not seen[k] then
      seen[k] = true
      local c = R.cells[k]
      if Dangerous(c, lvl) then
        count = count + 1
        if c.h and c.h >= lvl then hi = math.max(hi or 0, c.h) end
        elite = elite or (c.e and true) or false
        skull = skull or (c.s and true) or false
        if (c.d or 0) > 0 and c.dh and c.dh >= lvl - 2 then deaths = deaths + c.d end
      end
    end
  end
  if count == 0 then return nil end
  local what = {}
  if skull then what[#what + 1] = "mobs far above your level"
  elseif hi then what[#what + 1] = ("mobs up to level %d"):format(hi) end
  if elite then what[#what + 1] = "elites" end
  if deaths > 0 then what[#what + 1] = ("%d %s near your level"):format(deaths, deaths == 1 and "death" or "deaths") end
  if #what == 0 then what[1] = "trouble" end
  return ("|cFFFF5555Careful:|r %s on the way (you're %d)"):format(table.concat(what, ", "), lvl)
end
T.DangerAlong = DangerAlong

-- riding straight from one zone into another is only allowed when WritPath knows no roads for one of them:
-- between two zones with known roads the way goes over a road, a boat or a flight (a straight line across a
-- border runs into the mountains between Feralas and Un'Goro, Duskwood and Stranglethorn, ...)
local function ZoneName(m) local i = MapInfo(m); return i and i.name or "?" end
-- looked up for every place on the travel map, for every leg the planner times: a table built once (1.17.0), not
-- a walk through the list each time
local noRoadSet
local function NoRoad(a, b)
  if not noRoadSet then
    noRoadSet = {}
    for _, r in ipairs(WritPath_Data and WritPath_Data.noRoad or {}) do
      noRoadSet[r[1] .. ":" .. r[2]], noRoadSet[r[2] .. ":" .. r[1]] = true, true
    end
  end
  return noRoadSet[a .. ":" .. b] or false
end
T.NoRoad = NoRoad

-- Learned records that look wrong stay out of routes, old ones included (before loops were cut while recording):
-- a path that doubles back, loops or takes 2.5 times the straight way, and a boat or zeppelin trip on a route that
-- isn't a known one, taken only once (a summon or portal recorded as a ship).
local function PathShapeOK(c)
  local pts = {}
  for _, v in ipairs(c.via or {}) do pts[#pts + 1] = v end
  pts[#pts + 1] = { c.x, c.y }
  local function d(a, b) return math.sqrt((a[1] - b[1]) ^ 2 + (a[2] - b[2]) ^ 2) end
  for k = 2, #pts - 1 do
    local ax, ay = pts[k][1] - pts[k - 1][1], pts[k][2] - pts[k - 1][2]
    local bx, by = pts[k + 1][1] - pts[k][1], pts[k + 1][2] - pts[k][2]
    local la, lb = math.sqrt(ax * ax + ay * ay), math.sqrt(bx * bx + by * by)
    if la > 0 and lb > 0 and (ax * bx + ay * by) / (la * lb) < -0.866 then return false end
  end
  for i = 1, #pts do for j = i + 2, #pts do if d(pts[i], pts[j]) < 2 then return false end end end
  local len = 0
  for k = 2, #pts do len = len + d(pts[k - 1], pts[k]) end
  return not (len > 2.5 * d(pts[1], pts[#pts]))
end
T.PathShapeOK = PathShapeOK
local KNOWN_SHIPS = { ["1411>1434"] = true, ["1434>1411"] = true, ["1411>1420"] = true, ["1420>1411"] = true,
  ["1420>1434"] = true, ["1434>1420"] = true, ["1434>1413"] = true, ["1413>1434"] = true,
  ["2548>1446"] = true, ["1446>2548"] = true, ["2548>1414"] = true, ["1446>1415"] = true,
  ["1414>1446"] = true, ["1415>2548"] = true }
-- trips once recorded as a boat or zeppelin that were a summon or portal: there's no such ship, whoever recorded it
-- (Orgrimmar - Badlands, Thunder Bluff - Undercity)
local NOT_SHIPS = { ["1454>1418"] = true, ["1418>1454"] = true, ["1456>1458"] = true, ["1458>1456"] = true }
-- every boat, zeppelin and airship Polestar knows (TravelFacts.transports): a known route, and how long it takes
local SHIP_SECS = {}   -- ["from>to"] = seconds riding plus the average wait at the dock
for _, t in ipairs((WritPath_TravelFacts or {}).transports or {}) do
  local k = t[1] .. ">" .. t[4]
  KNOWN_SHIPS[k] = true
  if not SHIP_SECS[k] or t[7] + t[8] < SHIP_SECS[k] then SHIP_SECS[k] = t[7] + t[8] end
end
T.ShipSecs = function(from, to) return SHIP_SECS[tostring(from) .. ">" .. tostring(to)] end
local function ShipOK(t) return not NOT_SHIPS[t.from .. ">" .. t.to] and (t.src or (t.n or 1) >= 2 or KNOWN_SHIPS[t.from .. ">" .. t.to]) or false end
T.ShipOK = ShipOK
function T.NotShip(from, to) return NOT_SHIPS[tostring(from) .. ">" .. tostring(to)] or false end

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
local function Edge(a, b, cost, kind, legs, pts)
  if kind == "cross" and hostileCity[b.zone] and not hostileCity[a.zone] then cost = cost + HOSTILE end   -- into their capital
  a.edges[#a.edges + 1] = { to = b, cost = cost, kind = kind, legs = legs, pts = pts }
end

function T.Build()
  builtLevel = PlayerLevel()
  SetRide()
  hostileCity = UnitFactionGroup("player") == "Horde" and ALLIANCE_CITIES or HORDE_CITIES
  nodes, byZone, cache, roads = {}, {}, {}, {}
  local L = WritPathLearned or {}
  -- winding paths (shipped, and learned ones ridden twice) replace a plain crossing at the same spot: riding
  -- straight there is what the path goes around
  local paths, ends = {}, {}
  for _, c in ipairs(WritPath_Data and WritPath_Data.paths or {}) do paths[#paths + 1] = c end
  for _, c in ipairs(L.paths or {}) do if (c.n or 1) >= 2 and not c.suspect and PathShapeOK(c) then paths[#paths + 1] = c end end
  for _, c in ipairs(paths) do local q = T.Point(c.from, c.x, c.y); if q then ends[#ends + 1] = { c.from, c.to, q } end end
  local function Replaced(from, to, p)
    for _, e in ipairs(ends) do
      if ((e[1] == from and e[2] == to) or (e[1] == to and e[2] == from)) and p and e[3].inst == p.inst and Dist(e[3], p) < 150 then return true end
    end
    return false
  end
  -- road crossings you've ridden: an exit on this side, an entry at the same spot on the far side, both ways
  for _, c in ipairs(L.crossings or {}) do
    -- an old record taken out at sea (map = a whole continent) isn't a road; an imported one where Forever has
    -- no road isn't either (one you rode yourself has no src, and stays)
    local p = not (IsContinent(c.from) or IsContinent(c.to)) and not (c.src and NoRoad(c.from, c.to)) and T.Point(c.from, c.x, c.y)
    if p and not Replaced(c.from, c.to, p) then
      local exit = Add({ zone = c.from, p = p, kind = "exit", peer = c.to })
      local entry = Add({ zone = c.to, p = p, kind = "entry", peer = c.from })
      Edge(exit, entry, CROSS, "cross"); Edge(entry, exit, CROSS, "cross")
    end
  end
  -- crossings WritPath players have ridden (WritPathData.lua), both ways
  for _, c in ipairs(WritPath_Data and WritPath_Data.crossings or {}) do
    local p = not (IsContinent(c.from) or IsContinent(c.to)) and not NoRoad(c.from, c.to) and T.Point(c.from, c.x, c.y)
    if p and not Replaced(c.from, c.to, p) then
      local exit = Add({ zone = c.from, p = p, kind = "exit", peer = c.to })
      local entry = Add({ zone = c.to, p = p, kind = "entry", peer = c.from })
      Edge(exit, entry, CROSS, "cross"); Edge(entry, exit, CROSS, "cross")
    end
  end
  -- mountain paths (WritPathData.lua): the first waypoint to the crossing, both ways, with a guide step for
  -- every waypoint so the arrow follows the path
  -- the paths themselves (learned ones once two rides agree, so one detour doesn't count)
  for _, c in ipairs(paths) do
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
      -- the path's waypoints are one step, "Follow the path"; the arrow points to each in turn (1.15.2)
      local function Way(list, zone)
        if #list == 0 then return nil end
        return { at = list[#list], way = list, into = zone, text = "{goto} Follow the path" }
      end
      -- there: the waypoints, then over the border
      local there = {}
      local fwd = {}; for i = 2, #pts do fwd[#fwd + 1] = pts[i] end
      there[#there + 1] = Way(fwd, c.from)
      there[#there + 1] = { at = cross, into = c.to, cross = true, text = "{goto} Ride into |cFF00FF25" .. into .. "|r" }
      local a = Add({ zone = c.from, p = all[1], kind = "exit", peer = c.to, path = true })
      local b = Add({ zone = c.to, p = cross, kind = "entry", peer = c.from, path = true })
      Edge(a, b, cost, "cross", there)
      -- back: over the border, then the waypoints the other way round
      local backLegs = { { at = cross, into = c.from, cross = true, text = "{goto} Ride into |cFF00FF25" .. back .. "|r" } }
      local rev = {}; for i = #pts, 1, -1 do rev[#rev + 1] = pts[i] end
      backLegs[#backLegs + 1] = Way(rev, c.from)
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
    if p and not Replaced(c[1], c[2], p) then
      local exit = Add({ zone = c[1], p = p, kind = "exit", peer = c[2] })
      local entry = Add({ zone = c[2], p = p, kind = "entry", peer = c[1] })
      Edge(exit, entry, CROSS, "cross"); Edge(entry, exit, CROSS, "cross")
    end
  end
  -- ships you've taken, one way each (the way back is its own record). The other faction's boats and zeppelins
  -- are left out: their guards kill you on the tower or the dock (Alliance players were sent to the Undercity
  -- zeppelin, 2026-11-18). Everyone keeps the neutral boats (Ratchet - Booty Bay, Riverglades).
  local hostile = UnitFactionGroup("player") == "Horde" and ALLIANCE_DOCKS or HORDE_DOCKS
  local sailed = {}   -- from..to pairs you've taken yourself: those win over the shipped routes
  local mine = UnitFactionGroup("player") == "Horde" and "H" or "A"
  local function Sail(from, dock, to, land, faction)
    if NOT_SHIPS[from .. ">" .. to] then return end
    if faction then
      if faction ~= "AH" and faction ~= mine then return end
    elseif hostile[from] or hostile[to] then return end
    -- the ride and the average wait for it (Polestar's timetables), else a flat guess
    Edge(Add({ zone = from, p = dock, kind = "dock" }), Add({ zone = to, p = land, kind = "land" }),
      SHIP_SECS[from .. ">" .. to] or SAIL, "sail")
  end
  -- a place recorded on a continent map (out at sea) -> the zone it's in
  local function OnZone(m, x, y)
    if not IsContinent(m) then return m, x, y end
    local z, zx, zy = Place(m, x / 100, y / 100)
    return z, zx, zy
  end
  for _, t in ipairs(L.transports or {}) do
    if ShipOK(t) then
      local from, x, y = OnZone(t.from, t.x, t.y)
      local to, tx, ty = OnZone(t.to, t.tx, t.ty)
      local dock, land = from and T.Point(from, x, y), to and T.Point(to, tx, ty)
      if dock and land then Sail(from, dock, to, land); sailed[from .. ">" .. to] = true end
    end
  end
  -- every boat, zeppelin and airship from Polestar's data: where each docks, for your faction or both
  for _, t in ipairs(RXP.transports or {}) do
    local k = t[1] .. ">" .. t[4]
    if not sailed[k] then
      local dock, land = T.Point(t[1], t[2], t[3]), T.Point(t[4], t[5], t[6])
      if dock and land then Sail(t[1], dock, t[4], land, t[9]); sailed[k] = true end
    end
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
        -- the guess: flights follow the flight paths, not a straight line; fitted to the recorded times, a flight
        -- takes about 36 s plus a second per 21 yards of straight distance (FLY's 28 is the gryphon's speed)
        local secs = FlightTime(a.fpid, b.fpid)
        Edge(a, b, (secs and (secs + 15) or (FLIGHT_GUESS_OVERHEAD + Dist(a.p, b.p) / FLY_GUESS)) + (a.unlearned and LEARN_FP or 0), "fly")
      end
    end
  end
  -- which zones have known roads (a crossing on either side)
  for _, n in ipairs(nodes) do if n.kind == "exit" or n.kind == "entry" then roads[n.zone] = true end end
  -- learned roads: checkpoint steps ridden in ROAD_RUNS or more runs. A stretch of road with no junction is one
  -- link that remembers its shape (with an access point every ROAD_ACCESS spots); its cost is the time it really
  -- took, plus extra where players died or swam.
  local R = L.roads
  local roadNodes = {}
  if R and R.v == 2 and R.edges and R.cells then   -- v2: hexes (an old square-grid store is ignored)
    local pt = {}
    local function P(k)
      if pt[k] == nil then local c = R.cells[k]; pt[k] = c and T.Point(c.m, c.x, c.y) or false end
      return pt[k]
    end
    -- a hex is road when it was ridden and ROAD_RUNS different runs went through it or right next to it: a road
    -- along the edge between two rows of hexes still adds up, and no run is counted twice
    local isRoad, near = {}, R.near or {}
    for key, c in pairs(R.cells) do
      if (c.v or 0) >= 1 and (near[key] or 0) >= ROAD_RUNS then isRoad[key] = true end
    end
    -- linked where a run actually moved between them (never through a wall); one way only when it's clear (3+ runs
    -- one way, none back: a drop you can't climb)
    local step, nbr = {}, {}       -- step[a][b] = cost; nbr[a] = set of spots linked either way
    local function E(a, b) local v = R.edges[a .. ">" .. b]; return v and (type(v) == "number" and { n = v } or v) end
    local seen = {}
    for key in pairs(R.edges) do
      local a, b = key:match("^(.-)>(.+)$")
      local pair = a and b and ((a < b) and (a .. "|" .. b) or (b .. "|" .. a))
      if pair and not seen[pair] and isRoad[a] and isRoad[b] then
        seen[pair] = true
        local pa, pb = P(a), P(b)
        if pa and pb and pa.inst == pb.inst then
          local ab, ba = E(a, b), E(b, a)
          local nab, nba = ab and ab.n or 0, ba and ba.n or 0
          local r, k = (ab and ab.r or 0) + (ba and ba.r or 0), (ab and ab.k or 0) + (ba and ba.k or 0)
          local base = Dist(pa, pb) / RIDE * (k > 0 and r / k or 1)
          local function Cost(to)
            local c, cell = base, R.cells[to]
            if (cell.d or 0) > 0 then c = c + 20 * math.min(cell.d, 3) end   -- deaths here: mobs worth avoiding
            if (cell.w or 0) > 0 then c = c * 1.3 end                        -- swimming
            if Dangerous(cell, builtLevel) then c = c + 60 end               -- too dangerous for your level
            return c
          end
          local oneWay = (nab >= 3 and nba == 0) and "ab" or ((nba >= 3 and nab == 0) and "ba" or nil)
          if oneWay ~= "ba" then step[a] = step[a] or {}; step[a][b] = Cost(b) end
          if oneWay ~= "ab" then step[b] = step[b] or {}; step[b][a] = Cost(a) end
          nbr[a] = nbr[a] or {}; nbr[a][b] = true
          nbr[b] = nbr[b] or {}; nbr[b][a] = true
          roadZone[R.cells[a].m], roadZone[R.cells[b].m] = true, true
        end
      end
    end
    local function Count(t) local n = 0; for _ in pairs(t or {}) do n = n + 1 end; return n end
    local function Interior(k) return Count(nbr[k]) == 2 end
    local function NodeOf(k)
      if not roadNodes[k] then roadNodes[k] = Add({ zone = R.cells[k].m, p = P(k), kind = "road" }) end
      return roadNodes[k]
    end
    -- walk every stretch from a junction or end (or an access point) to the next one
    local walked = {}
    local function Walk(a)
      if walked[a] then return end
      walked[a] = true
      for b, cost in pairs(step[a] or {}) do
        local pts, total, prev, cur, len = { P(a), P(b) }, cost, a, b, 1
        while Interior(cur) and len % ROAD_ACCESS ~= 0 do
          local nxt
          for c in pairs(step[cur] or {}) do if c ~= prev then nxt = c end end
          if not nxt then break end   -- a one-way end: this spot becomes a place of its own
          total = total + step[cur][nxt]; pts[#pts + 1] = P(nxt)
          prev, cur, len = cur, nxt, len + 1
        end
        Edge(NodeOf(a), NodeOf(cur), total, "road", nil, pts)
        if Interior(cur) and len % ROAD_ACCESS == 0 then Walk(cur) end
      end
    end
    for k in pairs(step) do if not Interior(k) then Walk(k) end end
  end
  -- roads traced from the zone maps (WritPathRoads.lua): every player starts with them, so routes follow the drawn
  -- roads instead of a straight line through the mountains. Each point is a road spot; lines that meet at the same
  -- point share it (a junction). Trails count a little slower. Learned roads (above) are timed by real rides, so a
  -- shortcut players use wins wherever it's faster.
  local TRAIL = 1.15
  for m, z in pairs(WritPath_MapRoads or {}) do
    local spot = {}
    local function Spot(x, y)
      local k = ("%.1f:%.1f"):format(x, y)
      if spot[k] == nil then
        local p = T.Point(m, x, y)
        spot[k] = p and Add({ zone = m, p = p, kind = "road" }) or false
      end
      return spot[k]
    end
    local any = false
    for _, kind in ipairs({ "roads", "trails" }) do
      local f = kind == "trails" and TRAIL or 1
      for _, line in ipairs(z[kind] or {}) do
        local prev
        for i = 1, #line - 1, 2 do
          local n = Spot(line[i], line[i + 1])
          if n and prev and n ~= prev and n.p.inst == prev.p.inst then
            local c = Dist(prev.p, n.p) / RIDE * f
            Edge(prev, n, c, "road", nil, { prev.p, n.p }); Edge(n, prev, c, "road", nil, { n.p, prev.p })
            any = true
          end
          if n then prev = n end
        end
      end
    end
    if any then roadZone[m] = true end
  end
  -- riding between any two places in the same zone (learned road spots join only their nearby places)
  for _, list in pairs(byZone) do
    for _, a in ipairs(list) do
      for _, b in ipairs(list) do
        if a ~= b and a.p.inst == b.p.inst then
          if a.kind ~= "road" and b.kind ~= "road" then Edge(a, b, Dist(a.p, b.p) / RIDE * Ride(a.zone), "ride")
          elseif a.kind ~= b.kind then
            local d = Dist(a.p, b.p)
            if d < 400 then Edge(a, b, d / RIDE * OFFROAD, "ride") end   -- onto or off a road
          end
        end
      end
    end
  end
end

-- shortest times from a place to every node (cached per place)
local function From(src)
  local key = src.map .. ":" .. src.x .. ":" .. src.y .. (loose and ":loose" or "")
  if cache[key] then return cache[key] end
  local dist, prev, done = {}, {}, {}
  -- a binary heap of { time, node }: the road network can have many places
  local heap = {}
  local function Push(d, i)
    heap[#heap + 1] = { d, i }
    local c = #heap
    while c > 1 do
      local up = math.floor(c / 2)
      if heap[up][1] <= heap[c][1] then break end
      heap[up], heap[c] = heap[c], heap[up]; c = up
    end
  end
  local function Pop()
    local top = heap[1]; if not top then return nil end
    local last = table.remove(heap)
    if #heap > 0 then
      heap[1] = last
      local c = 1
      while true do
        local l, r, m = c * 2, c * 2 + 1, c
        if heap[l] and heap[l][1] < heap[m][1] then m = l end
        if heap[r] and heap[r][1] < heap[m][1] then m = r end
        if m == c then break end
        heap[m], heap[c] = heap[c], heap[m]; c = m
      end
    end
    return top
  end
  -- start: ride to any known place on this continent; straight across a zone you haven't learned roads for
  -- costs a bit more, because the straight line may run into hills
  local open = {}
  for _, n in ipairs(nodes) do
    if n.p.inst == src.inst then
      local o = open[n.zone]
      if o == nil then o = Open(src.map, n.zone); open[n.zone] = o end
      if o then
        dist[n.i] = Dist(src, n.p) / RIDE * (n.zone == src.map and Ride(src.map) or UNKNOWN)
        Push(dist[n.i], n.i)
      end
    end
  end
  while true do
    local top = Pop()
    if not top then break end
    local u, best = top[2], top[1]
    if not done[u] and best <= (dist[u] or math.huge) then
      done[u] = true
      -- landed from a flight: never take off again straight away. The game flies you from the first flight
      -- point to the last in one go, so a second takeoff only adds a stop (and a guessed flight time could
      -- otherwise make the stop look quicker: Nethergarde -> Farholde Keep -> Thelsamar)
      local landed = prev[u] and prev[u][2].kind == "fly"
      for _, e in ipairs(nodes[u].edges) do
        if not (landed and e.kind == "fly") then
          local nd = best + e.cost
          if not dist[e.to.i] or nd < dist[e.to.i] then dist[e.to.i], prev[e.to.i] = nd, { u, e }; Push(nd, e.to.i) end
        end
      end
    end
  end
  cache[key] = { dist = dist, prev = prev }
  return cache[key]
end

T.Build = WritPath_Timed("travel map rebuild", T.Build)

---------------------------------------------------------------- walking yards from Shortest Path Forever (1.16.2)
-- With Shortest Path Forever installed, a ride between two writ customers is timed by the real way on the ground
-- (around cliffs, water and buildings) instead of a straight line. Its searches run in the background (Planner.lua
-- asks for them, one customer at a time) and the answers are kept in WritPathWalks: rows[from][to] = yards, or false
-- when there is no way on foot. They're dropped when Shortest Path Forever's walking data changes (its NavVersion).
local function WalkKey(p) return ("%d:%.1f:%.1f"):format(p.map, p.x, p.y) end
T.WalkKey = WalkKey
-- and from where you stood when the plan was made (Planner.lua asks just before planning): { p, rows = { [key] =
-- yards or false } }. Your own spot is never a saved one, so this is how the first leg of a plan gets the ground way.
local here
local HERE_NEAR = 30   -- yards: still standing where those were worked out from
function T.SetHere(p, rows) here = p and { p = p, rows = rows } or nil end
function T.WalkYards(a, b)
  if here then
    local hp = here.p
    if a.inst == hp.inst and Dist(a, hp) <= HERE_NEAR and here.rows[WalkKey(b)] ~= nil then return here.rows[WalkKey(b)] end
    if b.inst == hp.inst and Dist(b, hp) <= HERE_NEAR and here.rows[WalkKey(a)] ~= nil then return here.rows[WalkKey(a)] end
  end
  local rows = WritPathWalks and WritPathWalks.rows
  if not rows then return nil end
  local ka, kb = WalkKey(a), WalkKey(b)
  local v = rows[ka] and rows[ka][kb]
  if v == nil then v = rows[kb] and rows[kb][ka] end   -- either way round: a walk is the same both ways
  return v
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
  if nodes and builtLevel ~= PlayerLevel() then T.Reset() end   -- a new level: danger is judged afresh
  if nodes and math.abs((MountSpeed() or DEFAULT_RIDE) - builtSpeed) > 0.3 then T.Reset() end   -- a faster (or slower) mount
  if not nodes then T.Build() end
  -- straight there, or over the known roads, ships and flights and then straight to the stop
  local best
  local walk = a.inst == b.inst and T.WalkYards(a, b)
  if walk then best = walk / RIDE            -- the real way on the ground (Shortest Path Forever)
  elseif walk == false then best = nil       -- no way on foot: only roads, flights and ships
  else best = (a.inst == b.inst and Direct(a.map, b.map)) and Dist(a, b) / RIDE * (a.map == b.map and Ride(a.map) or UNKNOWN) or nil end
  local via
  local r = From(a)
  -- the ground way is known (Shortest Path Forever): a route that stays on the ground (roads, crossings, rides) can't
  -- beat it, and its straight rides onto and off the roads may run through a cliff (1.16.2: Juo, in the Hinterlands,
  -- was sent straight over a 500-yard mountain to reach the road). Only a flight or a ship can do better.
  -- (worked out once per starting place and kept with its shortest times: r.carried[node])
  local function Carried(i)
    local c = r.carried
    if not c then c = {}; r.carried = c end
    local v = c[i]
    if v == nil then
      local p = r.prev[i]
      if not p then v = false
      else local k = p[2].kind; v = (k == "fly" or k == "sail") or Carried(p[1]) end
      c[i] = v
    end
    return v
  end
  -- the places you can ride straight to b from: only its own zone's when its roads are known (1.17.0: every place on
  -- the map was checked, for every leg)
  local list = (not loose and roads and roads[b.map]) and (byZone[b.map] or {}) or nodes
  local open = {}
  for _, n in ipairs(list) do
    local d = r.dist[n.i]
    if d and walk and not Carried(n.i) then d = nil end
    if d and n.p.inst == b.inst then
      local o = open[n.zone]
      if o == nil then o = Open(b.map, n.zone); open[n.zone] = o end
      if o then
        d = d + Dist(n.p, b) / RIDE * (n.zone == b.map and Ride(b.map) or UNKNOWN)
        if not best or d < best then best, via = d, n end
      end
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
  [2548] = { [1446] = { "boat", "the Powderfuse Port dock", "Steamwheedle Port, Tanaris" } },
  [1446] = { [2548] = { "boat", "the Steamwheedle Port dock", "Powderfuse Port, Riverglades" } },
}
-- the rest from Polestar's names: "the Menethil Harbor boat" to "Theramore"
for _, t in ipairs((WritPath_TravelFacts or {}).transports or {}) do
  SHIP_NAMES[t[1]] = SHIP_NAMES[t[1]] or {}
  if not SHIP_NAMES[t[1]][t[4]] and t[11] then
    SHIP_NAMES[t[1]][t[4]] = { t[10], ("the %s %s"):format(t[11], t[10] == "boat" and "dock" or "tower"), t[12] }
  end
end
local function ShipText(from, to)
  local n = SHIP_NAMES[from] and SHIP_NAMES[from][to]
  if not n then return "{boat} Take the boat or zeppelin to |cFF00FF25" .. ZoneName(to) .. "|r" end
  return ("{%s} Go to %s and take the %s to |cFF00FF25%s|r"):format(n[1] == "boat" and "boat" or "zeppelin", n[2], n[1], n[3])
end
T.ShipText = ShipText

-- along a learned road: only the points where it really turns (over 30 degrees), or every 600 yards on a long
-- straight, and the end
local function Bends(pts)
  local out, since = {}, 0
  for k = 2, #pts - 1 do
    local ax, ay = pts[k].wx - pts[k - 1].wx, pts[k].wy - pts[k - 1].wy
    local bx, by = pts[k + 1].wx - pts[k].wx, pts[k + 1].wy - pts[k].wy
    local la, lb = math.sqrt(ax * ax + ay * ay), math.sqrt(bx * bx + by * by)
    since = since + la
    if (la > 0 and lb > 0 and (ax * bx + ay * by) / (la * lb) < 0.866) or since >= 600 then out[#out + 1] = pts[k]; since = 0 end
  end
  out[#out + 1] = pts[#pts]
  return out
end
T.RoadBends = Bends

-- the waypoints on the way from a to b: { kind, at = point, into = zone, text }
function T.Legs(a, b)
  local _, via, r = T.Time(a, b)
  local legs = {}
  if not via then
    if a and b and a.inst ~= b.inst then legs[1] = { kind = "unknown", into = b.map } end
    legs.finalWarn = DangerAlong(a, b)   -- riding straight there
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
  -- a road is one step, "Follow the road": its start and bends are waypoints (way) the arrow points to in turn,
  -- not steps of their own (1.15.2; they were listed one by one with their coordinates)
  local roadPts, roadZoneOf
  local function FlushRoad()
    if not roadPts then return end
    local way = { roadPts[1] }
    for _, q in ipairs(Bends(roadPts)) do way[#way + 1] = q end
    local prev = legs[#legs]
    if prev and prev.road and prev.at.inst == way[1].inst then
      -- a road straight after another (a short ride between them): one "Follow the road", its waypoints run on
      for _, q in ipairs(way) do prev.way[#prev.way + 1] = q end
      prev.at = way[#way]
    else
      legs[#legs + 1] = { kind = "cross", road = true, at = way[#way], way = way, into = roadZoneOf, text = "{goto} Follow the road" }
    end
    roadPts = nil
  end
  for _, c in ipairs(chain) do
    local k = c.e.kind
    if k ~= "road" then FlushRoad() end
    if k == "road" and c.e.pts then      -- a learned road: gathered piece by piece, then its bends (below)
      if not roadPts then
        roadPts, roadZoneOf = {}, c.from.zone
        roadPts[1] = c.e.pts[1]   -- where you join the road: the step's first waypoint
      end
      for i = 2, #c.e.pts do roadPts[#roadPts + 1] = c.e.pts[i] end
    elseif k == "cross" and c.e.legs then   -- a mountain path: start of the path, its waypoints, the border
      for j, l in ipairs(c.e.legs) do
        local way = l.way
        -- the start of the path is the first waypoint of "Follow the path" (not a step of its own)
        if j == 1 and way then way = { c.from.p }; for _, q in ipairs(l.way) do way[#way + 1] = q end end
        legs[#legs + 1] = { kind = "cross", at = l.at, way = way, into = l.into, text = l.text }
      end
      if not c.e.legs[1].cross and not c.e.legs[1].way then
        table.insert(legs, #legs - #c.e.legs + 1, { kind = "cross", at = c.from.p, into = c.from.zone, text = "{goto} Go to the start of the path" })
      end
    elseif k == "cross" then
      legs[#legs + 1] = { kind = "cross", at = c.from.p, into = c.to.zone,
                          text = "{goto} Ride into |cFF00FF25" .. ZoneName(c.to.zone) .. "|r" }
    elseif k == "sail" then
      legs[#legs + 1] = { kind = "sail", at = c.from.p, into = c.to.zone, land = c.to.p,
                          text = ShipText(c.from.zone, c.to.zone) }
    elseif k == "fly" then
      local secs = FlightTime(c.from.fpid, c.to.fpid)
      local town = function(n) return (n or ""):match("^([^,]+)") or n end
      local mins = secs and (" (" .. math.floor(secs / 60 + 0.5) .. " min)") or ""
      if c.from.unlearned then   -- a flight path you don't have yet: learn it, then take off
        legs[#legs + 1] = { kind = "fly", at = c.from.p, into = c.to.zone, fp = c.from.name, fpid = c.from.fpid, toFp = c.to.fpid, toName = c.to.name, learn = true, land = c.to.p,
                            text = "{fp} Learn the flight path at |cFF00FF25" .. (town(c.from.name) or "the flight master") .. "|r, then fly to |cFF00FF25"
                                   .. (town(c.to.name) or ZoneName(c.to.zone)) .. "|r" .. mins }
      else
        legs[#legs + 1] = { kind = "fly", at = c.from.p, into = c.to.zone, fp = c.from.name, fpid = c.from.fpid, toFp = c.to.fpid, toName = c.to.name, land = c.to.p,
                            text = "{fly} Fly from |cFF00FF25" .. (c.from.name or "here") .. "|r to |cFF00FF25" .. (c.to.name or ZoneName(c.to.zone)) .. "|r" .. mins }
      end
    end
  end
  FlushRoad()
  -- two crossings at the same spot (a border straight back out) say nothing useful twice
  for j = #legs, 2, -1 do
    if legs[j].kind == "cross" and legs[j - 1].kind == "cross" and Dist(legs[j].at, legs[j - 1].at) < 30 then table.remove(legs, j - 1) end
  end
  -- the stretch you ride to reach each step (after a flight or a boat, from where you land), and the last one to b
  local from = a
  for _, l in ipairs(legs) do
    if l.way then   -- along the waypoints: the first dangerous stretch
      local p = from
      for _, q in ipairs(l.way) do l.warn = l.warn or DangerAlong(p, q); p = q end
    elseif l.at then l.warn = DangerAlong(from, l.at) end
    from = (l.kind == "fly" or l.kind == "sail") and l.land or l.at
  end
  legs.finalWarn = DangerAlong(from, b)
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

-- Winding paths: while you ride, a breadcrumb every TRAIL_STEP yards (the last TRAIL_SECS seconds; in memory only,
-- just the few turns of a path are saved). At a border,
-- a trail much longer than the straight line from where it began means something was in the way: its turns are
-- saved as a path to that crossing. A path is used once two rides agree.
local TRAIL_STEP, TRAIL_SECS, PATH_MIN, PATH_WIND, PATH_TOL, PATH_AGREE = 100, 300, 250, 1.3, 60, 120
local function SegDist(p, a, b)
  local dx, dy = b.wx - a.wx, b.wy - a.wy
  local l2 = dx * dx + dy * dy
  local t = l2 > 0 and math.max(0, math.min(1, ((p.wx - a.wx) * dx + (p.wy - a.wy) * dy) / l2)) or 0
  local x, y = a.wx + t * dx, a.wy + t * dy
  return math.sqrt((p.wx - x) ^ 2 + (p.wy - y) ^ 2)
end
-- the few points where the trail turns (Douglas-Peucker), both ends kept
local function Simplify(pts, tol)
  local keep = { [1] = true, [#pts] = true }
  local function Rec(i, j)
    local far, at = 0, nil
    for k = i + 1, j - 1 do local d = SegDist(pts[k], pts[i], pts[j]); if d > far then far, at = d, k end end
    if at and far > tol then keep[at] = true; Rec(i, at); Rec(at, j) end
  end
  Rec(1, #pts)
  local out = {}
  for k = 1, #pts do if keep[k] then out[#out + 1] = pts[k] end end
  return out
end
local function Polyline(map, via, x, y)
  local out = {}
  for _, v in ipairs(via) do local q = T.Point(map, v[1], v[2]); if q then out[#out + 1] = q end end
  local c = T.Point(map, x, y); if c then out[#out + 1] = c end
  return out
end
-- every turn of one path lies near the other path (where they overlap: trails start wherever a ride began)
local function Agree(a, b)
  local A, B = Polyline(a.from, a.via, a.x, a.y), Polyline(b.from, b.via, b.x, b.y)
  if #A < 2 or #B < 2 then return false end
  local function Near(P, Q)   -- the points of P after where Q starts
    local d0 = Dist(Q[1], Q[#Q])
    for _, p in ipairs(P) do
      if Dist(p, Q[#Q]) <= d0 + 30 then   -- only where Q covers the way (it began d0 from the border)
        local best = math.huge
        for k = 2, #Q do best = math.min(best, SegDist(p, Q[k - 1], Q[k])) end
        if best > PATH_AGREE then return false end
      end
    end
    return true
  end
  return Near(A, B) and Near(B, A)
end
-- A wrong turn, a backtrack or running from mobs and coming back: the trail returns near a spot it already passed.
-- Everything between the two visits is cut out, so only the way you actually needed stays.
local LOOP_YDS = 70
local function CutLoops(pts)
  local out, i = {}, 1
  while i <= #pts do
    out[#out + 1] = pts[i]
    local back
    for j = #pts, i + 2, -1 do if Dist(pts[i], pts[j]) < LOOP_YDS then back = j; break end end
    i = back or (i + 1)
  end
  return out
end
-- what's still odd after that: a turn that doubles back (over 150 degrees), or far more ground than the way needs
local function Suspect(pts)
  for k = 2, #pts - 1 do
    local ax, ay = pts[k].wx - pts[k - 1].wx, pts[k].wy - pts[k - 1].wy
    local bx, by = pts[k + 1].wx - pts[k].wx, pts[k + 1].wy - pts[k].wy
    local la, lb = math.sqrt(ax * ax + ay * ay), math.sqrt(bx * bx + by * by)
    if la > 0 and lb > 0 and (ax * bx + ay * by) / (la * lb) < -0.866 then return "doubles back" end
  end
  local len = 0
  for k = 2, #pts do len = len + Dist(pts[k - 1], pts[k]) end
  if len > 2.5 * Dist(pts[1], pts[#pts]) then return "roundabout" end
end
T.Path_CutLoops, T.Path_Suspect = CutLoops, Suspect   -- for tests

local function RecordPath(trail, a, b)
  local pts = {}
  for _, q in ipairs(trail or {}) do if q.map == a.map and q.inst == a.inst then pts[#pts + 1] = q end end
  pts[#pts + 1] = a
  pts = CutLoops(pts)
  if #pts < 3 then return end
  local len = 0
  for k = 2, #pts do len = len + Dist(pts[k - 1], pts[k]) end
  local straight = Dist(pts[1], a)
  if straight < PATH_MIN or len < PATH_WIND * straight then return end   -- near enough straight: nothing to learn
  local s = Simplify(pts, PATH_TOL)
  local via = {}
  for k = 1, #s - 1 do via[#via + 1] = { math.floor(s[k].x * 10 + 0.5) / 10, math.floor(s[k].y * 10 + 0.5) / 10 } end
  local new = { from = a.map, to = b.map, x = math.floor(a.x * 10 + 0.5) / 10, y = math.floor(a.y * 10 + 0.5) / 10,
                via = via, len = math.floor(len), n = 1, t = time(), suspect = Suspect(s) }
  WritPathLearned.paths = WritPathLearned.paths or {}
  local L = WritPathLearned.paths
  local same = {}
  for i, c in ipairs(L) do
    local q = c.from == new.from and c.to == new.to and T.Point(c.from, c.x, c.y)
    if q and Dist(q, a) < 80 then
      if Agree(c, new) and not new.suspect and not c.suspect then
        c.n = (c.n or 1) + 1; c.t = new.t
        if new.len > (c.len or 0) then c.via, c.len = new.via, new.len end   -- the longer ride covers more of the way
        if c.n == 2 then T.Reset() end
        return
      end
      same[#same + 1] = i
    end
  end
  -- a new way to this crossing (or a detour): kept as a candidate, at most three per crossing
  if #same >= 3 then
    local worst = same[1]
    for _, i in ipairs(same) do
      if (L[i].n or 1) < (L[worst].n or 1) or ((L[i].n or 1) == (L[worst].n or 1) and (L[i].t or 0) < (L[worst].t or 0)) then worst = i end
    end
    table.remove(L, worst)
  end
  L[#L + 1] = new
end
T.Path = { Simplify = Simplify, Agree = Agree, Record = function(trail, a, b) RecordPath(trail, a, b) end }

-- Checkpoints (roads learned from many rides): the world is tiled with 50-yard hexes (HexKey above). While a writ route is
-- under way, every step from one hex into the next is counted, once per run, and so is each hex it passes. A hex is
-- road when 3 different runs went through it or a neighbour (Build); a wrong turn or a chase almost never repeats. Each step also keeps how slow it was (its time against the
-- time it takes at the speed you were moving: 1.0 is open riding, 2.0 took twice as long), and each spot how often
-- someone died or swam there.
local CellKey = HexKey
local function Roads()
  -- v2: 50-yard hexes (the first version used 100-yard squares; those few records are dropped)
  if not (WritPathLearned.roads and WritPathLearned.roads.v == 2) then WritPathLearned.roads = { v = 2, cells = {}, edges = {}, near = {} } end
  return WritPathLearned.roads
end
local function Edge0(v) if type(v) == "number" then return { n = v } end; return v end   -- older saves: a bare count
-- p: a spot of a leg being saved (with the speed and swimming seen there when it was ridden)
local function RecordStep(p, now)
  local run = WritPathNav and WritPathNav.run
  local runId = run and run.start or 0
  if REC.runId ~= runId then REC.runId, REC.runSteps, REC.runSwim, REC.runCells, REC.runNear = runId, {}, {}, {}, {} end
  local key = CellKey(p)
  local R = Roads()
  local cell = R.cells[key]
  if not cell then cell = { m = p.map, x = math.floor(p.x * 10 + 0.5) / 10, y = math.floor(p.y * 10 + 0.5) / 10 }; R.cells[key] = cell end
  if not REC.runCells[key] then
    REC.runCells[key] = true; cell.v = (cell.v or 0) + 1      -- runs through this hex
    -- runs through it or a neighbour (each run once per hex)
    R.near = R.near or {}
    local around = HexNeighbours(key); around[#around + 1] = key
    for _, k in ipairs(around) do
      if not REC.runNear[k] then REC.runNear[k] = true; R.near[k] = (R.near[k] or 0) + 1 end
    end
  end
  -- swimming here (once per run per spot)
  if p.swim and not REC.runSwim[key] then REC.runSwim[key] = true; cell.w = (cell.w or 0) + 1 end
  -- the speed you were moving at, sampled while in this spot
  local speed = p.speed   -- nil when the game kept it secret
  if speed and speed > 0 then REC.speedSum, REC.speedN = (REC.speedSum or 0) + speed, (REC.speedN or 0) + 1 end
  local prev = REC.cell
  if prev == key then return end
  local prevP, prevT, sum, cnt = REC.cellP, REC.cellT, REC.speedSum, REC.speedN
  REC.cell, REC.cellP, REC.cellT, REC.speedSum, REC.speedN = key, p, now, 0, 0
  if not prev then return end
  local step = prev .. ">" .. key
  if REC.runSteps[step] then return end   -- once per run
  REC.runSteps[step] = true
  local e = Edge0(R.edges[step] or { n = 0 })
  e.n = (e.n or 0) + 1
  e.g = 1   -- ridden under 1.15.2's rules (a plan running, closing in on the stop): only these steps are shared
  -- how slow: the time it took against the time at the speed you were going (0.5 to 5)
  local d = prevP and Dist(prevP, p) or 0
  if prevT and now and cnt and cnt > 0 and d > 20 then
    local expected = d / (sum / cnt)
    local ratio = math.max(0.5, math.min(5, (now - prevT) / expected))
    e.r, e.k = (e.r or 0) + ratio, (e.k or 0) + 1
  end
  R.edges[step] = e
end
-- someone died here (counted on the spot where it happened)
local function RecordDeath(p)
  local R = Roads()
  local key = CellKey(p)
  local cell = R.cells[key] or { m = p.map, x = math.floor(p.x * 10 + 0.5) / 10, y = math.floor(p.y * 10 + 0.5) / 10 }
  cell.d = (cell.d or 0) + 1
  local lvl = PlayerLevel()
  cell.dl, cell.dh = math.min(cell.dl or lvl, lvl), math.max(cell.dh or lvl, lvl)   -- the levels of those who died here
  R.cells[key] = cell
end
T.RoadEdge = Edge0
T.Roads = Roads

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

-- Travelling on purpose, or questing with a route open? Road steps are only noted when all of these hold:
--  * not fighting;
--  * the route isn't stale: a guide step was done in the last STALE seconds;
--  * you're getting closer to the guide's current stop: at least HEAD_GAIN yards nearer than HEAD_SECS ago
--    (the first HEAD_SECS after a step changes count as heading out, and are noted);
--  * the stop is on this continent (on another, there's nothing to judge by, so nothing is noted).
-- Questing wanders around a hub and gets nowhere; riding to a customer closes in on it.
local STALE, HEAD_SECS, HEAD_GAIN = 900, 30, 40
local TUNNEL_SECS, TUNNEL_YDS = 180, 1500   -- a crossing through a stretch with no map position: at most this long and far
local SPEED_HOLD = 20   -- seconds a mounted speed must hold before it can become your best (outlasts potions and trinkets)
local function Heading(p, now)
  local function No(why) REC.why = why; if REC.heading then REC.heading.log = {} end; return false end   -- start the history afresh
  if WritPath_Open(UnitAffectingCombat, "player") then return No("combat") end
  if not WritPath_RouteTarget then return No("no route") end
  local at, since, step = WritPath_RouteTarget()
  REC.whyStep, REC.whyAt, REC.whyD = step, at, nil
  if not at then return No("no stop") end
  if now - (since or 0) > STALE then return No("stale") end
  local goal = T.Point(at[1], at[2], at[3])
  local d = goal and goal.inst == p.inst and Dist(p, goal)
  -- the stop is on another continent: nothing to judge by, so nothing is noted (1.15.2: it used to be)
  if not d then return No("other continent") end
  REC.whyD = d
  local h = REC.heading
  if not h or h.step ~= step then h = { step = step, t0 = since or now, log = {} }; REC.heading = h end
  local log = h.log
  if log[#log] and now - log[#log].t > 5 then log = {}; h.log = log end   -- a gap (a flight, a pause): no old samples
  log[#log + 1] = { t = now, d = d }
  while log[2] and now - log[2].t >= HEAD_SECS do table.remove(log, 1) end   -- keep the sample about HEAD_SECS old
  -- the first HEAD_SECS of a leg (after a hand-in, or landing from a flight) are noted: too soon to judge, and it's the
  -- ride out of town that everyone takes. A few hexes of questing here don't become road (that takes 3 runs nearby).
  if now - h.t0 < HEAD_SECS then REC.why = "heading out"; return true end
  local old = log[1]
  local ready = old and now - old.t >= HEAD_SECS * 0.5
  local ok = ready and (old.d - d >= HEAD_GAIN * (now - old.t) / HEAD_SECS) or false
  REC.why = ok and "closing in" or (ready and "not closing in" or "warming up")
  return ok
end
T.Heading = Heading

-- the hostile mobs around you (enemy nameplates), noted on the hex you're in: lowest and highest level, a "??"
-- mob, an elite. Only while heading to a stop on a route, at most once a second.
local function RecordMobs(p, now)
  if not (C_NamePlate and C_NamePlate.GetNamePlates) or now - (REC.mobsAt or 0) < 1 then return end
  REC.mobsAt = now
  local lo, hi, skull, elite
  for _, plate in ipairs(C_NamePlate.GetNamePlates() or {}) do
    local u = plate.namePlateUnitToken or (plate.UnitFrame and plate.UnitFrame.unit)
    local O = WritPath_Open   -- any of these can be secret: then the mob is skipped
    if u and O(UnitExists, u) and not O(UnitIsPlayer, u) and O(UnitCanAttack, "player", u) and not O(UnitIsDead, u)
       and (O(UnitReaction, u, "player") or 4) <= 3 and O(UnitCreatureType, u) ~= "Critter" then
      local lv = O(UnitLevel, u)
      if lv == -1 then skull = true elseif lv and lv > 0 then lo, hi = math.min(lo or lv, lv), math.max(hi or lv, lv) end
      local cl = O(UnitClassification, u)
      if cl == "elite" or cl == "rareelite" or cl == "worldboss" then elite = true end
    end
  end
  if not (lo or skull) then return end
  local R = Roads()
  local key = CellKey(p)
  local cell = R.cells[key]
  if not cell then cell = { m = p.map, x = math.floor(p.x * 10 + 0.5) / 10, y = math.floor(p.y * 10 + 0.5) / 10 }; R.cells[key] = cell end
  if lo then cell.l, cell.h = math.min(cell.l or lo, lo), math.max(cell.h or hi, hi) end
  if skull then cell.s = true end
  if elite then cell.e = true end
end
T.RecordMobs = RecordMobs

---------------------------------------------------------------- road steps, saved at a writ hand-in (1.15.2)
-- While a plan runs, the ride is kept as a leg (REC.leg: a spot a second since the last flight, hand-in, teleport,
-- death or jump). Nothing becomes road until a writ is handed in, the proof that the ride led to a customer; a leg
-- that never ends at one (questing, wandering) just goes. At a hand-in:
--   * the approach, the last APPROACH_YDS, is saved: the way in to the customer, which no traced road knows;
--   * the whole leg too if it was direct: no longer than DIRECT times the straight line (plus SLACK yards for the
--     odd bend), with no stop over LEG_STOP seconds on the way. A detour to quest fails that; a shortcut passes.
local LEG_MAX, APPROACH_YDS, DIRECT, SLACK, LEG_STOP = 3600, 500, 1.5, 150, 60
local function LegAdd(p, now)
  local leg = REC.leg
  if not leg then leg = {}; REC.leg = leg end
  local tail = leg[#leg]
  if tail and now - tail.t < 1 then return end
  local s = { map = p.map, x = p.x, y = p.y, inst = p.inst, wx = p.wx, wy = p.wy, t = now,
              speed = WritPath_Open(GetUnitSpeed, "player"), swim = WritPath_Open(IsSwimming) and true or nil }
  -- standing about before setting off (at the mailbox, after a hand-in) isn't part of the leg
  if #leg == 1 and Dist(tail, p) < 2 then leg[1] = s; return end
  leg[#leg + 1] = s
  if #leg > LEG_MAX then table.remove(leg, 1) end
end
-- how the last leg went: its length, the straight line, the longest stop (not counting the wait at its end)
local function LegShape(leg)
  local len, stop, still = 0, 0, nil
  for i = 2, #leg do
    local d = Dist(leg[i - 1], leg[i])
    len = len + d
    if d < 2 then still = still or leg[i - 1].t
    else
      if still then stop = math.max(stop, leg[i - 1].t - still) end
      still = nil
    end
  end
  return len, Dist(leg[1], leg[#leg]), stop
end
local function CommitLeg()
  local leg = REC.leg
  REC.leg = nil
  if not (leg and #leg >= 2) then return 0, "none" end
  local len, straight, stop = LegShape(leg)
  local direct = len <= DIRECT * straight + SLACK and stop <= LEG_STOP
  local first = 1
  if not direct then   -- the approach only: back from the hand-in until APPROACH_YDS
    local back = 0
    first = #leg
    while first > 1 and back < APPROACH_YDS do back = back + Dist(leg[first - 1], leg[first]); first = first - 1 end
  end
  REC.cell = nil
  for i = first, #leg do RecordStep(leg[i], leg[i].t) end
  REC.cell = nil
  T.Reset()
  return #leg - first + 1, direct and "leg" or "approach"
end
T.LegShape, T.CommitLeg = LegShape, CommitLeg
-- a writ was handed in (Planner): save the ride that led here
function T.WritHandedIn()
  local n, how = CommitLeg()
  REC.lastCommit = { n = n, how = how }
  if WritPathNav then
    local rl = WritPathNav.recLog or {}; WritPathNav.recLog = rl
    rl[#rl + 1] = ("%s hand-in: saved %d spots (%s)"):format(date and date("%H:%M:%S") or "", n, how)
  end
end

local function Poll()
  if not WritPathLearned then return end
  local now = GetTime()
  local p = T.PlayerPoint()
  local taxi = WritPath_Open(UnitOnTaxi, "player") and true or false
  local dead = WritPath_Open(UnitIsDeadOrGhost, "player")
  -- a death counts on a route only if you were heading to the stop just before the fight (not while questing)
  if dead and not REC.dead and p and not p.sea and WritPath_RouteActive and WritPath_RouteActive()
     and now - (REC.headingAt or -1e9) < 60 then RecordDeath(p) end
  REC.dead = dead
  local inside = IsInInstance and IsInInstance()
  local last = REC.last
  -- a writ plan under way? Road steps and boat trips are only noted then (questing wanders; a summon once passed for
  -- a boat). Crossings and flight times are facts whatever you're doing, so they're noted anyway (outside capitals).
  local onRoute = WritPath_RouteActive and WritPath_RouteActive() or false

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
  -- your mount's speed: GetUnitSpeed's second value is the run speed with the mount included. Read when you mount,
  -- and once more SPEED_HOLD seconds later if you're still on it; the same speed both times becomes your best (it
  -- only goes up). A slow never lowers it, and a speed potion or trinket (10-15 s) has worn off by the second read,
  -- so that read becomes the new first one instead. An aura you always ride with counts: it's there both times.
  local mounted = not taxi and WritPath_Open(IsMounted) and true or false
  if not mounted then REC.speed, REC.speedAt = nil, nil
  elseif not REC.speedAt or now - REC.speedAt >= SPEED_HOLD then
    local run, r
    if GetUnitSpeed then r = select(2, GetUnitSpeed("player")) end
    if not (issecretvalue and issecretvalue(r)) and type(r) == "number" and r > 7.1 and r < 30 then
      run = math.floor(r * 10 + 0.5) / 10
    end
    local at = now
    if run and run == REC.speed then
      WritPathChar = WritPathChar or {}
      if not WritPathChar.mountBest or run > WritPathChar.mountBest then WritPathChar.mountBest = run end
      at = math.huge   -- known: no more reads until you mount again
    end
    REC.speed, REC.speedAt = run, at
  end
  -- a tunnel (Timbermaw Hold's Moonglade end, for one): the game gives no map position inside. Keep the last spot
  -- before it went missing; reappearing in another zone close by soon after is a crossing from that spot.
  if not p and last and not taxi and not dead and not inside then REC.lost = REC.lost or { at = last, t = now } end
  if not p or inside or p.sea then return end
  local lost = REC.lost
  REC.lost = nil
  if lost and not taxi and not dead and not lost.at.taxi and lost.at.map ~= p.map and lost.at.inst == p.inst
     and now - lost.t <= TUNNEL_SECS and now - REC.teleport > 30 and Dist(lost.at, p) < TUNNEL_YDS then
    local cityGap = ALLIANCE_CITIES[p.map] or HORDE_CITIES[p.map] or ALLIANCE_CITIES[lost.at.map] or HORDE_CITIES[lost.at.map]
    if not cityGap or onRoute then RecordCrossing(lost.at, p) end
  end

  local clean = not taxi and not dead and not (last and last.taxi) and now - REC.teleport > 30
  -- the breadcrumb trail (reset by anything that isn't riding: a flight, a teleport, dying, a big jump). Only kept
  -- while a writ route is under way: then you're travelling on purpose, not questing or wandering about town, so a
  -- path is the way you meant to go. Crossings and flight times are recorded all the time, except in capitals; boat
  -- trips only on a route (1.15.2).
  local heading = onRoute and Heading(p, now)
  if heading then REC.headingAt = now; if clean then RecordMobs(p, now) end end
  -- why the recorder did or didn't note this spot, every 5 seconds on a route (WritPathNav.recLog, the last 300):
  -- for finding out why a ride wasn't recorded
  if onRoute and now - (REC.logAt or 0) >= 5 then
    REC.logAt = now
    WritPathNav = WritPathNav or {}
    local rl = WritPathNav.recLog or {}; WritPathNav.recLog = rl
    local at = REC.whyAt
    rl[#rl + 1] = ("%s %d %.1f,%.1f step %s -> %s %s d %s %s %s%s%s"):format(date and date("%H:%M:%S") or "", p.map, p.x, p.y,
      tostring(REC.whyStep), at and at[1] or "-", at and ("%.1f,%.1f"):format(at[2], at[3]) or "-",
      REC.whyD and math.floor(REC.whyD) or "-", "leg " .. (REC.leg and #REC.leg or 0), tostring(REC.why),
      taxi and " taxi" or "", clean and "" or " notclean")
    while #rl > 300 do table.remove(rl, 1) end
  end
  -- the leg: kept while a plan runs; a flight, teleport, death or jump starts a new one
  local jump = last and (p.inst ~= last.inst or Dist(p, last) > 300)
  if not onRoute or not clean or jump then REC.leg = nil end
  if onRoute and clean then LegAdd(p, now) end
  if not clean or not heading or jump then
    REC.trail = nil   -- the next checkpoint starts afresh (no path across a flight or a jump)
  else
    REC.trail = REC.trail or {}
    local tr = REC.trail
    local tail = tr[#tr]
    if not tail or Dist(tail, p) >= TRAIL_STEP then
      tr[#tr + 1] = { map = p.map, x = p.x, y = p.y, inst = p.inst, wx = p.wx, wy = p.wy, t = now }
    end
    while tr[1] and now - tr[1].t > TRAIL_SECS do table.remove(tr, 1) end
  end
  -- in a capital (or just leaving one) nothing is noted unless a writ route is under way: cities are where people
  -- live and wander, not where they travel on purpose
  local city = ALLIANCE_CITIES[p.map] or HORDE_CITIES[p.map] or (last and (ALLIANCE_CITIES[last.map] or HORDE_CITIES[last.map]))
  if last and clean and p.map ~= last.map and (onRoute or not city) then
    if p.inst == last.inst then
      if Dist(p, last) < NEAR_CROSS and now - last.t < 5 then
        RecordCrossing(last, p)
        RecordPath(REC.trail, last, p)
        REC.trail = { { map = p.map, x = p.x, y = p.y, inst = p.inst, wx = p.wx, wy = p.wy, t = now } }
      end
    elseif onRoute and REC.still and now - REC.still.t < 600 and now - REC.still.t >= 45 then
      -- a ship: from where you last stood waiting. A boat or zeppelin takes a minute or more to cross; landing
      -- on the other continent sooner was a summon, portal or teleport (a summon was once taken for an Orgrimmar -> Badlands
      -- zeppelin), not a ship
      RecordShip(REC.still, p)
    end
  end

  -- where you last stood still for ten seconds (waiting at a dock looks like this)
  if city and not onRoute then
    REC.stillSince, REC.still = nil, nil
  elseif last and Dist(p, last) < 2 then
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
  -- the Hearthstone only if you allow it (the planner's Hearth box, /writs hearth; per character)
  if hs and ItemCount(HEARTH) > 0 and not (WritPathChar and WritPathChar.noHearth) then
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
    local p = T.Point(1450, 44.1, 45.2)   -- where Teleport: Moonglade lands, by the druids' own flight masters
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
rec:SetScript("OnEvent", WritPath_Timed("road recorder events", function(_, event, unit, _, spellID)
  if event == "PLAYER_ENTERING_WORLD" then return end
  if event == "CHAT_MSG_SYSTEM" then
    -- "X is now your home.": you're standing at the innkeeper
    if WritPath_Text(unit) and unit:match(HOME) then C_Timer.After(0.5, T.SaveHearth) end
    return
  end
  if unit ~= "player" then return end
  local name = spellID and ((C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(spellID)) or (GetSpellInfo and GetSpellInfo(spellID)))
  if name and (name:find("Hearthstone") or name:find("Teleport") or name:find("Portal") or name:find("Astral Recall")) then
    REC.teleport = GetTime()   -- what follows isn't a road or a ship
    -- landed from a hearthstone: that's where it's bound
    if name:find("Hearthstone") or name:find("Astral Recall") then C_Timer.After(8, T.SaveHearth) end
  end
end))
local acc = 0
rec:SetScript("OnUpdate", WritPath_Timed("road recorder", function(_, e) acc = acc + e; if acc >= 0.5 then acc = 0; Poll() end end))
T.Recorder = { Poll = Poll, State = REC }
