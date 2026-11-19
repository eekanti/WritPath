-- WritPath: finds the map pin for every Craftsman's Writ quest in the log.
-- /writs prints them and saves them to WritPathDB (written to disk on /reload).

local function Print(msg) DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99WritPath|r " .. msg) end

-- The game can hand an addon a "secret" value (a speed, a level, a reaction) that may not be compared, added or
-- tested; touching one is an error. WritPath_Open(fn, ...) calls fn and gives back its first result, or nil when
-- that result is secret (or fn is missing), so callers treat it as "not known".
function WritPath_Open(fn, ...)
  if type(fn) ~= "function" then return nil end
  local v = fn(...)
  if issecretvalue and issecretvalue(v) then return nil end
  return v
end

---------------------------------------------------------------- what's in your bags
-- How many of an item are IN your bags: not what you're wearing, and not the bags themselves (a quiver or ammo
-- pouch is a bag in a bag slot, and the game's item count includes it). Read once per bag change, then looked up.
local bagCounts
local function ReadBags()
  local C = C_Container
  local numSlots = (C and C.GetContainerNumSlots) or GetContainerNumSlots
  local itemID = (C and C.GetContainerItemID) or GetContainerItemID
  local info = (C and C.GetContainerItemInfo) or GetContainerItemInfo
  if not (numSlots and itemID and info) then return nil end
  local t = {}
  local last = (NUM_TOTAL_EQUIPPED_BAG_SLOTS or NUM_BAG_SLOTS or 4)
  for bag = 0, last do
    for slot = 1, numSlots(bag) or 0 do
      local id = itemID(bag, slot)
      if id then
        local i = info(bag, slot)
        local n = type(i) == "table" and i.stackCount or select(2, info(bag, slot)) or 1
        t[id] = (t[id] or 0) + (n or 1)
      end
    end
  end
  return t
end
function WritPath_BagCount(id)
  if not id then return 0 end
  if not bagCounts then bagCounts = ReadBags() end
  if bagCounts then return bagCounts[id] or 0 end
  -- no bag API (never on a real client): the game's own count
  if C_Item and C_Item.GetItemCount then return C_Item.GetItemCount(id) or 0 end
  return GetItemCount and GetItemCount(id) or 0
end
local bagWatch = CreateFrame("Frame")
for _, e in ipairs({ "BAG_UPDATE", "BAG_UPDATE_DELAYED", "PLAYER_EQUIPMENT_CHANGED", "PLAYER_ENTERING_WORLD" }) do
  bagWatch:RegisterEvent(e)
end
bagWatch:SetScript("OnEvent", function() bagCounts = nil end)

local function WritQuests()
  local out = {}
  if C_QuestLog and C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetInfo then
    for i = 1, C_QuestLog.GetNumQuestLogEntries() do
      local info = C_QuestLog.GetInfo(i)
      if info and not info.isHeader and info.title and info.title:find("Craftsman's Writ") then
        out[info.questID] = info.title
      end
    end
  elseif GetNumQuestLogEntries then
    for i = 1, GetNumQuestLogEntries() do
      local title, _, _, isHeader, _, _, _, questID = GetQuestLogTitle(i)
      if title and not isHeader and title:find("Craftsman's Writ") then out[questID] = title end
    end
  end
  return out
end

local function MapName(mapID)
  local info = mapID and C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(mapID)
  return info and info.name or ("map " .. tostring(mapID))
end

local function Locate(quests)
  local found = {}
  -- 1) the waypoint API, where the client has it
  if C_QuestLog and C_QuestLog.GetNextWaypoint then
    for qid in pairs(quests) do
      local ok, mapID, x, y = pcall(C_QuestLog.GetNextWaypoint, qid)
      if ok and mapID and x then found[qid] = { mapID = mapID, x = x, y = y, how = "waypoint" } end
    end
  end
  -- 2) scan every zone map for the quest's pin
  if C_QuestLog and C_QuestLog.GetQuestsOnMap then
    for mapID = 1, 5000 do
      local ok, pins = pcall(C_QuestLog.GetQuestsOnMap, mapID)
      if ok and pins then
        for _, p in ipairs(pins) do
          if quests[p.questID] and p.x then
            local info = C_Map.GetMapInfo(mapID)
            WritPathAll = WritPathAll or {}
            WritPathAll[p.questID] = WritPathAll[p.questID] or {}
            table.insert(WritPathAll[p.questID], { mapID = mapID, name = info and info.name,
              mapType = info and info.mapType, parent = info and info.parentMapID,
              x = math.floor(p.x * 1000 + 0.5) / 10, y = math.floor(p.y * 1000 + 0.5) / 10 })
            local isZone = info and Enum and Enum.UIMapType and info.mapType == Enum.UIMapType.Zone
            local cur = found[p.questID]
            if not cur or (isZone and not cur.zone) then
              found[p.questID] = { mapID = mapID, x = p.x, y = p.y, how = "map pin", zone = isZone or nil }
            end
          end
        end
      end
    end
  end
  -- 3) the quest's own map, as a last resort
  if GetQuestUiMapID then
    for qid in pairs(quests) do
      if not found[qid] then
        local ok, mapID = pcall(GetQuestUiMapID, qid)
        if ok and mapID and mapID > 0 then found[qid] = { mapID = mapID, how = "quest map only" } end
      end
    end
  end
  return found
end

local function Run()
  local quests = WritQuests()
  WritPathAll = {}
  local found = Locate(quests)
  WritPathDB = { time = time(), writs = {}, all = WritPathAll }
  local pmap = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
  local ppos = pmap and C_Map.GetPlayerMapPosition and C_Map.GetPlayerMapPosition(pmap, "player")
  WritPathDB.player = { mapID = pmap, zone = MapName(pmap), x = ppos and ppos.x and ppos.x * 100, y = ppos and ppos.y and ppos.y * 100 }
  local n = 0
  for qid, title in pairs(quests) do
    n = n + 1
    local f = found[qid]
    local row = { questID = qid, title = title }
    if f then
      row.mapID, row.zone, row.how = f.mapID, MapName(f.mapID), f.how
      if f.x then row.x, row.y = math.floor(f.x * 1000 + 0.5) / 10, math.floor(f.y * 1000 + 0.5) / 10 end
      Print(("%s: %s %s (%s)"):format((title:gsub("Craftsman's Writ: ", "")), row.zone,
        row.x and ("%.1f, %.1f"):format(row.x, row.y) or "", f.how))
    else
      Print(title .. ": no location found")
    end
    table.insert(WritPathDB.writs, row)
  end
  if n == 0 then Print("No Craftsman's Writ quests in your log. Right-click each writ to accept it first.")
  else Print(n .. " writs. Type /reload so I can read them.") end
end

WritPath_Scan = Run   -- reads the map pins of accepted writs (done by itself as you accept them)

---------------------------------------------------------------- a newer WritPath is out
-- WritPath users tell each other which version they have: hidden addon messages to your guild, your group and
-- your online friends, at login and when your group changes. Someone with a newer version means there's an
-- update: a line in chat says so (once a session, and again at each login until you have it).
local PREFIX = "WritPath"
-- the version, kept here as well as in WritPath.toc: the game reads the .toc only when it starts, so after an
-- update and a /reload the .toc's number is still the old one (the release check makes sure the two match)
WritPath_VERSION = "1.14.13"
local MINE = WritPath_VERSION
local function Parts(v) local t = {}; for n in tostring(v):gmatch("%d+") do t[#t + 1] = tonumber(n) end; return t end
local function Newer(a, b)   -- is version a newer than version b?
  local x, y = Parts(a), Parts(b)
  for i = 1, math.max(#x, #y) do
    local p, q = x[i] or 0, y[i] or 0
    if p ~= q then return p > q end
  end
  return false
end
local told = {}
local function Notice(v)
  if told[v] then return end
  told[v] = true
  -- one quiet line in chat, the way addons usually say it
  Print(("A newer version (%s) is available. You have %s."):format(v, MINE))
end
local function Seen(v)
  if not (v and Newer(v, MINE)) then return end
  WritPathNav = WritPathNav or {}
  if not WritPathNav.latest or Newer(v, WritPathNav.latest) then WritPathNav.latest = v end
  Notice(WritPathNav.latest)
end
local function Send(dist, target)
  if C_ChatInfo and C_ChatInfo.SendAddonMessage then pcall(C_ChatInfo.SendAddonMessage, PREFIX, "V:" .. MINE, dist, target) end
end
local function ToGroup()
  if IsInRaid and IsInRaid() then Send("RAID") elseif IsInGroup and IsInGroup() then Send("PARTY") end
end
local function Announce()
  if IsInGuild and IsInGuild() then Send("GUILD") end
  ToGroup()
  if C_FriendList and C_FriendList.GetNumFriends and C_FriendList.GetFriendInfoByIndex then
    for i = 1, C_FriendList.GetNumFriends() do
      local f = C_FriendList.GetFriendInfoByIndex(i)
      if f and f.connected and f.name then Send("WHISPER", f.name) end
    end
  end
end
local replied, lastGroup = {}, 0
local ver = CreateFrame("Frame")
ver:RegisterEvent("PLAYER_LOGIN")
ver:RegisterEvent("CHAT_MSG_ADDON")
ver:RegisterEvent("GROUP_ROSTER_UPDATE")
ver:SetScript("OnEvent", function(_, event, prefix, msg, _, sender)
  if event == "PLAYER_LOGIN" then
    if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then C_ChatInfo.RegisterAddonMessagePrefix(PREFIX) end
    -- one line at every login and /reload: which version is running
    C_Timer.After(2, function() Print("v" .. MINE .. " |cFFAAAAAA· /writs help|r") end)
    C_Timer.After(15, Announce)
    -- heard about a newer version before and still don't have it
    if WritPathNav and WritPathNav.latest and Newer(WritPathNav.latest, MINE) then
      local v = WritPathNav.latest
      C_Timer.After(8, function() Notice(v) end)
    end
  elseif event == "GROUP_ROSTER_UPDATE" then
    if GetTime() - lastGroup > 60 then lastGroup = GetTime(); C_Timer.After(5, ToGroup) end
  elseif event == "CHAT_MSG_ADDON" and prefix == PREFIX and type(msg) == "string" then
    local v = msg:match("^V:(.+)$")
    if not v then return end
    local who = Ambiguate and Ambiguate(sender or "", "none") or sender
    if who == UnitName("player") then return end
    Seen(v)
    -- they're behind: tell them (once a minute at most per player)
    if Newer(MINE, v) and who and (not replied[who] or GetTime() - replied[who] > 60) then
      replied[who] = GetTime()
      Send("WHISPER", who)
    end
  end
end)
WritPath_Version = { Mine = MINE, Newer = Newer }   -- for tests
