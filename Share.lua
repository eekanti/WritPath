-- WritPath: sharing what's learned while travelling with the WritPath author's collector, by way of other players.
--
-- What's shared: road crossings, winding paths, boat and zeppelin trips, flight times, writ customers' spots from
-- hand-ins, the road steps of writ routes (50-yard hexes) and trouble spots on them. Nothing else: no gold, no
-- items, no character names. Each player's records travel under a random id (made once, kept in the saved data).
--
-- The web: every copy asks the WritPath players it can reach (guild, party/raid, instance chat, online friends)
-- every half hour, keeps what they send (checked, capped, expiring) and passes it on when asked, so the author's
-- collector hears from friends of friends of friends, not only the players it can reach itself.
--   "R"   the collector asks: answered in full (up to 100 messages); confirmed records aren't sent to it again
--   "RR"  another player asks: answered smaller and less often (see the limits below)
--   "X:<id>:rec;rec" the records of one contributor; "E:<count>" ends an answer; "A:<n>" confirms it
-- /writs share turns all of this off (and back on).

local PREFIX = "WritPathData"
local MAXLEN = 240               -- one message carries several records, under the 255-character limit

local function Round(v) return math.floor((v or 0) * 10 + 0.5) / 10 end
local function Clean(s) return (tostring(s or ""):gsub("[|,;:\r\n]", " ")) end   -- characters that would break a record

-- every record this player learned themselves, as short text ("C,1448,1440,54.8,92.9")
local function Records()
  local L, out = WritPathLearned or {}, {}
  for _, c in ipairs(L.crossings or {}) do
    if not c.src then out[#out + 1] = ("C,%d,%d,%s,%s,%d"):format(c.from, c.to, Round(c.x), Round(c.y), c.n or 1) end
  end
  for _, p in ipairs(L.paths or {}) do
    local via = {}
    for _, v in ipairs(p.via or {}) do via[#via + 1] = Round(v[1]) .. " " .. Round(v[2]) end
    out[#out + 1] = ("P,%d,%d,%s,%s,%d,%s"):format(p.from, p.to, Round(p.x), Round(p.y), p.n or 1, table.concat(via, " / "))
  end
  for _, s in ipairs(L.transports or {}) do
    if not s.src then out[#out + 1] = ("S,%d,%s,%s,%d,%s,%s,%d"):format(s.from, Round(s.x), Round(s.y), s.to, Round(s.tx), Round(s.ty), s.n or 1) end
  end
  for a, row in pairs(L.flights or {}) do
    if type(row) == "table" then
      for b, secs in pairs(row) do if type(secs) == "number" then out[#out + 1] = ("F,%d,%d,%d"):format(a, b, secs) end end
    end
  end
  for id, v in pairs(L) do   -- customer spots from hand-ins (writ pins are keyed by item id)
    if type(id) == "number" and type(v) == "table" and v.src == "turnin" and v.map then
      out[#out + 1] = ("N,%d,%d,%s,%s,%s"):format(id, v.map, Round(v.x), Round(v.y), Clean(v.npc))
    end
  end
  -- road steps from the checkpoints (writ routes only): sent when first ridden, again at 3 runs and at 10
  local R = L.roads
  if R and R.edges and R.cells then
    for step, v in pairs(R.edges) do
      local e = type(v) == "number" and { n = v } or v
      local a, b = step:match("^(.-)>(.+)$")
      local A, B = a and R.cells[a], b and R.cells[b]
      if A and B then
        local n = e.n or 0
        local bucket = n >= 10 and 10 or (n >= 3 and 3 or 1)
        local slow = (e.k or 0) > 0 and Round(e.r / e.k) or 0   -- 1.0 open riding, 2.0 twice as slow (0: not measured)
        -- H (hex steps, 1.14.2+; E was 1.14.1's square grid): the hexes' own names (the same for every player)
        -- first, then where this player saw them
        out[#out + 1] = ("H,%s,%s,%d,%s,%d,%s,%s,%d,%s,%s"):format(a, b, bucket, slow, A.m, Round(A.x), Round(A.y), B.m, Round(B.x), Round(B.y))
      end
    end
    -- spots where someone died or swam on a route, or hostile mobs were seen from the road:
    -- Q,hex,deaths,swims,map,x,y,mob lowest,mob highest,flags (s: a "??" mob, e: an elite),died lowest,died highest
    for key, c in pairs(R.cells) do
      if (c.d or 0) > 0 or (c.w or 0) > 0 or c.h or c.s then
        out[#out + 1] = ("Q,%s,%d,%d,%d,%s,%s,%d,%d,%s,%d,%d"):format(key, c.d or 0, c.w or 0, c.m, Round(c.x), Round(c.y),
          c.l or 0, c.h or 0, (c.s and "s" or "") .. (c.e and "e" or "") .. "-", c.dl or 0, c.dh or 0)
      end
    end
  end
  table.sort(out)
  return out
end
WritPath_ShareRecords = Records   -- for tests

-- sending: queued at about 800 characters a second, the pace ChatThrottleLib (used by most addons) keeps to stay
-- clear of the server's flood limits; much slower inside instances, where whispers are throttled.
local CPS = 800
local queue, sending = {}, false
local function Pump()
  local m = table.remove(queue, 1)
  if not m then sending = false; return end
  if C_ChatInfo and C_ChatInfo.SendAddonMessage then pcall(C_ChatInfo.SendAddonMessage, PREFIX, m.text, m.dist or "WHISPER", m.to) end
  local inside = IsInInstance and IsInInstance()
  C_Timer.After(inside and 1.5 or math.max(0.3, (#m.text + #PREFIX) / CPS), Pump)
end
local function Queue(to, text, dist)
  queue[#queue + 1] = { to = to, text = text, dist = dist }
  if not sending then sending = true; C_Timer.After(0.1, Pump) end
end

---------------------------------------------------------------- limits
local FULL, RELAY_MSGS = 100, 40       -- messages in one answer: to the collector, to another player
local RELAY_EVERY = 900                -- the same player is answered at most once in 15 minutes...
local RELAY_PER, RELAY_WINDOW = 4, 600 -- ...and at most 4 players in 10 minutes
local ASK_EVERY = 1800                 -- asking around: every half hour
local KEEP, KEEP_DAYS = 5000, 21       -- records passed on to you: at most 5000, each for 3 weeks after last heard
local PER_ID, PER_SENDER = 3000, 2000  -- at most 3000 kept from one contributor; 2000 accepted from one player a day

---------------------------------------------------------------- your id
local function MyId()
  WritPathNav = WritPathNav or {}
  if not WritPathNav.shareId then
    local t = {}
    for i = 1, 8 do t[i] = ("%x"):format(math.random(0, 15)) end
    WritPathNav.shareId = table.concat(t)
  end
  return WritPathNav.shareId
end
WritPath_ShareId = MyId

---------------------------------------------------------------- checking a record before it's kept or passed on
local function N(v, lo, hi) v = tonumber(v); return v ~= nil and v >= lo and v <= hi end
local function Map(v) return N(v, 1, 5000) end
local function XY(x, y) return N(x, 0, 100) and N(y, 0, 100) end
local function Hex(k)
  local i, q, r = (k or ""):match("^(%d+):(%-?%d+):(%-?%d+)$")
  if not i then return nil end
  return tonumber(q), tonumber(r)
end
local CHECK = {
  C = function(f) return #f == 6 and Map(f[2]) and Map(f[3]) and XY(f[4], f[5]) and N(f[6], 1, 999) end,
  P = function(f) return (#f == 6 or #f == 7) and Map(f[2]) and Map(f[3]) and XY(f[4], f[5]) and N(f[6], 1, 999)
                     and (f[7] or ""):match("^[%d%. /]*$") ~= nil end,
  S = function(f) return #f == 8 and Map(f[2]) and XY(f[3], f[4]) and Map(f[5]) and XY(f[6], f[7]) and N(f[8], 1, 999) end,
  F = function(f) return #f == 4 and N(f[2], 1, 9999) and N(f[3], 1, 9999) and N(f[4], 5, 3600) end,
  N = function(f) return (#f == 5 or #f == 6) and N(f[2], 1, 999999) and Map(f[3]) and XY(f[4], f[5]) end,
  H = function(f)
    if #f ~= 11 then return false end
    local q1, r1 = Hex(f[2]); local q2, r2 = Hex(f[3])
    if not (q1 and q2) then return false end
    local dq, dr = q2 - q1, r2 - r1
    if (math.abs(dq) + math.abs(dr) + math.abs(dq + dr)) / 2 > 8 then return false end   -- one step, not a jump
    return (f[4] == "1" or f[4] == "3" or f[4] == "10") and N(f[5], 0, 5) and Map(f[6]) and XY(f[7], f[8])
       and Map(f[9]) and XY(f[10], f[11])
  end,
  Q = function(f)
    return #f == 12 and Hex(f[2]) ~= nil and N(f[3], 0, 99) and N(f[4], 0, 99) and Map(f[5]) and XY(f[6], f[7])
       and N(f[8], 0, 63) and N(f[9], 0, 63) and (f[10] or ""):match("^[se%-]+$") ~= nil and N(f[11], 0, 63) and N(f[12], 0, 63)
  end,
}
local function Valid(rec)
  if type(rec) ~= "string" or #rec > 200 or rec:find("[|;]") then return false end
  local f = {}
  for part in (rec .. ","):gmatch("([^,]*),") do f[#f + 1] = part end
  local c = CHECK[f[1]]
  return (c and c(f)) and true or false
end
WritPath_ShareValid = Valid   -- for tests

---------------------------------------------------------------- what others passed on to you
local function Relay()
  WritPathLearned = WritPathLearned or {}
  local R = WritPathLearned.relay
  if not R then R = { recs = {}, n = 0, perId = {} }; WritPathLearned.relay = R end
  R.perId = R.perId or {}
  return R
end
local function Prune(R)
  local cut = time() - KEEP_DAYS * 86400
  local n, list, per = 0, {}, {}
  for rec, e in pairs(R.recs) do
    for id, t in pairs(e.by) do if t < cut then e.by[id] = nil end end
    if next(e.by) == nil then R.recs[rec] = nil else n = n + 1; list[#list + 1] = { rec, e.last or e.t or 0 } end
  end
  if n > KEEP then   -- too many: drop the ones heard longest ago
    table.sort(list, function(a, b) return a[2] < b[2] end)
    for i = 1, n - KEEP do R.recs[list[i][1]] = nil end
    n = KEEP
  end
  for _, e in pairs(R.recs) do for id in pairs(e.by) do per[id] = (per[id] or 0) + 1 end end
  R.n, R.perId = n, per
end
WritPath_SharePrune = function() Prune(Relay()) end   -- for tests
local fromToday = {}   -- [sender] = { day, n }: records accepted from each player today
local function Keep(sender, id, rec)
  if id == MyId() or not id:match("^%x%x%x%x%x%x%x%x$") or not Valid(rec) then return false end
  local day = date and date("%Y%m%d") or "0"
  local s = fromToday[sender]
  if not s or s.day ~= day then s = { day = day, n = 0 }; fromToday[sender] = s end
  if s.n >= PER_SENDER then return false end
  local R = Relay()
  local e = R.recs[rec]
  if not (e and e.by[id]) and (R.perId[id] or 0) >= PER_ID then return false end
  if not e then
    if (R.n or 0) >= KEEP then Prune(R); if R.n >= KEEP then return false end end
    e = { t = time(), by = {} }; R.recs[rec] = e; R.n = (R.n or 0) + 1
  end
  if not e.by[id] then R.perId[id] = (R.perId[id] or 0) + 1 end
  e.by[id], e.last = time(), time()
  s.n = s.n + 1
  return true
end

---------------------------------------------------------------- answering
-- what's waiting for confirmation, per asker
local pending, pendingAt, relayAt, relayRecent = {}, {}, {}, {}
local function Answer(to, full)
  if WritPathNav and WritPathNav.noShare then return end
  local now = GetTime()
  if pending[to] and now - (pendingAt[to] or 0) < 120 then return end   -- an answer is already on its way
  if not full then
    if relayAt[to] and now - relayAt[to] < RELAY_EVERY then return end
    local recent = 0
    for i = #relayRecent, 1, -1 do if now - relayRecent[i] < RELAY_WINDOW then recent = recent + 1 else table.remove(relayRecent, i) end end
    if recent >= RELAY_PER then return end
  end
  WritPathNav.sharedTo = WritPathNav.sharedTo or {}
  local done = WritPathNav.sharedTo[to] or {}
  -- your own records first, then what others passed on (most recently heard first), grouped by contributor
  local me, items = MyId(), {}
  for _, r in ipairs(Records()) do if not done[me .. r] then items[#items + 1] = { me, r } end end
  local R = WritPathLearned and WritPathLearned.relay
  if R and R.recs then
    local list = {}
    for rec, e in pairs(R.recs) do for id in pairs(e.by) do if not done[id .. rec] then list[#list + 1] = { id, rec, e.last or 0 } end end end
    table.sort(list, function(a, b) if a[3] ~= b[3] then return a[3] > b[3] end; if a[1] ~= b[1] then return a[1] < b[1] end; return a[2] < b[2] end)
    -- grouped by contributor within the order, so one message carries one id
    local byId, ids = {}, {}
    for _, x in ipairs(list) do if not byId[x[1]] then byId[x[1]] = {}; ids[#ids + 1] = x[1] end; table.insert(byId[x[1]], x[2]) end
    for _, id in ipairs(ids) do for _, rec in ipairs(byId[id]) do items[#items + 1] = { id, rec } end end
  end
  if #items == 0 then return end
  local cap = full and FULL or RELAY_MSGS
  local sent, msgs, cur, body = {}, 0, nil, ""
  local function Flush() if body ~= "" then Queue(to, "X:" .. cur .. ":" .. body); msgs = msgs + 1; body = "" end end
  for _, it in ipairs(items) do
    local id, r = it[1], it[2]
    if id ~= cur or #body + #r + 12 > MAXLEN then Flush(); cur = id end
    if msgs >= cap - 1 then break end   -- enough for one answer; the rest goes next time
    body = body == "" and r or (body .. ";" .. r)
    sent[#sent + 1] = id .. r
  end
  Flush()
  if #sent == 0 then return end
  pending[to], pendingAt[to] = sent, now
  if not full then relayAt[to] = now; relayRecent[#relayRecent + 1] = now end
  Queue(to, "E:" .. #sent)
end

---------------------------------------------------------------- asking around
local got = {}   -- [sender] = records received in the current answer
local function Ask()
  if WritPathNav and WritPathNav.noShare then return end
  if IsInGuild and IsInGuild() then Queue(nil, "RR", "GUILD") end
  local instance = LE_PARTY_CATEGORY_INSTANCE
  if instance and IsInGroup and IsInGroup(instance) then Queue(nil, "RR", "INSTANCE_CHAT") end
  local home = LE_PARTY_CATEGORY_HOME
  if IsInRaid and IsInRaid(home) then Queue(nil, "RR", "RAID") elseif IsInGroup and IsInGroup(home) then Queue(nil, "RR", "PARTY") end
  if C_FriendList and C_FriendList.GetNumFriends and C_FriendList.GetFriendInfoByIndex then
    for i = 1, C_FriendList.GetNumFriends() do
      local f = C_FriendList.GetFriendInfoByIndex(i)
      if f and f.connected and f.name then Queue(f.name, "RR") end
    end
  end
end
WritPath_ShareAsk = Ask   -- for tests

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:RegisterEvent("CHAT_MSG_ADDON")
ev:SetScript("OnEvent", function(_, event, prefix, msg, _, sender)
  if event == "PLAYER_LOGIN" then
    if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then C_ChatInfo.RegisterAddonMessagePrefix(PREFIX) end
    -- the random id's seed. The game's math.random is already seeded randomly and it has no math.randomseed (calling
    -- it errored here and stopped everything below: no asking around). Outside the game (the tests), seed with the
    -- clock plus a hash of this character's name and realm, so two players logging in at once get different ids.
    if math.randomseed then
      local salt = 0
      for c in ((UnitName and UnitName("player") or "") .. (GetRealmName and GetRealmName() or "")):gmatch(".") do salt = (salt * 31 + c:byte()) % 2147483647 end
      math.randomseed(math.floor(((time and time() or 0) + (GetTime and GetTime() or 0) * 1000 + salt) % 2147483647))
    end
    MyId()
    Prune(Relay())
    -- ask around a little after logging in (spread out, so a whole guild logging in doesn't ask at once), then every
    -- half hour
    C_Timer.After(90 + math.random(0, 120), Ask)
    if C_Timer.NewTicker then C_Timer.NewTicker(ASK_EVERY + math.random(0, 300), Ask) end
    return
  end
  if prefix ~= PREFIX or type(msg) ~= "string" or not sender then return end
  local me = UnitName("player")
  local short = Ambiguate and Ambiguate(sender, "none") or sender
  if short == me then return end
  if msg == "R" then
    Answer(sender, true)                              -- the author's collector asks: send what's new
  elseif msg == "RR" then
    Answer(sender, false)                             -- another player asks: a smaller answer, now and then
  elseif msg:sub(1, 2) == "X:" then
    if WritPathNav and WritPathNav.noShare then return end
    local id, body = msg:match("^X:(%x+):(.*)$")      -- records passed on to you: checked, then kept
    if id and body then
      for r in body:gmatch("[^;]+") do if Keep(sender, id, r) then got[sender] = (got[sender] or 0) + 1 end end
    end
  elseif msg:sub(1, 2) == "E:" then
    local n = got[sender] or 0
    got[sender] = nil
    if n > 0 then Queue(sender, "A:" .. n) end        -- confirm, so they don't send those again
  elseif msg:sub(1, 2) == "A:" then
    local list = pending[sender]                      -- they got it all: don't send those again
    if list then
      WritPathNav.sharedTo = WritPathNav.sharedTo or {}
      local done = WritPathNav.sharedTo[sender] or {}
      for _, r in ipairs(list) do done[r] = true end
      WritPathNav.sharedTo[sender] = done
      pending[sender] = nil
    end
  end
end)
