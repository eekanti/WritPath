-- WritPath guide: a step window and a navigation arrow.
-- Steps complete by themselves (writ handed in, flight taken, zone reached); the
-- checkbox on a step completes it by hand. Styled through EllesmereUI's skinning API when it's
-- installed; otherwise a plain flat dark look. The arrow is WritPath's own (Media/arrow.tga).
-- /writs  show or hide the guide     /writs help  the other commands

local ROUTE = {}   -- the planned route (WritPathNav.route); empty until you start one from the planner
local function Print(msg) DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99WritPath|r " .. msg) end

local TEX = {
  arrow   = "Interface/AddOns/WritPath/Media/arrow",
  flat    = "Interface/BUTTONS/WHITE8X8",
  icon    = "Interface/AddOns/WritPath/Media/icon",
  discord = "Interface/AddOns/WritPath/Media/discord",
  box     = "Interface/Buttons/UI-CheckBox-Up",
  checked = "Interface/Buttons/UI-CheckBox-Check",
}
local THEME = {   -- flat dark; the current step takes your EllesmereUI accent when there is one
  background = { 0.07, 0.06, 0.05, 0.95 },
  strip      = { 0.04, 0.035, 0.03, 1 },
  step       = { 0.11, 0.10, 0.09, 1 },
  current    = { 0.10, 0.30, 0.24, 1 },
}
local ICONS = {
  fly      = "|TInterface/GossipFrame/TaxiGossipIcon:0|t",
  turnin   = "|TInterface/GossipFrame/DailyActiveQuestIcon:0|t",
  ["goto"] = "|TInterface/MINIMAP/POIICONS:0:0:0:0:128:128:96:112:0:16|t",
  boat     = "|TInterface/Icons/INV_Misc_Anchor:0|t",
  zeppelin = "|TInterface/Icons/INV_Misc_Bomb_04:0|t",
  rep      = "|TInterface/GossipFrame/WorkOrderGossipIcon:0|t",
  hs       = "|TInterface/MINIMAP/TRACKING/Innkeeper:0|t",
  buy      = "|TInterface/GossipFrame/VendorGossipIcon:0|t",
  fp       = "|TInterface/GossipFrame/TaxiGossipIcon:0|t",
}
local function Icons(s) return (s:gsub("{(%w+)}", function(k) return ICONS[k] or "" end)) end

---------------------------------------------------------------- positions
local HBD
local function Lib()
  if HBD == nil then HBD = LibStub and LibStub("HereBeDragons-2.0", true) or false end
  return HBD
end

local function World(mapID, x, y)          -- own fallback when HereBeDragons isn't around
  local ok, cont, pos = pcall(C_Map.GetWorldPosFromMapPos, mapID, CreateVector2D(x, y))
  if ok and cont and pos then local wx, wy = pos:GetXY(); return cont, wx, wy end
end

local function PlayerMap() return C_Map.GetBestMapForUnit("player") end

-- distance in yards and bearing (radians, counter-clockwise from north); nil + reason if none
local function Vector(g)
  local hbd = Lib()
  if hbd then
    local tx, ty, ti = hbd:GetWorldCoordinatesFromZone(g[2] / 100, g[3] / 100, g[1])
    local px, py, pi = hbd:GetPlayerWorldPosition()
    if not (tx and px) then return nil, "nopos" end
    if ti ~= pi then return nil, "continent" end
    local angle, dist = hbd:GetWorldVector(pi, px, py, tx, ty)
    return dist, angle
  end
  local map = PlayerMap(); if not map then return nil, "nopos" end
  local pos = C_Map.GetPlayerMapPosition(map, "player"); if not pos then return nil, "nopos" end
  local pc, px, py = World(map, pos:GetXY())
  local tc, tx, ty = World(g[1], g[2] / 100, g[3] / 100)
  if not (pc and tc) then return nil, "nopos" end
  if pc ~= tc then return nil, "continent" end
  local dx, dy = tx - px, ty - py
  local _, ox, oy = World(map, 0.5, 0.5); local _, ex, ey = World(map, 0.6, 0.5); local _, sx, sy = World(map, 0.5, 0.6)
  local exv, eyv, sxv, syv = ex - ox, ey - oy, sx - ox, sy - oy
  local east = (dx * exv + dy * eyv) / math.sqrt(exv * exv + eyv * eyv)
  local south = (dx * sxv + dy * syv) / math.sqrt(sxv * sxv + syv * syv)
  return math.sqrt(dx * dx + dy * dy), math.atan2(-east, -south)
end

---------------------------------------------------------------- step state
local function QuestDone(q) return C_QuestLog.IsQuestFlaggedCompleted(q) end
local function Count(id) return WritPath_BagCount(id) end   -- in your bags, not worn (WritPath.lua)

-- a step on the way somewhere (it has a waypoint, and it isn't a hand-in or the shopping step)
local NEAR_YARDS = 200
local function TravelStep(s) return s and s.at and s.done and not s.done.quests and not s.done.ready end
local function Near(s) local dist = Vector(s.at); return dist and dist <= NEAR_YARDS end
local function InZone(zones)
  local m = PlayerMap(); if not m then return false end
  local z = WritPath_Travel and WritPath_Travel.ZoneOf(m) or m
  for _, a in ipairs(zones or {}) do if m == a or z == a then return true end end
  return false
end
-- the zones whose arrival finishes a step: never the zone the step itself starts in (a flight from Grom'gol
-- to Booty Bay lands in Stranglethorn, where you already are: being there says nothing)
local function ArriveZones(s)
  local d = s and s.done
  if not (d and d.arrive) then return nil end
  local own = s.at and (WritPath_Travel and WritPath_Travel.ZoneOf(s.at[1]) or s.at[1])
  local t = {}
  for _, a in ipairs(d.arrive) do if a ~= own and (not s.at or a ~= s.at[1]) then t[#t + 1] = a end end
  return #t > 0 and t or nil
end

-- Only the current step is tested, and a step once done stays done (WritPathNav.manual),
-- so landing after a flight or leaving a zone never sends the guide back.
local function StepDone(i)
  local s = ROUTE[i]; if not s then return false end
  if WritPathNav.manual[i] then return true end
  local hit = false
  local d = s.done
  if d.quests then
    hit = true
    for _, q in ipairs(d.quests) do if not QuestDone(q) then hit = false end end
  end
  if d.ready then   -- planned route's shopping step: every writ bought and accepted, every item in the bags
    hit = true
    for _, q in ipairs(d.ready.quests or {}) do
      local inLog = C_QuestLog.GetLogIndexForQuestID and C_QuestLog.GetLogIndexForQuestID(q)
      if not (QuestDone(q) or inLog) then hit = false end
    end
    for _, it in ipairs(d.ready.items or {}) do   -- { item, count, quest }: not needed once that writ is done
      if not QuestDone(it[3]) and Count(it[1]) < it[2] then hit = false end
    end
  end
  if d.taxi and WritPath_Open(UnitOnTaxi, "player") then hit = true end
  if d.arrive and InZone(ArriveZones(s)) then hit = true end
  -- a waypoint on the way (a road crossing) is done once you're close to it; a flight master only once you've
  -- taken the flight (or landed), a boat or zeppelin once you land, a writ customer only when you've handed it in
  if not hit and TravelStep(s) and not d.taxi and not d.taxiMap and not d.sail and not d.pin and Near(s) then hit = true end
  if hit then WritPathNav.manual[i] = true end
  return hit
end

local function SetWaypoint(s)
  pcall(function()
    if not (s and s.at) then C_Map.ClearUserWaypoint(); return end
    local g = (s.way and s.way[s.wayI or 1]) or s.at
    if C_Map.CanSetUserWaypointOnMap and not C_Map.CanSetUserWaypointOnMap(g[1]) then return end
    C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(g[1], g[2] / 100, g[3] / 100))
    if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then C_SuperTrack.SetSuperTrackedUserWaypoint(true) end
  end)
end

-- A road or path step ("Follow the road") carries its waypoints (s.way); the arrow and the map pin point to one at a
-- time. A waypoint is passed once you're within WAY_NEAR yards of it, or nearer the next one than it is (a corner
-- cut). The step itself is done at its end (s.at), like any step on the way.
local WAY_NEAR = 60
local function WorldYds(g)
  local hbd = Lib()
  if hbd then local x, y, i = hbd:GetWorldCoordinatesFromZone(g[2] / 100, g[3] / 100, g[1]); return i, x, y end
  return World(g[1], g[2] / 100, g[3] / 100)
end
local function Gap(a, b)
  local ac, ax, ay = WorldYds(a)
  local bc, bx, by = WorldYds(b)
  if not (ac and bc and ax and bx) or ac ~= bc then return nil end
  return math.sqrt((ax - bx) ^ 2 + (ay - by) ^ 2)
end
-- where you stand in world yards: continent, x, y
local function PlayerYds()
  local hbd = Lib()
  if hbd then local x, y, i = hbd:GetPlayerWorldPosition(); return i, x, y end
  local map = PlayerMap(); if not map then return nil end
  local pos = C_Map.GetPlayerMapPosition(map, "player"); if not pos then return nil end
  return World(map, pos:GetXY())
end
-- Bends passed without coming near them (joined the road partway along, rode past a few bends off the line, or the
-- arrow wasn't shown for a while): the arrow looks ahead for the stretch of road you're on and leads to its far end.
-- Only a few bends ahead, so a road that doubles back past itself isn't cut short. (1.16.2: players were sent 200
-- yards back along a road because only the very next bend was ever checked.)
local LOOK_AHEAD, ON_ROAD = 8, 50   -- bends looked ahead; yards from a stretch that count as being on it
local function Ahead(w, i)
  local pc, px, py = PlayerYds()
  if not (pc and px) then return i end
  local best, bd = nil, ON_ROAD
  for k = math.max(1, i - 1), math.min(#w - 1, i + LOOK_AHEAD) do   -- the stretch from bend k to bend k + 1 (from the one
                                                                   -- you are on now: nearest to it, the arrow stays)
    local ac, ax, ay = WorldYds(w[k])
    local bc, bx, by = WorldYds(w[k + 1])
    if ac == pc and bc == pc and ax and bx then
      local dx, dy = bx - ax, by - ay
      local len2 = dx * dx + dy * dy
      local t = len2 > 0 and math.max(0, math.min(1, ((px - ax) * dx + (py - ay) * dy) / len2)) or 0
      local d = math.sqrt((px - ax - t * dx) ^ 2 + (py - ay - t * dy) ^ 2)
      if d < bd then best, bd = k + 1, d end
    end
  end
  return best and best > i and best or i
end
-- yards from you to the nearest stretch of a road's waypoints (nil: not on this continent, or no position)
local ROAD_LEAVE = 100
function WritPath_RoadGap(w)
  local pc, px, py = PlayerYds()
  if not (pc and px and w) then return nil end
  local best
  for k = 1, #w - 1 do
    local ac, ax, ay = WorldYds(w[k])
    local bc, bx, by = WorldYds(w[k + 1])
    if ac == pc and bc == pc and ax and bx then
      local dx, dy = bx - ax, by - ay
      local len2 = dx * dx + dy * dy
      local t = len2 > 0 and math.max(0, math.min(1, ((px - ax) * dx + (py - ay) * dy) / len2)) or 0
      local d = math.sqrt((px - ax - t * dx) ^ 2 + (py - ay - t * dy) ^ 2)
      if not best or d < best then best = d end
    end
  end
  return best
end
---------------------------------------------------------------- terrain walks (Shortest Path Forever)
-- With Shortest Path Forever installed, the walk to a step's spot follows the ground (around cliffs, water and
-- buildings) instead of a straight line. Its public API (WalkPath) gives the bends; the arrow leads through them the
-- way it leads along a road. None of its data is copied into WritPath. Without it, the arrow points straight as before.
local OWNER = "WritPath"
local WALK_MIN = 80     -- yards: nearer than this, a walk isn't worked out (straight is fine)
local WALK_OFF = 80     -- yards strayed off the path before it's worked out again from where you are
local WALK_AGAIN = 5    -- seconds between requests
local WALK_FAIL = 30    -- after no path, seconds before asking again for that step
local WALK_WAIT = 20    -- seconds a request may take before it's given up and asked again
local walk = {}         -- { s, at, pts, i, from, asked, failed, cancel }
local function SPF()
  local api = ShortestPathForever and ShortestPathForever.API
  if type(api) == "table" and (api.version == 1 or api.version == 2) and type(api.WalkPath) == "function" then return api end
end
local function WalkReset() if walk.cancel then pcall(walk.cancel) end; walk = {} end

local function WalkAsk(s, at)
  local api, now = SPF(), GetTime()
  if not api then return end
  if walk.asked and now - walk.asked < (walk.failed and WALK_FAIL or walk.cancel and WALK_WAIT or WALK_AGAIN) then return end
  if WritPath_Open(UnitOnTaxi, "player") or WritPath_Open(InCombatLockdown) then return end
  local map = PlayerMap()
  local pos = map and C_Map.GetPlayerMapPosition(map, "player"); if not pos then return end
  local px, py = pos:GetXY(); if not (px and py) then return end
  if walk.cancel then pcall(walk.cancel) end
  at = at or s.at
  -- the old bends stay in use until the new ones arrive
  local mine = { s = s, at = at, pts = walk.pts, i = walk.i, from = walk.from, prog = walk.prog, line = walk.line, asked = now,
                 start = { map, px * 100, py * 100, at[4] } }
  walk = mine
  local ok, cancel = pcall(api.WalkPath, OWNER, { map = map, x = px, y = py }, { map = at[1], x = at[2] / 100, y = at[3] / 100 },
    function(path)
      if walk ~= mine then return end   -- the step moved on, or a newer request replaced this one
      mine.cancel = nil
      local w = type(path) == "table" and path.waypoints
      if type(w) ~= "table" or #w < 2 then mine.failed = true; return end
      local pts = {}
      for k = 2, #w - 1 do   -- the first is where you stood; the last is its snap of the step's spot
        local p = w[k]
        if type(p) == "table" and p.map and p.x and p.y then pts[#pts + 1] = { p.map, p.x * 100, p.y * 100, at[4] } end
      end
      pts[#pts + 1] = at     -- end on the step's own spot
      mine.pts, mine.i, mine.from, mine.failed, mine.prog, mine.line = pts, 1, mine.start, nil, nil, nil
    end)
  if ok and type(cancel) == "function" then mine.cancel = cancel else mine.failed = true end
end

-- The arrow points CARROT yards further along the ground path from where you are on it, so it only ever points
-- along ground Shortest Path Forever knows is passable, and always onwards (1.18.0). Where you are on it is the
-- nearest spot of the path, looked for only a little behind and ahead of how far along it you've got: a ramp up a
-- mountain has its legs stacked close together on the map (no heights), and the leg above isn't where you are.
-- (Before: the arrow pointed at the next bend; the bends sit a few yards apart and wiggle, so it could point back
-- over your shoulder with the step dead ahead.)
local CARROT = 25                    -- yards ahead along the path
local SMOOTH_FROM, SMOOTH_TO = 15, 45   -- yards ahead: the stretch of path whose middle the arrow points at
local SEEK_BACK, SEEK_AHEAD = 20, 100   -- yards of path behind and ahead of your progress searched for where you are
local function Line(pts)
  local l = walk.line
  if l and l.pts == pts then return l end
  local seq = {}
  if walk.from then seq[1] = walk.from end
  for k = 1, #pts do seq[#seq + 1] = pts[k] end
  l = { pts = pts, seq = seq, xy = {}, cum = { 0 } }
  for k = 1, #seq do
    local c, x, y = WorldYds(seq[k])
    if not (c and x) then return nil end
    l.c = l.c or c
    if c ~= l.c then return nil end
    l.xy[k] = { x, y }
    if k > 1 then l.cum[k] = l.cum[k - 1] + math.sqrt((x - l.xy[k - 1][1]) ^ 2 + (y - l.xy[k - 1][2]) ^ 2) end
  end
  walk.line = l
  return l
end
-- a spot `arc` yards along the path, as a waypoint { map, x, y, label }, and the index (into seq) of the bend after it
local function Along(l, arc, label)
  local seq, cum = l.seq, l.cum
  for k = 1, #seq - 1 do
    if arc < cum[k + 1] then
      local a, b = seq[k], seq[k + 1]
      local len = cum[k + 1] - cum[k]
      local t = len > 0 and (arc - cum[k]) / len or 1
      if a[1] ~= b[1] then return b, k + 1 end   -- two different maps: the bend itself
      local g = walk.carrot or {}
      g[1], g[2], g[3], g[4] = a[1], a[2] + (b[2] - a[2]) * t, a[3] + (b[3] - a[3]) * t, label
      walk.carrot = g
      return g, k + 1
    end
  end
  return seq[#seq], #seq
end

-- where the arrow points on the ground path to a step's spot (or to goal: where you join a road), or the spot itself
-- while there is no path
local function WalkTarget(s, goal)
  local at = goal or (s and s.at)
  if not at then return nil end
  if walk.s ~= s or walk.at ~= at then WalkReset() end   -- a new step
  if not SPF() then return at end
  local pts = walk.pts
  if not pts then
    local d = Vector(at)
    if d and d > WALK_MIN then WalkAsk(s, at) end
    return at
  end
  local l = Line(pts)
  local pc, px, py = PlayerYds()
  if not (l and pc == l.c and px) then return pts[math.min(walk.i or 1, #pts)] end
  -- where you are on the path
  local prog, cum, xy = walk.prog or 0, l.cum, l.xy
  local best, bestArc
  for k = 1, #xy - 1 do
    if cum[k + 1] >= prog - SEEK_BACK and cum[k] <= prog + SEEK_AHEAD then
      local a, b = xy[k], xy[k + 1]
      local dx, dy = b[1] - a[1], b[2] - a[2]
      local len2 = dx * dx + dy * dy
      local t = len2 > 0 and math.max(0, math.min(1, ((px - a[1]) * dx + (py - a[2]) * dy) / len2)) or 0
      local d2 = (px - a[1] - t * dx) ^ 2 + (py - a[2] - t * dy) ^ 2
      if not best or d2 < best then best, bestArc = d2, cum[k] + t * (cum[k + 1] - cum[k]) end
    end
  end
  if bestArc and bestArc > prog then prog = bestArc end
  walk.prog = prog
  -- strayed far off the path (or rode on beside it, past where it was looked for): worked out again from where you
  -- are, and straight at the spot meanwhile (where you left the path is behind you)
  if not best or best > WALK_OFF * WALK_OFF then WalkAsk(s, at); return at end
  if prog + CARROT >= cum[#cum] then walk.i = #pts; return at end
  local g, k = Along(l, prog + CARROT, at[4])
  walk.i = math.max(1, math.min(#pts, k - (walk.from and 1 or 0)))   -- the next bend (for tests)
  -- the path zigzags a few yards side to side, and a single spot on it slides across each zigzag: the arrow
  -- twitched. It points at the middle of the stretch SMOOTH_FROM to SMOOTH_TO yards ahead instead, where the
  -- zigzags cancel out and a real bend still pulls it round. (Needs HereBeDragons to turn it back into map
  -- coordinates; without it, the single spot.)
  local hbd = Lib()
  if hbd and hbd.GetZoneCoordinatesFromWorld then
    local sx, sy, n = 0, 0, 0
    for arc = prog + SMOOTH_FROM, prog + SMOOTH_TO, 5 do
      local a = math.min(arc, cum[#cum])
      for j = 1, #xy - 1 do
        if a <= cum[j + 1] then
          local len = cum[j + 1] - cum[j]
          local t = len > 0 and (a - cum[j]) / len or 1
          sx, sy, n = sx + xy[j][1] + (xy[j + 1][1] - xy[j][1]) * t, sy + xy[j][2] + (xy[j + 1][2] - xy[j][2]) * t, n + 1
          break
        end
      end
    end
    if n > 0 then
      local zx, zy = hbd:GetZoneCoordinatesFromWorld(sx / n, sy / n, at[1], true)
      if zx and zy then
        local m = walk.mid or {}
        m[1], m[2], m[3], m[4] = at[1], zx * 100, zy * 100, at[4]
        walk.mid = m
        return m
      end
    end
  end
  return g
end
function WritPath_WalkState() return walk end   -- for tests

local function Target(s)
  local w = s and s.way
  if not w then return WalkTarget(s) end
  -- a road step with Shortest Path Forever: its ground path to where you join the road, which knows the cliffs the
  -- straight ride onto it can't. The traced road is the fallback while there's no path. Once you're on the road,
  -- the road leads (1.17.3: the ground path wandered off a road that ran straight to Felwood, and the arrow kept
  -- swinging off it). Off it again only past ROAD_LEAVE yards, so the arrow doesn't flip at the edge. (1.18.0: the
  -- ground path went to the road's far end, beside the road, and never joined it.)
  local near = WritPath_RoadGap(w)
  if near then
    if near <= ON_ROAD then s.onRoad = true elseif near > ROAD_LEAVE then s.onRoad = nil end
  end
  if SPF() and not s.onRoad then
    local g = WalkTarget(s, w[math.min(s.wayI or 1, #w)])
    if walk.pts then return g end   -- while it's being worked out (or there's none), the traced road
  end
  local i = math.min(s.wayI or 1, #w)
  local moved = false
  while i < #w do
    local d = Vector(w[i])
    if not d then break end
    local n, gap = Vector(w[i + 1]), Gap(w[i], w[i + 1])
    if d <= WAY_NEAR or (n and gap and n < gap) then i, moved = i + 1, true else break end
  end
  local j = Ahead(w, i)
  if j > i then i, moved = j, true end
  if moved then s.wayI = i; SetWaypoint(s) end
  return w[i]
end
function WritPath_ArrowTarget() local s = ROUTE[WritPathNav.step]; return s and Target(s) end   -- for tests

---------------------------------------------------------------- guide window
local WIDTH, SHOWN = 310, 12   -- up to 12 rows, as many as fit in STEPS_H
local STEPS_H = 360            -- the step list grows to this height, then the mouse wheel scrolls it
local scroll = 0               -- rows scrolled away from the current step (negative: finished steps)
local BACKDROP = { bgFile = TEX.flat, edgeFile = TEX.flat, edgeSize = 1, insets = { left = 1, right = 1, top = 1, bottom = 1 } }

local guide = CreateFrame("Frame", "WritPathGuide", UIParent, "BackdropTemplate")
guide:SetWidth(WIDTH); guide:SetPoint("RIGHT", UIParent, "RIGHT", -60, 120)
guide:SetMovable(true); guide:EnableMouse(true); guide:RegisterForDrag("LeftButton"); guide:SetClampedToScreen(true)
guide:SetBackdrop(BACKDROP); guide:SetBackdropColor(unpack(THEME.background)); guide:SetBackdropBorderColor(0, 0, 0, 1); guide:Hide()

local header = CreateFrame("Frame", nil, guide, "BackdropTemplate")
header:SetHeight(26); header:SetPoint("BOTTOMLEFT", guide, "TOPLEFT", 0, -2); header:SetPoint("BOTTOMRIGHT", guide, "TOPRIGHT", 0, -2)
header:SetBackdrop(BACKDROP); header:SetBackdropColor(unpack(THEME.strip)); header:SetBackdropBorderColor(0, 0, 0, 1)
header:EnableMouse(true); header:RegisterForDrag("LeftButton")
local logo = header:CreateTexture(nil, "ARTWORK"); logo:SetSize(16, 16); logo:SetPoint("LEFT", 6, 0); logo:SetTexture(TEX.icon)
logo:SetTexCoord(0.08, 0.92, 0.08, 0.92)
local title = header:CreateFontString(nil, "OVERLAY", "GameFontNormal"); title:SetPoint("LEFT", logo, "RIGHT", 4, 0)
title:SetText("Merchant Writs")
local count = header:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"); count:SetPoint("RIGHT", -24, 0)
local close = CreateFrame("Button", nil, header, "UIPanelCloseButton"); close:SetSize(20, 20); close:SetPoint("RIGHT", -2, 0)

-- small buttons in the header, so nothing needs a slash command
local function HeadButton(icon, tip, anchor, onClick, whole)   -- whole: our own texture, not a game icon to crop
  local b = CreateFrame("Button", nil, header)
  b:SetSize(16, 16); b:SetPoint("RIGHT", anchor, "LEFT", -4, 0)
  b:SetNormalTexture(icon)
  if not whole then b:GetNormalTexture():SetTexCoord(0.08, 0.92, 0.08, 0.92) end
  b:SetHighlightTexture("Interface/Buttons/ButtonHilight-Square", "ADD")
  b:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP"); GameTooltip:SetText(tip[1]); GameTooltip:AddLine(tip[2], 1, 1, 1, true); GameTooltip:Show()
  end)
  b:SetScript("OnLeave", function() GameTooltip:Hide() end)
  b:SetScript("OnClick", onClick)
  return b
end
local clearBtn = HeadButton("Interface/Buttons/UI-GroupLoot-Pass-Up", { "Clear", "Clear the route, the planner and its shopping list (asks first)." },
  count, function() WritPath_AskClear() end)
-- the WritPath Discord: its invite link, selected so Ctrl+C copies it
local shareBtn = HeadButton(TEX.discord, { "Discord", "The WritPath Discord's invite link, selected: press Ctrl+C to copy it, then paste it in your browser. Help and news." },
  clearBtn, function() WritPath_CopyDiscord() end, true)
local moneyBtn = HeadButton("Interface/Icons/INV_Misc_Bag_10", { "Report", "In chat: every writ you've handed in with what the writ and its item cost and what its pouch paid, then your lifetime total: writs, rep earned, pouches, spent, net and cost per rep." },
  shareBtn, function() WritPath_MoneyReport() end)
local planHeadBtn = HeadButton("Interface/Icons/INV_Misc_Map_01", { "Plan", "Plan writs: a rep target gives the cheapest and the fastest writs to reach it, starting from the ones you have; no target plans just the writs you have." },
  moneyBtn, function() WritPath_TogglePlanner() end)
title:SetPoint("RIGHT", planHeadBtn, "LEFT", -4, 0); title:SetJustifyH("LEFT"); title:SetWordWrap(false)

local function SavePos(self)
  guide:StopMovingOrSizing()
  local p, _, rp, x, y = guide:GetPoint(); WritPathNav.guidePos = { p, rp, x, y }
end
for _, f in ipairs({ guide, header }) do
  f:SetScript("OnDragStart", function() guide:StartMoving() end)
  f:SetScript("OnDragStop", SavePos)
end

local rows = {}
local Refresh
-- the mouse wheel scrolls through the whole route; it snaps back to the current step when that changes
guide:EnableMouseWheel(true)
guide:SetScript("OnMouseWheel", function(_, delta)
  scroll = scroll - delta
  if Refresh then Refresh(true) end
end)
for r = 1, SHOWN do
  local row = CreateFrame("Frame", nil, guide, "BackdropTemplate")
  row:SetBackdrop({ bgFile = "Interface/BUTTONS/WHITE8X8" })
  row.num = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  row.num:SetPoint("TOPLEFT", 6, -6); row.num:SetWidth(18); row.num:SetJustifyH("LEFT")
  row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  row.text:SetPoint("TOPLEFT", 24, -6); row.text:SetWidth(WIDTH - 62)
  row.text:SetJustifyH("LEFT"); row.text:SetJustifyV("TOP"); row.text:SetSpacing(3)
  row.check = CreateFrame("Button", nil, row)
  row.check:SetSize(16, 16); row.check:SetPoint("TOPRIGHT", -6, -5)
  row.check:SetNormalTexture(TEX.box)
  row.check:SetScript("OnClick", function(self)
    if row.index then WritPath_ToggleStep(row.index) end
  end)
  rows[r] = row
end

-- a step's box: ticked, the step is skipped (or done); unticked, it's back
function WritPath_ToggleStep(i)
  WritPathNav.manual[i] = not WritPathNav.manual[i] or nil
  -- a skipped writ or flight path stays skipped when the rest of the trip is planned again (a new zone, a
  -- hand-in): re-plans renumber the steps, so the skip is kept by writ and by flight point, not by step
  local s = ROUTE[i]
  if s and s.writ then
    WritPathNav.skipWrit = WritPathNav.skipWrit or {}
    WritPathNav.skipWrit[s.writ] = WritPathNav.manual[i] or nil
  elseif s and s.fpid and s.done and s.done.taxiMap then
    WritPathNav.skipFp = WritPathNav.skipFp or {}
    WritPathNav.skipFp[s.fpid] = WritPathNav.manual[i] or nil
  end
  Refresh(true)
end

-- a line above the steps when the zone you're in has a flight path you don't have yet
local hint = CreateFrame("Frame", nil, guide, "BackdropTemplate")
hint:SetBackdrop({ bgFile = "Interface/BUTTONS/WHITE8X8" }); hint:SetBackdropColor(0.25, 0.2, 0.05, 0.95); hint:Hide()
hint.text = hint:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
hint.text:SetPoint("TOPLEFT", 8, -6); hint.text:SetWidth(WIDTH - 24)
hint.text:SetJustifyH("LEFT"); hint.text:SetJustifyV("TOP"); hint.text:SetSpacing(3)
local HINT_YARDS = 1e9   -- anywhere in the zone
local hinted = {}   -- said in chat once per flight point per session
local function FlightHint()
  local T = WritPath_Travel
  if not (T and T.UnlearnedNear and T.PlayerPoint) then return nil end
  local ok, fp = pcall(T.UnlearnedNear, T.PlayerPoint(), HINT_YARDS)
  return ok and fp or nil
end
WritPath_FlightHintFrame = hint   -- for tests

-- EllesmereUI's look when it's installed: its window style, font and accent
if EllesmereUI and EllesmereUI.RegisterSkin then
  EllesmereUI.RegisterSkin("WritPathGuide", function(S)
    S.Panel(guide); S.Panel(header, { inset = true }); S.CloseButton(close)
    S.Font(title); S.Font(count)
    for _, row in ipairs(rows) do S.Font(row.text); S.Font(row.num) end
    if WritPath_FooterText then S.Font(WritPath_FooterText) end
    local function Accent()
      local r, g, b = S.GetAccentColor()
      if r then THEME.current = { r * 0.35, g * 0.35, b * 0.35, 1 } end
      if WritPathNav then Refresh() end
    end
    Accent()
    if S.OnLooksChanged then S.OnLooksChanged(Accent) end
  end)
end

---------------------------------------------------------------- arrow
local arrow = CreateFrame("Frame", "WritPathArrow", UIParent)
arrow:SetSize(42, 42); arrow:SetPoint("TOP", UIParent, "TOP", 0, -120)
arrow:SetMovable(true); arrow:EnableMouse(true); arrow:RegisterForDrag("LeftButton"); arrow:SetClampedToScreen(true)
arrow:SetScript("OnDragStart", arrow.StartMoving)
arrow:SetScript("OnDragStop", function(self)
  self:StopMovingOrSizing(); local p, _, rp, x, y = self:GetPoint(); WritPathNav.arrowPos = { p, rp, x, y }
end)
arrow.tex = arrow:CreateTexture(nil, "ARTWORK"); arrow.tex:SetAllPoints(); arrow.tex:SetTexture(TEX.arrow)
arrow.text = arrow:CreateFontString(nil, "OVERLAY")
arrow.text:SetFont(GameFontNormal:GetFont(), 10, "OUTLINE"); arrow.text:SetPoint("TOP", arrow, "BOTTOM", 0, -5)
arrow.text:SetJustifyH("CENTER")
-- arrived: the name and "here" in large type (1.18.0: at size 10 it was easy to miss)
function arrow:Big(big)
  big = big and true or false
  if self.big == big then return end
  self.big = big
  self.text:SetFont(GameFontNormal:GetFont(), big and 20 or 10, "OUTLINE")
end
arrow:Hide()

---------------------------------------------------------------- refresh
local lastStep

function Refresh(announce)
  -- the current step is the first one that isn't done
  local cur = 1
  while ROUTE[cur] and StepDone(cur) do cur = cur + 1 end
  -- a later writ already handed in means every waypoint before it is behind you too
  -- (you took another road or a flight and skipped a crossing step)
  for i = #ROUTE, cur + 1, -1 do
    local q = ROUTE[i].done and ROUTE[i].done.quests
    if q and #q > 0 then
      local all = true
      for _, id in ipairs(q) do if not QuestDone(id) then all = false end end
      if all then
        for j = cur, i do WritPathNav.manual[j] = true end
        while ROUTE[cur] and StepDone(cur) do cur = cur + 1 end
        break
      end
    end
  end
  -- already near a later waypoint before the next customer, or in the zone it leads to: you took another road
  -- or a shortcut, so the guide catches up (never past a customer you haven't handed in to)
  for i = cur + 1, TravelStep(ROUTE[cur]) and #ROUTE or 0 do
    local s = ROUTE[i]
    if not TravelStep(s) then break end
    if Near(s) or InZone(ArriveZones(s)) then
      for j = cur, i - 1 do WritPathNav.manual[j] = true end
      cur = i
      while ROUTE[cur] and StepDone(cur) do cur = cur + 1 end
      break
    end
  end
  WritPathNav.step = cur
  title:SetText(WritPathNav.title or "Writs")
  scroll = math.max(1 - cur, math.min(scroll, #ROUTE - cur))
  count:SetText(math.min(cur, #ROUTE) .. "/" .. #ROUTE .. (scroll ~= 0 and " |cFFAAAAAA(scrolled)|r" or ""))

  if cur ~= lastStep then
    lastStep, scroll = cur, 0   -- the route moved on: back to the current step
    WritPathNav.stepSince = GetTime()   -- when this step became the current one (the road recorder's clock)
    SetWaypoint(ROUTE[cur])
    if PlaySound and SOUNDKIT and announce then PlaySound(SOUNDKIT.IG_QUEST_LOG_OPEN or 875) end
  end

  local y = -4
  -- not while flying: passing over a zone isn't being in it
  local fp = not WritPath_Open(UnitOnTaxi, "player") and FlightHint() or nil
  if fp then
    local town = (fp.name or "a flight master"):match("^([^,]+)") or fp.name
    hint.text:SetText(("%s You don't have this zone's flight path: |cFF00FF25%s|r (%.0f, %.0f). Talk to the flight master to learn it."):format(
      ICONS.fp, town, fp.x or 0, fp.y or 0))
    hint:SetHeight(hint.text:GetStringHeight() + 12)
    hint:ClearAllPoints(); hint:SetPoint("TOPLEFT", 4, y); hint:SetPoint("TOPRIGHT", -2, y); hint:Show()
    y = y - hint:GetHeight() - 2
    if not hinted[fp.id] then
      hinted[fp.id] = true
      Print(("You don't have the %s flight path in this zone yet: the flight master is at %.0f, %.0f."):format(town, fp.x or 0, fp.y or 0))
    end
  else
    hint:Hide()
  end
  local top, full = y, false
  for r = 1, SHOWN do
    local row, i = rows[r], cur + scroll + r - 1
    local s = not full and ROUTE[i]
    row.index = s and i or nil
    if s then
      row:Show()
      row:SetBackdropColor(unpack(i == cur and THEME.current or THEME.step))
      row.num:SetText(i)
      local t = {}
      for _, l in ipairs(s.lines) do t[#t + 1] = Icons(l) end
      row.text:SetText(table.concat(t, "\n"))
      row.text:SetAlpha(i == cur and 1 or (i < cur and 0.45 or 0.7))
      row.check:SetNormalTexture(WritPathNav.manual[i] and TEX.checked or TEX.box)
      row.text:SetWidth(WIDTH - 62)
      local h = math.max(26, row.text:GetStringHeight() + 12)
      if r > 1 and (top - y) + h > STEPS_H then   -- no room: the wheel reaches the rest
        full = true; row:Hide(); row.index = nil
      else
        row:SetHeight(h)
        row:ClearAllPoints(); row:SetPoint("TOPLEFT", 4, y); row:SetPoint("TOPRIGHT", -2, y)
        y = y - h - 2
      end
    else
      row:Hide()
    end
  end

  if not ROUTE[cur] then
    local row = rows[1]; row:Show(); row.index = nil
    row:SetBackdropColor(unpack(THEME.current)); row.num:SetText("")
    if #ROUTE == 0 then
      row.text:SetText("No route yet. Open the planner with the map icon above (or right-click the minimap button).")
    else
      local done = WritPathNav.doneText or "All planned writs handed in"
      local rep = WritPathNav.doneRep and WritPath_SessionRep and WritPath_SessionRep()
      if rep then   -- what you really handed in, not what was planned
        done = ("Writs handed in: |cFF00FF25%d rep|r"):format(rep)
        if rep ~= WritPathNav.doneRep then done = done .. (" |cFFAAAAAA(planned %d)|r"):format(WritPathNav.doneRep) end
      end
      row.text:SetText(ICONS.rep .. " " .. done .. ". Close with the X.")
      if WritPath_MoneyUpdate then WritPath_MoneyUpdate() end   -- the footer's cost now counts only what happened
    end
    row.text:SetAlpha(1); row:SetHeight(30)
    local top = fp and (-4 - hint:GetHeight() - 2) or -4
    row:ClearAllPoints(); row:SetPoint("TOPLEFT", 4, top); row:SetPoint("TOPRIGHT", -2, top)
    y = top - 32
    arrow:Hide()
  elseif WritPathNav.shown then
    arrow:Show()
  end
  guide:SetHeight(-y + 4)
end

Refresh = WritPath_Timed("guide refresh", Refresh)
-- arrow and auto-complete, polled: cheap, and catches taxis and boats without extra events
local tick, poll = 0, 0
arrow:SetScript("OnUpdate", WritPath_Timed("guide arrow", function(self, e)
  tick, poll = tick + e, poll + e
  if poll > 0.5 then poll = 0; Refresh(true) end
  if tick < 0.03 then return end
  local dt = tick; tick = 0
  local s = ROUTE[WritPathNav.step]; if not s then return end
  local g = Target(s)   -- where the arrow points: a road's next waypoint, along the ground path, or the step's spot
  if not g then self.tex:SetAlpha(0); self.text:SetText(""); return end
  local dist, angle = Vector(g)
  -- the distance shown is to the marker (the map pin: a road's next waypoint, or the step's spot), not to the spot
  -- the arrow follows 25 yards ahead on the ground path (1.18.0)
  local marker = (s.way and s.way[s.wayI or 1]) or s.at
  local mdist = marker and Vector(marker) or dist
  self:Big(mdist and mdist < 10)
  if not dist then
    self.tex:SetAlpha(angle == "continent" and 0.4 or 0); self.tex:SetRotation(0)
    self.text:SetText(g[4] .. "\n" .. (angle == "continent" and "|cFFFF5722other continent|r" or "~"))
    return
  end
  if mdist and mdist < 10 then
    self.tex:SetAlpha(0); self.text:SetText(marker[4] .. "\n|cFF00FF25here|r"); return
  end
  -- the bearing eases round over a quarter second instead of snapping, so the path's small jumps don't twitch the
  -- arrow; your own turning (facing) isn't eased. A new step, or a turn past 90 degrees, snaps straight there.
  if angle then
    local b = self.bear
    if b and self.bearStep == WritPathNav.step then
      local d = (angle - b + math.pi) % (2 * math.pi) - math.pi
      if math.abs(d) > math.pi / 2 then b = angle else b = b + d * math.min(1, dt / 0.25) end
    else b = angle end
    self.bear, self.bearStep, angle = b, WritPathNav.step, b
  end
  local facing = WritPath_Open(GetPlayerFacing)
  if facing and angle then self.tex:SetAlpha(1); self.tex:SetRotation(angle - facing) else self.tex:SetAlpha(0) end
  self.text:SetText(("%s\n(%dyd)"):format(g[4], math.floor(mdist or dist)))
end))
-- the poll lives on the arrow; keep it running while only the window is shown
guide:SetScript("OnUpdate", WritPath_Timed("guide window", function(_, e) if not arrow:IsShown() then poll = poll + e; if poll > 0.5 then poll = 0; Refresh(true) end end end))
-- with the window closed, the guide still keeps track of where you are on the route (once a second), so the road
-- recorder always judges your riding against the right stop
local behind, bgPoll = CreateFrame("Frame"), 0
behind:SetScript("OnUpdate", WritPath_Timed("guide (closed)", function(_, e)
  bgPoll = bgPoll + e
  if bgPoll < 1 then return end
  bgPoll = 0
  if not guide:IsVisible() and #ROUTE > 0 then Refresh() end   -- closed, or the whole UI hidden (Alt+Z)
end))

---------------------------------------------------------------- show/hide, events, slash
local function Show(on)
  WritPathNav.shown = on
  if on then guide:Show(); arrow:Show(); Refresh() else guide:Hide(); arrow:Hide() end
end
close:SetScript("OnClick", function() Show(false) end)

-- the planner hands over a new route here; progress starts fresh
function WritPath_SetRoute(route, titleText, doneText)
  WritPathNav.route, WritPathNav.title, WritPathNav.doneText, WritPathNav.doneRep = route, titleText, doneText, nil
  WritPathNav.pinRoute = nil   -- a map pin's route says so itself, after this (Planner.lua)
  ROUTE = route or {}
  WritPathNav.manual, lastStep = {}, nil
  if not route then WritPathNav.skipWrit, WritPathNav.skipFp = nil, nil end   -- cleared: skips go with the route
  Show(true)
end
function WritPath_CurrentRoute() return ROUTE end
-- a writ route with steps still to do (a finished one doesn't count)
function WritPath_RouteActive() return #ROUTE > 0 and (WritPathNav.step or 1) <= #ROUTE end
-- where the guide is taking you now ({ map, x, y } or nil) and since when
function WritPath_RouteTarget()
  local s = ROUTE[WritPathNav.step or 1]
  return s and s.at, WritPathNav.stepSince or 0, WritPathNav.step or 1   -- the step's end, not a road's next bend
end
function WritPath_Refresh() if WritPathNav then Refresh() end end

local mini = CreateFrame("Button", "WritPathMinimapButton", Minimap)
mini:SetSize(31, 31); mini:SetFrameStrata("MEDIUM"); mini:SetFrameLevel(8)
mini:RegisterForClicks("LeftButtonUp", "RightButtonUp"); mini:RegisterForDrag("LeftButton")
-- WritPath's own badge (it has its own ring, so no extra border)
local miniIcon = mini:CreateTexture(nil, "ARTWORK"); miniIcon:SetAllPoints(); miniIcon:SetTexture(TEX.icon)
local miniGlow = mini:CreateTexture(nil, "HIGHLIGHT"); miniGlow:SetAllPoints(); miniGlow:SetTexture(TEX.icon)
miniGlow:SetBlendMode("ADD"); miniGlow:SetAlpha(0.35)
-- on the minimap's outer edge like other addons' buttons, following its shape (round, square, ...): the same
-- placement LibDBIcon uses
local SHAPES = {
  ["ROUND"] = { true, true, true, true }, ["SQUARE"] = { false, false, false, false },
  ["CORNER-TOPLEFT"] = { false, false, false, true }, ["CORNER-TOPRIGHT"] = { false, false, true, false },
  ["CORNER-BOTTOMLEFT"] = { false, true, false, false }, ["CORNER-BOTTOMRIGHT"] = { true, false, false, false },
  ["SIDE-LEFT"] = { false, true, false, true }, ["SIDE-RIGHT"] = { true, false, true, false },
  ["SIDE-TOP"] = { false, false, true, true }, ["SIDE-BOTTOM"] = { true, true, false, false },
  ["TRICORNER-TOPLEFT"] = { false, true, true, true }, ["TRICORNER-TOPRIGHT"] = { true, false, true, true },
  ["TRICORNER-BOTTOMLEFT"] = { true, true, false, true }, ["TRICORNER-BOTTOMRIGHT"] = { true, true, true, false },
}
local function PlaceMini()
  if not (Minimap and Minimap.GetWidth) then return end
  local a = math.rad(WritPathNav and WritPathNav.miniAngle or 200)
  local x, y, q = math.cos(a), math.sin(a), 1
  if x < 0 then q = q + 1 end
  if y > 0 then q = q + 2 end
  local shape = GetMinimapShape and GetMinimapShape() or "ROUND"
  local quad = SHAPES[shape] or SHAPES.ROUND
  local w, h = (Minimap:GetWidth() or 140) / 2 + 10, (Minimap:GetHeight() or 140) / 2 + 10
  if quad[q] then
    x, y = x * w, y * h
  else   -- a square corner: slide along the edge
    local dw, dh = math.sqrt(2 * w ^ 2) - 10, math.sqrt(2 * h ^ 2) - 10
    x = math.max(-w, math.min(x * dw, w)); y = math.max(-h, math.min(y * dh, h))
  end
  mini:ClearAllPoints(); mini:SetPoint("CENTER", Minimap, "CENTER", x, y)
end
mini:SetScript("OnDragStart", function(self)
  self:SetScript("OnUpdate", function()
    local mx, my = Minimap:GetCenter(); local cx, cy = GetCursorPosition(); local sc = Minimap:GetEffectiveScale()
    WritPathNav.miniAngle = math.deg(math.atan2(cy / sc - my, cx / sc - mx)); PlaceMini()
  end)
end)
mini:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
mini:SetScript("OnClick", function(_, button)
  if button == "RightButton" then WritPath_TogglePlanner()
  elseif IsShiftKeyDown and IsShiftKeyDown() then WritPath_CopyDiscord()
  else Show(not guide:IsShown()) end
end)
mini:SetScript("OnEnter", function(self)
  GameTooltip:SetOwner(self, "ANCHOR_LEFT"); GameTooltip:SetText("WritPath")
  GameTooltip:AddLine("Left-click: show or hide the guide", 1, 1, 1)
  GameTooltip:AddLine("Right-click: writ planner", 1, 1, 1)
  GameTooltip:AddLine("Shift-click: the WritPath Discord's link", 1, 1, 1)
  GameTooltip:AddLine("Drag: move this button", 0.7, 0.7, 0.7)
  GameTooltip:Show()
end)
mini:SetScript("OnLeave", function() GameTooltip:Hide() end)

-- The flight map rings the guide's next stop. Auto-fly (the planner's "Auto-fly" box, WritPathNav.autoFly; also /writs autofly): opening the flight map takes
-- the flight the guide shows, but only on that very step: the current step is "fly from A to B", the flight map is
-- A's (the node marked as where you are), and B is on it and reachable. Anything else, or holding Shift as you
-- talk to the flight master, leaves the map to you.
local function TaxiNames(id)   -- the names a flight point goes by on the flight map
  local n = {}
  local d = WritPath_Data and WritPath_Data.flightNodes and WritPath_Data.flightNodes[id]
  if d and d[5] then n[d[5]:lower()] = true end
  local f = WritPathLearned and WritPathLearned.fp and WritPathLearned.fp[id]
  if type(f) == "table" and f.name then n[f.name:lower()] = true end
  return n
end
local function TaxiSlots()   -- every node on the open flight map: { slot, id, name, here, reach }
  local list = {}
  local m = GetTaxiMapID and GetTaxiMapID()
  if m and C_TaxiMap and C_TaxiMap.GetAllTaxiNodes then
    local ok, nodes = pcall(C_TaxiMap.GetAllTaxiNodes, m)
    local S = Enum and Enum.FlightPathState or { Current = 0, Reachable = 1, Unreachable = 2 }
    for _, n in ipairs(ok and nodes or {}) do
      if n.slotIndex then
        list[#list + 1] = { slot = n.slotIndex, id = n.nodeID, name = n.name and n.name:lower(),
                            here = n.state == S.Current, reach = n.state == S.Reachable }
      end
    end
  end
  if #list == 0 and NumTaxiNodes and TaxiNodeName and TaxiNodeGetType then
    for i = 1, NumTaxiNodes() or 0 do
      local name, kind = TaxiNodeName(i), TaxiNodeGetType(i)
      list[#list + 1] = { slot = i, name = name and name:lower(), here = kind == "CURRENT", reach = kind == "REACHABLE" }
    end
  end
  return list
end
local function Is(node, id, name)
  if node.id and id then return node.id == id end
  if not node.name then return false end
  if name and node.name == name:lower() then return true end
  return id and TaxiNames(id)[node.name] or false
end
-- the flight the step wants, on the open flight map: its node, or nil when this isn't the step's flight master
local function StepFlight(s)
  if not (WritPathNav and s) then return end
  if ROUTE[WritPathNav.step] ~= s or (WritPathNav.manual or {})[WritPathNav.step] then return end   -- the guide moved on
  if not (s.done and s.done.taxi and s.flyTo) then return end
  if WritPath_Open(UnitOnTaxi, "player") then return end
  local here, to
  for _, n in ipairs(TaxiSlots()) do
    if n.here then here = n end
    if n.reach and Is(n, s.flyTo, s.flyToName) then to = n end
  end
  -- the flight master this step sends you to, and no other
  if not (here and s.fpid and Is(here, s.fpid, s.at and s.at[4])) then return end
  return to
end
-- a green ring around the step's next stop on the flight map (its node's button, else where the map puts it)
local ring
local function Ring(slot)
  local map = TaxiFrame
  if ring then ring:Hide() end
  if not (slot and map) then return end
  if not ring then
    ring = CreateFrame("Frame", nil, map); ring:SetSize(30, 30)
    local t = ring:CreateTexture(nil, "OVERLAY"); t:SetAllPoints(); t:SetTexture("Interface/AddOns/WritPath/Media/ring")
    ring.tex = t
  end
  ring:SetParent(map); ring:SetFrameStrata("DIALOG"); ring:ClearAllPoints()
  local btn = _G["TaxiButton" .. slot]
  if btn and btn.IsShown and btn:IsShown() then
    ring:SetPoint("CENTER", btn, "CENTER", 0, 0)
  else
    local area = TaxiRouteMap or TaxiMap or map
    local x, y; if TaxiNodePosition then x, y = TaxiNodePosition(slot) end
    if not (area and x and y) then return end
    ring:SetPoint("CENTER", area, "TOPLEFT", x * area:GetWidth(), -y * area:GetHeight())
  end
  ring:Show()
end
WritPath_FlightRing = function() return ring end   -- for tests
function WritPath_AutoFly(s)
  local to = StepFlight(s)
  Ring(to and to.slot)
  if not (to and WritPathNav.autoFly) or (IsShiftKeyDown and IsShiftKeyDown()) then return end
  local name = TaxiNodeName and TaxiNodeName(to.slot) or s.flyToName or "the next stop"
  Print("Auto-fly: flying to |cFF00FF25" .. name .. "|r (hold Shift as you talk to the flight master to choose yourself)")
  TakeTaxiNode(to.slot)
end
function WritPath_SetAutoFly(on)
  WritPathNav = WritPathNav or {}
  WritPathNav.autoFly = on and true or nil
  if WritPath_AutoFlyCheck then WritPath_AutoFlyCheck:SetChecked(on and true or false) end
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:RegisterEvent("QUEST_TURNED_IN")
ev:RegisterEvent("TAXIMAP_OPENED")
ev:RegisterEvent("UI_INFO_MESSAGE")
ev:RegisterEvent("CHAT_MSG_SYSTEM")
-- the game's "New flight path discovered!" (learning one doesn't open the flight map)
local NEW_FP = ERR_NEWTAXIPATH or "New flight path discovered!"
local function LearnedFlightPath(...)
  for i = 1, select("#", ...) do
    local a = WritPath_Text((select(i, ...)))
    if a and (a == NEW_FP or a:find(NEW_FP, 1, true)) then return true end
  end
end
ev:SetScript("OnEvent", WritPath_Timed("guide events", function(_, event, ...)
  if event == "UI_INFO_MESSAGE" or event == "CHAT_MSG_SYSTEM" then
    if not (WritPathNav and LearnedFlightPath(...)) then return end
    -- the flight path you were sent to learn (or the one you're standing at): it's yours now
    local T = WritPath_Travel
    local function Own(id) if id and T and T.MarkKnown then T.MarkKnown(id, nil, "discovered") end end
    -- the flight master you're standing at
    Own(T and T.NearestNode and T.NearestNode(T.PlayerPoint(), 100))
    local s = ROUTE[WritPathNav.step]
    if s and s.fpid then Own(s.fpid) end   -- the flight path this step learns ("learn it, then fly" waits for the flight)
    if s and s.done and s.done.taxiMap then WritPathNav.manual[WritPathNav.step] = true end
    Refresh(true)
    -- a new flight path can change the best way everywhere: plan the rest of the trip again from here
    if WritPath_RerouteNow then C_Timer.After(0.5, function() WritPath_RerouteNow("new flight path") end) end
    return
  end
  if event == "TAXIMAP_OPENED" then   -- talking to a flight master completes a "learn the flight path" step
    local s = WritPathNav and ROUTE[WritPathNav.step]
    if s and s.done.taxiMap then WritPathNav.manual[WritPathNav.step] = true; Refresh(true) end
    C_Timer.After(0.2, function() WritPath_AutoFly(s) end)   -- the ring (or none), and auto-fly
    return
  end
  if event == "PLAYER_LOGIN" then
    WritPathNav = WritPathNav or {}
    WritPathNav.manual = WritPathNav.manual or {}
    if WritPathNav.shown == nil then WritPathNav.shown = true end
    ROUTE = WritPathNav.route or {}
    local p = WritPathNav.guidePos; if p then guide:ClearAllPoints(); guide:SetPoint(p[1], UIParent, p[2], p[3], p[4]) end
    p = WritPathNav.arrowPos; if p then arrow:ClearAllPoints(); arrow:SetPoint(p[1], UIParent, p[2], p[3], p[4]) end
    Show(WritPathNav.shown)
    PlaceMini()
  elseif WritPathNav then
    C_Timer.After(0.5, function() Refresh(true) end)
  end
end))

SLASH_WRITPATH1 = "/writs"
SlashCmdList.WRITPATH = function(msg)
  msg = (msg or ""):lower():match("^%s*(.-)%s*$")
  local cur = WritPathNav.step or 1
  if msg == "help" or msg == "?" then
    Print(("Version |cFF00FF25%s|r. Commands (the buttons on the guide window and the minimap button do the rest):"):format(WritPath_VERSION or "?"))
    Print("  |cFFFFD100/writs|r  show or hide the guide")
    Print("  |cFFFFD100/writs plan|r  open the planner (writs for a rep target, or Merchant's Favor)")
    Print("  |cFFFFD100/writs runs|r  your last runs: the planner's time estimate against your real time")
    Print("  |cFFFFD100/writs pins|r  turn off (or back on) a map pin you drop becoming a route the arrow leads you on"
      .. (WritPathNav.noPins and " |cFFAAAAAA(off now)|r" or ""))
    Print("  |cFFFFD100/writs accept|r  turn off (or back on) accepting writs, handing them in, and handing in Sealed crates")
    Print("  |cFFFFD100/writs autofly|r  turn on (or off) flying to the next stop when you talk to the guide's flight master"
      .. (WritPathNav.autoFly and " |cFFAAAAAA(on now)|r" or ""))
    Print("  |cFFFFD100/writs travel|r  which flight paths, roads and ships WritPath knows (for a route that walks everywhere)")
    Print("  |cFFFFD100/writs leg|r  why the way to the next customer looks the way it does (to report a bad route)")
    Print("  |cFFFFD100/writs discord|r  the WritPath Discord's invite link, selected so Ctrl+C copies it (help and news)")
    Print("  |cFFFFD100/writs share|r  turn off (or back on) sharing the roads and spots you learn (anonymously, player to player)"
      .. (WritPathNav.noShare and " |cFFAAAAAA(off now)|r" or ""))
    Print("  |cFFFFD100/writs hearth|r  turn off (or back on) using your Hearthstone in plans, for this character"
      .. ((WritPathChar and WritPathChar.noHearth) and " |cFFAAAAAA(off now)|r" or ""))
  elseif msg == "pins" then
    WritPathNav.noPins = not WritPathNav.noPins or nil
    Print(WritPathNav.noPins and "Map pins no longer become routes."
      or "A map pin you drop becomes a route, and the arrow leads you there (not while a writ route is in progress).")
  elseif msg == "runs" then WritPath_RunReport()
  elseif msg == "hearth" then
    local on = WritPathChar and WritPathChar.noHearth   -- off now: turn it on
    if WritPath_SetHearth then WritPath_SetHearth(on and true or false) end
    Print(on and "Plans may use your Hearthstone again where it saves time."
      or "Plans no longer use your Hearthstone (Astral Recall and teleport spells still count).")
  elseif msg == "autofly" then
    WritPath_SetAutoFly(not WritPathNav.autoFly)
    Print(WritPathNav.autoFly and "Auto-fly on: at the flight master the guide sends you to, you take off for its next stop (hold Shift to choose yourself)."
      or "Auto-fly off: you choose your flights.")
  elseif msg == "discord" then WritPath_CopyDiscord()
  elseif msg == "share" then
    WritPathNav.noShare = not WritPathNav.noShare or nil
    Print(WritPathNav.noShare and "No longer sharing what you learn, or passing on what others learned."
      or "Sharing what you learn (roads, paths, boats, flight times, customer spots) anonymously, player to player.")
  elseif msg == "plan" then WritPath_OpenPlanner()
  elseif msg == "accept" then
    WritPathNav.noAutoAccept = not WritPathNav.noAutoAccept or nil
    Print(WritPathNav.noAutoAccept and "Writs are no longer accepted or handed in for you."
      or "Writs are accepted for you when you open them, and handed in when you talk to their customer.")
  elseif msg == "leg" then
    -- why the way to the next customer looks the way it does; also saved for a /reload so it can be read later
    local T = WritPath_Travel
    local target
    for i = cur, #ROUTE do local s = ROUTE[i]; if s.done and s.done.quests and s.at then target = s; break end end
    if not (T and target) then Print("No customer ahead on the route."); return end
    local a, b = T.PlayerPoint(), T.Point(target.at[1], target.at[2], target.at[3])
    local lines = T.Explain(a, b)
    table.insert(lines, 1, "leg to " .. tostring(target.at[4]) .. ", step " .. cur .. " of " .. #ROUTE .. ": " .. ((ROUTE[cur] and ROUTE[cur].lines[1]) or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
    for _, l in ipairs(lines) do Print(l) end
    WritPathLearned.debugLeg = { t = time(), lines = lines }
    Print("Saved. /reload and it can be read from WritPath's saved data.")
  elseif msg == "travel" then
    for _, l in ipairs(WritPath_Travel and WritPath_Travel.Report and WritPath_Travel.Report() or {}) do Print(l) end
  elseif msg == "" then Show(not guide:IsShown())
  else Print(("Unknown command \"%s\": /writs help lists them."):format(msg)) end
end
