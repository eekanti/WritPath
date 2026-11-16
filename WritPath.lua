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
