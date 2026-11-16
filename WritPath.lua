-- WritPath: finds the map pin for every Craftsman's Writ quest in the log.
-- /writs prints them and saves them to WritPathDB (written to disk on /reload).

local function Print(msg) DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99WritPath|r " .. msg) end

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

WritPath_Scan = Run   -- /writs scan (Nav.lua owns the slash command)

---------------------------------------------------------------- a newer WritPath is out
-- WritPath users tell each other which version they have: hidden addon messages to your guild, your group and
-- your online friends, at login and when your group changes. Someone with a newer version means there's an
-- update: you're told (once a session, and again at each login until you have it) to run the updater.
local PREFIX = "WritPath"
local GetMeta = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
local MINE = (GetMeta and GetMeta("WritPath", "Version")) or "0"
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
  Print(("|cFFFFD100WritPath %s is out (you have %s). Double-click \"Update WritPath\" on your desktop, then /reload.|r"):format(v, MINE))
  Print("|cFFAAAAAANo shortcut yet? Run \"Setup Updater.bat\" in Interface/AddOns/WritPath/tools once.|r")
  if RaidNotice_AddMessage and RaidWarningFrame and ChatTypeInfo and ChatTypeInfo.RAID_WARNING then
    RaidNotice_AddMessage(RaidWarningFrame, "WritPath " .. v .. " is out: run Update WritPath, then /reload", ChatTypeInfo.RAID_WARNING)
  end
  if PlaySound and SOUNDKIT and SOUNDKIT.RAID_WARNING then PlaySound(SOUNDKIT.RAID_WARNING) end
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
