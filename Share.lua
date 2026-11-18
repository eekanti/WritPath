-- WritPath: sharing what you've learned with the WritPath author's collector.
--
-- The author runs a private collector addon. When it asks (over guild, party/raid, instance chat, or a whisper to
-- an in-game friend), this copy whispers back what YOU learned yourself while travelling: road crossings you rode,
-- winding paths, boat and zeppelin trips, flight times, writ customers' spots from your hand-ins, and the road
-- steps of your writ routes (checkpoints about 100 yards apart, with how many runs used them). Nothing else:
-- no gold, no names but the NPCs', nothing from your bags. Each record is sent once; the collector confirms what it
-- got. The author checks the records and ships the good ones to every player in a later version.
-- /writs share turns this off (and back on).

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
        out[#out + 1] = ("E,%d,%s,%s,%d,%s,%s,%d,%s"):format(A.m, Round(A.x), Round(A.y), B.m, Round(B.x), Round(B.y), bucket, slow)
      end
    end
    -- spots where someone died or swam on a route
    for _, c in pairs(R.cells) do
      if (c.d or 0) > 0 or (c.w or 0) > 0 then
        out[#out + 1] = ("K,%d,%s,%s,%d,%d"):format(c.m, Round(c.x), Round(c.y), c.d or 0, c.w or 0)
      end
    end
  end
  table.sort(out)
  return out
end
WritPath_ShareRecords = Records   -- for tests

-- sending: queued, a few messages a second (slower inside instances, where whispers are throttled)
local queue, sending = {}, false
local function Pump()
  local m = table.remove(queue, 1)
  if not m then sending = false; return end
  if C_ChatInfo and C_ChatInfo.SendAddonMessage then pcall(C_ChatInfo.SendAddonMessage, PREFIX, m.text, "WHISPER", m.to) end
  local inside = IsInInstance and IsInInstance()
  C_Timer.After(inside and 1.5 or 0.25, Pump)
end
local function Queue(to, text)
  queue[#queue + 1] = { to = to, text = text }
  if not sending then sending = true; C_Timer.After(0.1, Pump) end
end

-- what's waiting for confirmation, per collector
local pending, pendingAt = {}, {}

local function Answer(to)
  if WritPathNav and WritPathNav.noShare then return end
  if pending[to] and GetTime() - (pendingAt[to] or 0) < 120 then return end   -- an answer is already on its way
  WritPathNav.sharedTo = WritPathNav.sharedTo or {}
  local done = WritPathNav.sharedTo[to] or {}
  local new = {}
  for _, r in ipairs(Records()) do if not done[r] then new[#new + 1] = r end end
  if #new == 0 then return end
  pending[to], pendingAt[to] = new, GetTime()
  local msg = ""
  for _, r in ipairs(new) do
    if #msg + #r + 1 > MAXLEN then Queue(to, "D:" .. msg); msg = "" end
    msg = msg == "" and r or (msg .. ";" .. r)
  end
  if msg ~= "" then Queue(to, "D:" .. msg) end
  Queue(to, "E:" .. #new)
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:RegisterEvent("CHAT_MSG_ADDON")
ev:SetScript("OnEvent", function(_, event, prefix, msg, _, sender)
  if event == "PLAYER_LOGIN" then
    if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then C_ChatInfo.RegisterAddonMessagePrefix(PREFIX) end
    return
  end
  if prefix ~= PREFIX or type(msg) ~= "string" or not sender then return end
  local me = UnitName("player")
  local short = Ambiguate and Ambiguate(sender, "none") or sender
  if short == me then return end
  if msg == "R" then
    Answer(sender)                                    -- the collector asks: send what's new
  elseif msg:match("^A:") then
    local list = pending[sender]                      -- the collector got it all: don't send those again
    if list then
      WritPathNav.sharedTo = WritPathNav.sharedTo or {}
      local done = WritPathNav.sharedTo[sender] or {}
      for _, r in ipairs(list) do done[r] = true end
      WritPathNav.sharedTo[sender] = done
      pending[sender] = nil
    end
  end
end)
