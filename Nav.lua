-- WritPath guide: a step window and a navigation arrow.
-- Steps complete by themselves (writ handed in, flight taken, zone reached); the
-- checkbox on a step completes it by hand. Styled through EllesmereUI's skinning API when it's
-- installed; otherwise a plain flat dark look. The arrow is WritPath's own (Media/arrow.tga).
-- /writs  show or hide     /writs next | back | reset     /writs plan  open the planner
-- /writs clear  drop the planned route

local ROUTE = {}   -- the planned route (WritPathNav.route); empty until you start one from the planner
local function Print(msg) DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99WritPath|r " .. msg) end

local TEX = {
  arrow   = "Interface/AddOns/WritPath/Media/arrow",
  flat    = "Interface/BUTTONS/WHITE8X8",
  icon    = "Interface/AddOns/WritPath/Media/icon",
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
local function Count(id)
  if C_Item and C_Item.GetItemCount then return C_Item.GetItemCount(id) or 0 end
  return GetItemCount and GetItemCount(id) or 0
end

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
  if d.taxi and UnitOnTaxi("player") then hit = true end
  if d.arrive and InZone(ArriveZones(s)) then hit = true end
  -- a waypoint on the way (a road crossing) is done once you're close to it; a flight master only once you've
  -- taken the flight (or landed), a boat or zeppelin once you land, a writ customer only when you've handed it in
  if not hit and TravelStep(s) and not d.taxi and not d.taxiMap and not d.sail and Near(s) then hit = true end
  if hit then WritPathNav.manual[i] = true end
  return hit
end

local function SetWaypoint(s)
  pcall(function()
    if not (s and s.at) then C_Map.ClearUserWaypoint(); return end
    local g = s.at
    if C_Map.CanSetUserWaypointOnMap and not C_Map.CanSetUserWaypointOnMap(g[1]) then return end
    C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(g[1], g[2] / 100, g[3] / 100))
    if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then C_SuperTrack.SetSuperTrackedUserWaypoint(true) end
  end)
end

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
local function HeadButton(icon, tip, anchor, onClick)
  local b = CreateFrame("Button", nil, header)
  b:SetSize(16, 16); b:SetPoint("RIGHT", anchor, "LEFT", -4, 0)
  b:SetNormalTexture(icon); b:GetNormalTexture():SetTexCoord(0.08, 0.92, 0.08, 0.92)
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
local moneyBtn = HeadButton("Interface/Icons/INV_Misc_Bag_10", { "Writ money", "Every turn-in: what the writ and its item cost and what its pouch paid (in chat)." },
  clearBtn, function() WritPath_MoneyReport() end)
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
    local i = row.index; if not i then return end
    WritPathNav.manual[i] = not WritPathNav.manual[i] or nil
    Refresh(true)
  end)
  rows[r] = row
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
    SetWaypoint(ROUTE[cur])
    if PlaySound and SOUNDKIT and announce then PlaySound(SOUNDKIT.IG_QUEST_LOG_OPEN or 875) end
  end

  local y = -4
  local fp = FlightHint()
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
      row.text:SetText("No route yet. Open the planner with the map or coin icon above (or right-click the minimap button).")
    else
      row.text:SetText(ICONS.rep .. " " .. (WritPathNav.doneText or "All planned writs handed in") .. ". Close with the X.")
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

-- arrow and auto-complete, polled: cheap, and catches taxis and boats without extra events
local tick, poll = 0, 0
arrow:SetScript("OnUpdate", function(self, e)
  tick, poll = tick + e, poll + e
  if poll > 0.5 then poll = 0; Refresh(true) end
  if tick < 0.03 then return end; tick = 0
  local s = ROUTE[WritPathNav.step]; if not s then return end
  local g = s.at
  if not g then self.tex:SetAlpha(0); self.text:SetText(""); return end
  local dist, angle = Vector(g)
  if not dist then
    self.tex:SetAlpha(angle == "continent" and 0.4 or 0); self.tex:SetRotation(0)
    self.text:SetText(g[4] .. "\n" .. (angle == "continent" and "|cFFFF5722other continent|r" or "~"))
    return
  end
  if dist < 10 then
    self.tex:SetAlpha(0); self.text:SetText(g[4] .. "\n|cFF00FF25here|r"); return
  end
  local facing = GetPlayerFacing()
  if facing and angle then self.tex:SetAlpha(1); self.tex:SetRotation(angle - facing) else self.tex:SetAlpha(0) end
  self.text:SetText(("%s\n(%dyd)"):format(g[4], math.floor(dist)))
end)
-- the poll lives on the arrow; keep it running while only the window is shown
guide:SetScript("OnUpdate", function(_, e) if not arrow:IsShown() then poll = poll + e; if poll > 0.5 then poll = 0; Refresh(true) end end end)

---------------------------------------------------------------- show/hide, events, slash
local function Show(on)
  WritPathNav.shown = on
  if on then guide:Show(); arrow:Show(); Refresh() else guide:Hide(); arrow:Hide() end
end
close:SetScript("OnClick", function() Show(false) end)

-- the planner hands over a new route here; progress starts fresh
function WritPath_SetRoute(route, titleText, doneText)
  WritPathNav.route, WritPathNav.title, WritPathNav.doneText = route, titleText, doneText
  ROUTE = route or {}
  WritPathNav.manual, lastStep = {}, nil
  Show(true)
end
function WritPath_CurrentRoute() return ROUTE end
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
  if button == "RightButton" then WritPath_TogglePlanner() else Show(not guide:IsShown()) end
end)
mini:SetScript("OnEnter", function(self)
  GameTooltip:SetOwner(self, "ANCHOR_LEFT"); GameTooltip:SetText("WritPath")
  GameTooltip:AddLine("Left-click: show or hide the guide", 1, 1, 1)
  GameTooltip:AddLine("Right-click: writ planner", 1, 1, 1)
  GameTooltip:AddLine("Drag: move this button", 0.7, 0.7, 0.7)
  GameTooltip:Show()
end)
mini:SetScript("OnLeave", function() GameTooltip:Hide() end)

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
    local a = select(i, ...)
    if type(a) == "string" and (a == NEW_FP or a:find(NEW_FP, 1, true)) then return true end
  end
end
ev:SetScript("OnEvent", function(_, event, ...)
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
end)

SLASH_WRITPATH1 = "/writs"
SlashCmdList.WRITPATH = function(msg)
  msg = (msg or ""):lower():match("^%s*(.-)%s*$")
  local cur = WritPathNav.step or 1
  if msg == "scan" then WritPath_Scan()
  elseif msg == "money" then WritPath_MoneyReport()
  elseif msg == "runs" then WritPath_RunReport()
  elseif msg == "plan" then WritPath_OpenPlanner()
  elseif msg == "mine" then WritPath_OpenPlanner("mine")
  elseif msg == "buy" then WritPath_OpenPlanner("buy")
  elseif msg == "why" then WritPath_WhyNot()
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
  elseif msg == "clear" then
    if WritPath_ClearAll then WritPath_ClearAll() else WritPath_SetRoute(nil); Print("Route cleared.") end
  elseif msg == "next" then WritPathNav.manual[cur] = true; Refresh(true)
  elseif msg == "back" then
    for i = cur - 1, 1, -1 do if WritPathNav.manual[i] then WritPathNav.manual[i] = nil; break end end
    Refresh()
  elseif msg == "reset" then WritPathNav.manual = {}; Refresh()
  else Show(not guide:IsShown()) end
end
