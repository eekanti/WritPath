-- WritPath planner: picks writs by price for a rep target and builds the guide route for them.
--  * customers: WritDB.lua, overridden by map pins learned in game (WritPathLearned)
--  * prices:    Auctionator's last scan, read live (writ + requested items, minus what you already own)
--  * picking:   cheapest gold per rep, plus travel time priced at "time worth" silver per minute;
--               each writ once a day (the game's daily limit is per writ: a customer takes any number of
--               different writs, 2026-11-20)
--  * route:     shortest order through the picked customers, then handed to the guide window
-- /writs plan  opens the planner (a rep target plans what to buy; no target plans just the writs you have)

local DB, CUST = WritPath_Writs, WritPath_Customers
local REP = { Journeyman = 75, Expert = 125, Artisan = 200 }
local POUCH_GUESS = { Journeyman = 1200, Expert = 6700, Artisan = 7456 }   -- copper, until your own log has some
local G, W_, Y = "|cFF00FF25", "|cFFFCDC00", "|cFF00BCD4"
local function Print(msg) DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99WritPath|r " .. msg) end

-- how many you have: in your bags, plus what WritPath bought for you that's still in the mail
local function Count(id)
  if not id then return 0 end
  return WritPath_BagCount(id) + (WritPath_InMail and WritPath_InMail(id) or 0)
end
local function Done(q) return C_QuestLog.IsQuestFlaggedCompleted(q) end
local function InLog(q) return C_QuestLog.GetLogIndexForQuestID and C_QuestLog.GetLogIndexForQuestID(q) ~= nil end
local function ItemName(id)
  if not id then return nil end
  if C_Item and C_Item.GetItemNameByID then local n = C_Item.GetItemNameByID(id); if n then return n end end
  return GetItemInfo and (GetItemInfo(id)) or nil
end
local function MapName(m) local i = m and C_Map.GetMapInfo(m); return i and i.name or "?" end

local function Coins(c)
  c = math.floor((c or 0) + 0.5)
  local neg = c < 0; c = math.abs(c)
  local g, s = math.floor(c / 10000), math.floor(c / 100) % 100
  local t = g > 0 and (g .. "g " .. s .. "s") or (s > 0 and (s .. "s " .. c % 100 .. "c") or (c % 100 .. "c"))
  return (neg and "-" or "") .. t
end
WritPath_Coins = Coins

---------------------------------------------------------------- learning customers from map pins
local zoneMaps
local function ZoneMaps()
  if zoneMaps then return zoneMaps end
  zoneMaps = {}
  local zoneType = Enum and Enum.UIMapType and Enum.UIMapType.Zone or 3
  for m = 1, 5000 do
    local info = C_Map.GetMapInfo(m)
    if info and info.mapType == zoneType then zoneMaps[#zoneMaps + 1] = m end
  end
  return zoneMaps
end

-- a pin shows on every zone map around it, squashed to the edge on the neighbours:
-- keep the one furthest from any edge
-- a spot read on one map, moved onto the zone it really lies in (the game also shows a quest's pin on the
-- neighbouring zones' maps, and near a border that copy can look like the better one)
local function OnOwnZone(map, x, y)
  local Tr = WritPath_Travel
  local ok, z, zx, zy = pcall(function() return Tr.Place(map, x / 100, y / 100) end)
  if ok and z and z ~= map and zx and zx >= 0 and zx <= 100 and zy >= 0 and zy <= 100 then return z, zx, zy end
  return map, x, y
end

-- the writ's map pin, the best data there is. The game draws it on the zone it's in and also on the neighbouring
-- zones' maps. Which copy to read: the one on the map of the zone the customer is known to be in (want); else
-- the one on the zone it really lies in; else the one furthest from a map edge, moved onto its zone. The spot
-- always comes from the pin.
local function FindPin(q, want)
  local best, bestScore, own, ownScore, wanted, wantScore
  for _, m in ipairs(ZoneMaps()) do
    local ok, pins = pcall(C_QuestLog.GetQuestsOnMap, m)
    if ok and pins then
      for _, p in ipairs(pins) do
        if p.questID == q and p.x then
          local s = math.min(p.x, 1 - p.x, p.y, 1 - p.y)
          local pin = { map = m, x = math.floor(p.x * 1000 + 0.5) / 10, y = math.floor(p.y * 1000 + 0.5) / 10 }
          if not bestScore or s > bestScore then best, bestScore = pin, s end
          if OnOwnZone(pin.map, pin.x, pin.y) == m and (not ownScore or s > ownScore) then own, ownScore = pin, s end
          if want and m == want and (not wantScore or s > wantScore) then wanted, wantScore = pin, s end
        end
      end
    end
  end
  own = wanted or own
  local pin = own or best
  if pin and not own then pin.map, pin.x, pin.y = OnOwnZone(pin.map, pin.x, pin.y) end
  if pin then pin.checked = true end
  return pin
end

local Customer   -- defined below

local learnTries = 0
local Learn
local function Learned()   -- something new: an open planner shows it straight away
  if WritPath_PlannerLearned then WritPath_PlannerLearned() end
end

function Learn()
  local missing, found = false, false
  for id, w in pairs(DB) do
    local old = WritPathLearned[id]
    -- not read yet, or read before WritPath knew which copy is the real one: read it (again) from the quest log
    local stale = type(old) == "table" and old.src ~= "turnin" and not old.checked
    if (not old or stale) and InLog(w.q) then
      local base = w.c and CUST[w.c]
      local pin = FindPin(w.q, base and base.map)
      if not pin then missing = true end
      if pin then
        found = true
        pin.t = time(); WritPathLearned[id] = pin
        Print(("Learned where %s goes: %s %.1f, %.1f"):format(w.name, MapName(pin.map), pin.x, pin.y))
        -- a planned route waiting on this spot gets the exact point now
        for _, s in ipairs(WritPathNav and WritPathNav.route or {}) do
          if s.writ == id then
            local c = Customer(id)
            s.at = { pin.map, pin.x, pin.y, c and c.npc or w.name }
            for i = #s.lines, 1, -1 do if s.lines[i]:find("Exact spot unknown") then table.remove(s.lines, i) end end
          end
        end
        if WritPath_Refresh then WritPath_Refresh() end
      end
    end
  end
  if found then Learned() end
  -- a pin that isn't on the map yet: look again every 5 seconds, for up to a minute
  if missing and learnTries < 12 then learnTries = learnTries + 1; C_Timer.After(5, Learn) end
  if not missing then learnTries = 0 end
end

-- At a turn-in you're standing next to the customer and the game knows their name: the best data there is.
-- It's saved for the writ and for its customer, so every writ that customer takes gets the exact spot.
local turnin
local function NoteTurnin()
  local name = UnitName("npc") or UnitName("target")
  local here = WritPath_Travel.PlayerPoint()
  if name and here then turnin = { npc = name, map = here.map, x = here.x, y = here.y, at = GetTime() } end
end
local function LearnTurnin(q)
  if not (turnin and GetTime() - turnin.at < 120) then return end
  for id, w in pairs(DB) do
    if w.q == q then
      local old = WritPathLearned[id]
      local spot = { map = turnin.map, x = math.floor(turnin.x * 10 + 0.5) / 10, y = math.floor(turnin.y * 10 + 0.5) / 10,
                     npc = turnin.npc, src = "turnin", t = time() }
      WritPathLearned[id] = spot
      WritPathLearned.npcs = WritPathLearned.npcs or {}
      local key = w.c or ("npc:" .. turnin.npc)
      local known = WritPathLearned.npcs[key]
      -- a writ handed to its own NPC (w.who), standing next to another customer: that NPC's
      -- name and spot stay with this writ, not with every writ of the customer
      if not w.who then
        WritPathLearned.npcs[key] = { map = spot.map, x = spot.x, y = spot.y, npc = turnin.npc, t = spot.t }
      else known = true end
      local base = w.c and CUST[w.c]
      if not known and not (base and base.x and base.npc == turnin.npc) then
        Print(("Learned %s's spot for %s: %s %.1f, %.1f."):format(turnin.npc, w.name, MapName(spot.map), spot.x, spot.y))
        Learned()
      end
      return
    end
  end
end

-- where a writ is turned in: your learned pin first, then the database; nil when nobody knows yet.
-- key identifies the customer (their writs share one stop)
function Customer(id)
  local w = DB[id]; if not w then return nil end
  local base = w.c and CUST[w.c]
  local LW = WritPathLearned or {}
  local L = LW[id]
  if type(L) == "table" and L.map and L.src ~= "turnin" then
    -- a pin saved before WritPath knew which copy is the real one, for a writ no longer in your log (so it can't
    -- be read again): moved onto the zone it lies in
    if not L.checked and L.x and not InLog(w.q) then L.map, L.x, L.y = OnOwnZone(L.map, L.x, L.y); L.checked = true end
  end
  if type(L) == "table" and L.map then
    local key = w.c or (L.npc and ("npc:" .. L.npc))
    if not key then   -- no name known: learned pins on the same spot are the same customer
      local low = id
      for oid, o in pairs(LW) do   -- writ pins only (numeric keys); the rest is travel data
        if type(oid) == "number" and type(o) == "table" and o.map == L.map and o.x and math.abs(o.x - L.x) < 0.8
           and math.abs(o.y - L.y) < 0.8 and oid < low then low = oid end
      end
      key = (DB[low] and DB[low].c) or ("pin" .. low)
    end
    return { key = key, npc = L.npc or (w.who and w.who.npc) or (base and base.npc), map = L.map, x = L.x, y = L.y, exact = true }
  end
  -- a writ that goes to its own NPC, standing right next to another customer (one stop for both)
  if w.who then return { key = w.c, npc = w.who.npc, map = w.who.map, x = w.who.x, y = w.who.y, exact = true } end
  -- this customer's spot learned at another writ's turn-in
  local N = w.c and LW.npcs and LW.npcs[w.c]
  if N then
    local npc = N.npc or (base and base.npc)
    -- an older turn-in may have saved a writ's own NPC (w.who) as the customer's name: the customer keeps theirs
    if base and base.npc and npc ~= base.npc then
      for _, o in pairs(DB) do if o.c == w.c and o.who and o.who.npc == npc then npc = base.npc; break end end
    end
    return { key = w.c, npc = npc, map = N.map, x = N.x, y = N.y, exact = true }
  end
  if not (base and base.map) then return nil end
  return { key = w.c, npc = base.npc, map = base.map, x = base.x or 50, y = base.y or 50, exact = base.x ~= nil }
end

---------------------------------------------------------------- prices
-- a price: what the auction house really asked in the last half hour (seen while buying: a stack you'd have
-- to take whole counts in full), else Auctionator's last scan
local SEEN_FOR = 30 * 60
local function AuctionatorTime()
  local sv = AUCTIONATOR_SAVEDVARS or {}
  return math.max(sv.TimeOfLastBrowseScan or 0, sv.TimeOfLastReplicateScan or 0)
end
local function AuctionatorPrice(item)
  local api = Auctionator and Auctionator.API and Auctionator.API.v1
  if not api then return nil end
  local ok, p = pcall(api.GetAuctionPriceByItemID, "WritPath", item)
  return ok and p or nil
end
-- a price per unit when you need n: what the auction house really asked in the last half hour (seen while
-- buying), else the newer of WritPath's own scan and Auctionator's, else whichever has it
local function Price(item, n)
  if not item then return nil end
  -- WritPath's own scan knows how many are listed: needing more than that means you can't buy them, whatever
  -- price another source has (Auctionator's has no quantity, so it would make anything look plentiful)
  local avail = WritPath_ScanAvail and WritPath_ScanAvail(item)
  if avail and avail < math.max(1, n or 1) then return nil end
  local seen = WritPathNav and WritPathNav.seenPrice and WritPathNav.seenPrice[item]
  if seen and time() - (seen.t or 0) < SEEN_FOR then return seen.u end
  local mine = WritPath_ScanPrice and WritPath_ScanPrice(item, n)
  local theirs = AuctionatorPrice(item)
  if mine and theirs then
    return ((WritPath_ScanTime and WritPath_ScanTime() or 0) >= AuctionatorTime()) and mine or theirs
  end
  return mine or theirs
end
WritPath_Price = Price   -- Favor.lua prices crates and materials the same way
local function HavePrices()
  return (Auctionator and Auctionator.API) or (WritPath_ScanTime and WritPath_ScanTime()) and true or false
end

-- copper to do this writ now: the writ (unless you have it) plus the items you're still missing
local function Cost(id)
  local w = DB[id]
  local have = Count(id) > 0 or InLog(w.q)
  local writ = have and 0 or Price(id)
  if not writ then return nil, "no AH price for the writ" end
  if not w.req then return nil, "requested item unknown" end
  local need = math.max(0, (w.n or 1) - Count(w.req))
  local item = need == 0 and 0 or Price(w.req, need)
  if not item then return nil, "no AH price for " .. (ItemName(w.req) or "the item") end
  return writ + item * need, have, need
end

local function PouchAverage(tier)
  local sum, n = 0, 0
  for _, e in ipairs(WritPathMoney and WritPathMoney.log or {}) do
    if e.tier == tier and e.paid then sum, n = sum + e.paid, n + 1 end
  end
  return n > 0 and sum / n or POUCH_GUESS[tier]
end

---------------------------------------------------------------- travel (Travel.lua: real paths)
local Travel = WritPath_Travel
local Pos, PlayerPos = Travel.Point, Travel.PlayerPoint
-- Job (1.17.0): the Plan button's work runs a few milliseconds a frame instead of all at once, which froze the game
-- for seconds on a first plan. Job.Tick() is called throughout the planner: inside a job it pauses until the next
-- frame once the frame's share is used up; anywhere else it does nothing. (Below: Job.Start, Job.Tick.)
local Job = { on = false, t0 = 0, n = 0, gen = 0, keep = false }
local memo = setmetatable({}, { __mode = "k" })
local function Secs(a, b)
  if not (a and b) then return 600 end
  local row = memo[a]; if not row then row = setmetatable({}, { __mode = "k" }); memo[a] = row end
  local t = row[b]
  if not t then t = Travel.Time(a, b); row[b] = t; if Job.on then Job.Tick() end end
  return t
end
local function ResetMemo() memo = setmetatable({}, { __mode = "k" }) end

local function PathSecs(start, route)
  local t, prev = 0, start
  for _, p in ipairs(route) do t = t + Secs(prev, p.pos) + 20; prev = p.pos end
  return t
end

-- Hearthstone, Astral Recall, mage teleports, Teleport: Moonglade: each goes on the legs where it saves the most
-- (at least 3 minutes), when it's off cooldown by then, a cooldown apart, one per leg, as many as you have runes.
-- (A mage teleport costs a Rune of Teleportation and the hearthstone's cooldown is long: neither is spent to
-- save a minute or two.)
-- Returns { [leg index] = { tp =, save = } } and the seconds saved.
local TELE_MIN = 180
-- legs[i] = { t = start time, secs = travel time }; via(k, i) = seconds for leg i using teleport k
local function AssignTeleports(legs, list, via)
  local cands = {}
  for i, L in ipairs(legs) do
    if L.secs > TELE_MIN then
      for k, tp in ipairs(list) do
        local v = via(k, i)
        local save = v and (L.secs - v) or 0
        if save >= TELE_MIN then cands[#cands + 1] = { i = i, tp = tp, save = save } end
      end
    end
  end
  table.sort(cands, function(a, b) if a.save ~= b.save then return a.save > b.save end return a.i < b.i end)
  local used, times, runes, total = {}, {}, nil, 0
  for _, c in ipairs(cands) do
    local tp, L = c.tp, legs[c.i]
    -- time saved by any teleport makes later legs start sooner: allow for all of it (a little cautious)
    local slack = total + c.save
    local ok = not used[c.i] and ((tp.ready or 0) <= 0 or L.t - slack >= tp.ready)
    for _, u in ipairs(ok and times[tp.key] or {}) do if math.abs(u - L.t) - slack < (tp.cd or 0) then ok = false end end
    if ok and tp.rune then runes = runes or tp.runes or 0; ok = runes > 0 end
    if ok then
      used[c.i] = { tp = tp, save = c.save }
      times[tp.key] = times[tp.key] or {}; table.insert(times[tp.key], L.t)
      if tp.rune then runes = runes - 1 end
      total = total + c.save
    end
  end
  if total == 0 then return nil, 0 end
  return used, total
end
WritPath_AssignTeleports = AssignTeleports   -- for tests
local function PlanTeleports(start, route)
  local list = Travel.Teleports and Travel.Teleports() or {}
  if #list == 0 or #route == 0 then return nil, 0 end
  local legs, t, prev = {}, 0, start
  for i, p in ipairs(route) do
    local s = (prev and p.pos) and Secs(prev, p.pos) or 0
    legs[i] = { t = t, secs = s, to = p.pos }
    t = t + s + 20; prev = p.pos
  end
  return AssignTeleports(legs, list, function(k, i)
    return legs[i].to and (list[k].cast + Secs(list[k].dest, legs[i].to)) or nil
  end)
end
local function ApplyTeleports(plan)
  local used, saved = PlanTeleports(plan.start, plan.route)
  plan.tele = used
  if saved > 0 then plan.secs = math.max(0, (plan.secs or 0) - saved) end
  return plan
end

local function InsertAt(start, route, pos)
  local best, at
  for i = 1, #route + 1 do
    local prev = i == 1 and start or route[i - 1].pos
    local nxt = route[i] and route[i].pos
    local dt = Secs(prev, pos) + (nxt and (Secs(pos, nxt) - Secs(prev, nxt)) or 0)
    if not best or dt < best then best, at = dt, i end
  end
  return best, at
end

local function TwoOpt(start, route)
  local improved = true
  while improved do
    improved = false
    for i = 1, #route - 1 do
      for j = i + 1, #route do
        local before = PathSecs(start, route)
        local a, b = i, j
        while a < b do route[a], route[b] = route[b], route[a]; a, b = a + 1, b - 1 end
        if PathSecs(start, route) < before - 1 then improved = true
        else a, b = i, j; while a < b do route[a], route[b] = route[b], route[a]; a, b = a + 1, b - 1 end end
      end
    end
  end
end

---------------------------------------------------------------- picking writs
-- every writ you could do right now, with why the others can't be
-- Quick plans: only customers within a short walk of a flight path you have, so the trip is fly in, hand in,
-- fly out. Set while a Quick plan is being made.
local QUICK_YARDS = 300
local quickOnly = false
local function QuickOK(c)
  if not quickOnly then return true end
  local pos = c and Pos(c.map, c.x, c.y)
  return pos and c.exact and Travel.NearKnown(pos, QUICK_YARDS) ~= nil
end

-- the planning job (see Job above). It never pauses while a Quick plan is being made: quickOnly is shared, and
-- something else planning in the pause would see it.
Job.MS = 8   -- milliseconds of planning per frame
function Job.Tick()
  if not Job.on or quickOnly then return end
  Job.n = Job.n + 1
  if Job.n % 16 ~= 0 then return end
  if debugprofilestop and debugprofilestop() - Job.t0 > Job.MS then coroutine.yield() end
end
-- how far the job has got, 0 to 1, for the loading bar: Job.Span(lo, hi) says which part of the bar the next stage
-- fills, Job.At(f) how far through that stage it is (the bar never goes back)
Job.p, Job.lo, Job.hi = 0, 0, 1
function Job.Span(lo, hi) Job.lo, Job.hi = lo, hi; Job.At(0) end
function Job.At(f)
  local v = Job.lo + (Job.hi - Job.lo) * math.max(0, math.min(1, f))
  if v > Job.p then Job.p = v end
end
-- pcall stops a pause (Lua 5.1 can't pause inside one): inside a job, call straight through and let an error end
-- the job instead
function Job.Try(fn, ...)
  if Job.on then return true, fn(...) end
  return pcall(fn, ...)
end
-- work() runs as a job; done(result) gets its answer. A new job replaces one still running. Returns true when
-- it finished at once.
function Job.Start(work, done)
  Job.gen = Job.gen + 1
  Job.keep = false   -- a job replaced mid-way may have left it set
  Job.p, Job.lo, Job.hi = 0, 0, 1
  local gen, co = Job.gen, coroutine.create(work)
  Job.frame = Job.frame or CreateFrame("Frame")
  local function Step()
    Job.on, Job.t0, Job.n = true, debugprofilestop and debugprofilestop() or 0, 0
    local ok, res = coroutine.resume(co)
    Job.on = false
    if gen ~= Job.gen then return true end
    if not ok then
      quickOnly, Job.keep = false, false
      Job.frame:SetScript("OnUpdate", nil)
      if Job.onStep then Job.onStep(nil) end
      if geterrorhandler then geterrorhandler()(res) end
      return true
    end
    if coroutine.status(co) == "dead" then Job.frame:SetScript("OnUpdate", nil); done(res); return true end
    if Job.onStep then Job.onStep(Job.p) end
  end
  Job.frame:SetScript("OnUpdate", nil)
  if Step() then return true end
  Job.frame:SetScript("OnUpdate", WritPath_Timed("planner", function() Step() end))
  return false
end

local function Candidates(zoneOnly)
  local list, skipped = {}, {}
  for id, w in pairs(DB) do
    local rep = REP[w.tier]
    local c = Customer(id)
    local why
    if Done(w.q) then why = "done today"
    elseif not c then why = "customer unknown"
    elseif not c.exact and not zoneOnly then why = "only the zone is known"
    elseif not QuickOK(c) then why = "not next to a flight path you have (Quick)" end
    local cost, have, need
    if not why then cost, have = Cost(id); if not cost then why = have end end
    if why then skipped[#skipped + 1] = { id = id, why = why }
    else
      local _, h, n = Cost(id)
      list[#list + 1] = { id = id, w = w, rep = rep, cost = cost, have = h, need = n, c = c, pos = Pos(c.map, c.x, c.y) }
    end
  end
  return list, skipped
end

---------------------------------------------------------------- the writs you already have, in the best order
-- best order from where you stand: every order tried (with pruning) up to EXACT stops, else insertion + 2-opt
local EXACT = 10
local function BestOrder(start, stops, quick)
  local n = #stops
  if n <= 1 then return stops end
  -- the same writs always go in the same order, whichever plan they came from
  local sorted = {}
  for i, s in ipairs(stops) do sorted[i] = s end
  table.sort(sorted, function(a, b) return a.id < b.id end)
  stops = sorted
  local pts = { start }
  for i, s in ipairs(stops) do pts[i + 1] = s.pos end
  local T = {}   -- travel seconds between every pair, worked out once
  for i = 1, n + 1 do T[i] = {}; for j = 1, n + 1 do T[i][j] = i == j and 0 or Secs(pts[i], pts[j]) end end
  -- a good first answer: cheapest insertion, then 2-opt
  local order = {}
  for i = 1, n do
    local best, at
    for k = 1, #order + 1 do
      local a, b = k == 1 and 1 or order[k - 1], order[k]
      local d = T[a][i + 1] + (b and (T[i + 1][b] - T[a][b]) or 0)
      if not best or d < best then best, at = d, k end
    end
    table.insert(order, at, i + 1)
  end
  local function Len(o) local t, p = 0, 1; for _, j in ipairs(o) do t = t + T[p][j]; p = j end; return t end
  -- 2-opt: reverse a stretch of the route when that's shorter. Only the two joining legs and the stretch's
  -- direction change, so each try is worked out from running sums instead of re-measuring the whole route.
  local F, B = {}, {}   -- F[k]: time along order[1..k] forwards; B[k]: the same stretch backwards
  local function Sums()
    F[1], B[1] = 0, 0
    for k = 2, n do F[k] = F[k - 1] + T[order[k - 1]][order[k]]; B[k] = B[k - 1] + T[order[k]][order[k - 1]] end
  end
  Sums()
  local passes, improved = 0, true
  while improved and passes < 50 do
    improved, passes = false, passes + 1
    for i = 1, n - 1 do
      if Job.on then Job.Tick() end
      for j = i + 1, n do
        local prev = i == 1 and 1 or order[i - 1]
        local nxt = order[j + 1]
        local oi, oj = order[i], order[j]
        local delta = T[prev][oj] + (nxt and T[oi][nxt] or 0) + (B[j] - B[i])
                    - T[prev][oi] - (nxt and T[oj][nxt] or 0) - (F[j] - F[i])
        if delta < -0.5 then
          local a, b = i, j
          while a < b do order[a], order[b] = order[b], order[a]; a, b = a + 1, b - 1 end
          Sums(); improved = true
        end
      end
    end
  end
  -- exact: try every order, dropping any branch already longer than the best found
  if n <= EXACT and not quick then
    local bestLen, bestOrder = Len(order), { unpack(order) }
    local used, cur = {}, {}
    local function DFS(depth, last, len)
      if Job.on then Job.Tick() end
      if len >= bestLen then return end
      if depth > n then bestLen, bestOrder = len, { unpack(cur) }; return end
      for j = 2, n + 1 do
        if not used[j] then
          used[j] = true; cur[depth] = j
          DFS(depth + 1, j, len + T[last][j])
          used[j] = nil
        end
      end
    end
    DFS(1, 1, 0)
    order = bestOrder
  end
  -- with a hearthstone or teleport ready, the best order can change: go to the far-off stop, then hearth
  -- back. Move stops and reverse stretches while the time with teleports gets shorter.
  local tps = not quick and Travel.Teleports and Travel.Teleports() or {}
  if #tps > 0 then
    local D = {}
    for k, tp in ipairs(tps) do D[k] = {}; for j = 2, n + 1 do D[k][j] = tp.cast + Secs(tp.dest, pts[j]) end end
    local function Score(o)
      local legs, t, p = {}, 0, 1
      for idx, j in ipairs(o) do legs[idx] = { t = t, secs = T[p][j], j = j }; t = t + T[p][j] + 20; p = j end
      local _, saved = AssignTeleports(legs, tps, function(k, i) return D[k][legs[i].j] end)
      return t - saved
    end
    local best, passes, better = Score(order), 0, true
    while better and passes < 20 do
      better, passes = false, passes + 1
      for i = 1, n do
        if Job.on then Job.Tick() end
        for k = 1, n do
          if i ~= k then
            local o = { unpack(order) }
            table.insert(o, k, table.remove(o, i))
            local sc = Score(o)
            if sc < best - 0.5 then order, best, better = o, sc, true end
          end
        end
      end
      for i = 1, n - 1 do
        for j = i + 1, n do
          local o = { unpack(order) }
          local a, b = i, j
          while a < b do o[a], o[b] = o[b], o[a]; a, b = a + 1, b - 1 end
          local sc = Score(o)
          if sc < best - 0.5 then order, best, better = o, sc, true end
        end
      end
    end
  end
  local out = {}
  for k, j in ipairs(order) do out[k] = stops[j - 1] end
  return out
end

-- writs in your bags or quest log (not yet handed in today), in the best order
local function PlanOwned(only, skipQuest, planned, ready, priced)   -- priced: planning to buy (leave out what can't be had)   -- only: just these writ ids; skipQuest: a quest just handed in;
                                                     -- planned: the "only" writs count even if not bought yet;
                                                     -- ready: only writs you can hand in now (their item in your bags)
  if not Job.keep then Travel.Reset(); ResetMemo() end   -- PlanBoth starts afresh once for all its passes
  local stops, later, unknown = {}, {}, {}
  local owned = {}
  for id, w in pairs(DB) do
    if (planned or Count(id) > 0 or InLog(w.q)) and not Done(w.q) and w.q ~= skipQuest and (not only or only[id]) then owned[#owned + 1] = id end
  end
  table.sort(owned, function(a, b)    -- higher rep first
    local ra, rb = REP[DB[a].tier] or 0, REP[DB[b].tier] or 0
    if ra ~= rb then return ra > rb end
    return a < b
  end)
  for _, id in ipairs(owned) do
    local w, c = DB[id], Customer(id)
    if not c then
      unknown[#unknown + 1] = { id = id, w = w, why = InLog(w.q) and "map pin not read yet" or "accept it so its map pin shows where it goes" }
    elseif ready and math.max(0, (w.n or 1) - Count(w.req)) > 0 then
      later[#later + 1] = { id = id, w = w, why = "needs its item first (" .. (ItemName(w.req) or "the item") .. "): buy it, or plan with a rep target" }
    elseif priced and WritPathNav and WritPathNav.dropped and WritPathNav.dropped[id] then
      later[#later + 1] = { id = id, w = w, why = "dropped from this plan (its writ or item isn't on the auction house)" }
    elseif priced and math.max(0, (w.n or 1) - Count(w.req)) > 0 and Cost(id) == nil then
      later[#later + 1] = { id = id, w = w, why = "its item (" .. (ItemName(w.req) or "the item") .. ") isn't on the auction house" }
    elseif not QuickOK(c) then
      later[#later + 1] = { id = id, w = w, why = "not next to a flight path you have (Quick)" }
    else
      local cost, _, need = Cost(id)
      local stop = { id = id, w = w, rep = REP[w.tier] or 0, c = c, pos = Pos(c.map, c.x, c.y),
                     cost = cost or 0, have = Count(id) > 0 or InLog(w.q), need = need or math.max(0, (w.n or 1) - Count(w.req)) }
      stops[#stops + 1] = stop
    end
  end
  local start = PlayerPos()
  local route = BestOrder(start, stops)
  local rep, cost, pouches = 0, 0, 0
  for _, p in ipairs(route) do rep, cost, pouches = rep + p.rep, cost + p.cost, pouches + PouchAverage(p.w.tier) end
  return ApplyTeleports({ route = route, rep = rep, cost = cost, secs = PathSecs(start, route), pouches = pouches, target = rep,
           start = start, later = later, unknown = unknown, owned = #owned, mine = true })
end

-- what to buy for a rep target: your own writs first (already paid for, they count toward the target),
-- then writs to fill the rest (each writ once: the game's daily limit is per writ, not per customer); the
-- whole set in the best order.
--   Cheapest: exact. A knapsack in steps of 25 rep over the writs for the least gold that reaches the target.
--   Fastest:  starts from the quickest greedy pick (and from the cheapest set), then keeps swapping or
--             dropping writs while the whole route gets shorter.
--   PlanBoth makes sure the fastest is never slower than the cheapest, nor the cheapest dearer than the fastest.

local function RepOf(set) local r = 0; for _, c in ipairs(set) do r = r + c.rep end; return r end
local function CostOf(set) local r = 0; for _, c in ipairs(set) do r = r + c.cost end; return r end
local function Join(a, b) local t = {}; for _, x in ipairs(a) do t[#t + 1] = x end; for _, x in ipairs(b) do t[#t + 1] = x end; return t end

-- the writs you could buy (not the ones you already have)
local function Buyable(zoneOnly)
  local list = {}
  for _, c in ipairs((Candidates(zoneOnly))) do
    local gone = WritPathNav and WritPathNav.dropped and WritPathNav.dropped[c.id]
    if c.pos and not gone and not (Count(c.id) > 0 or InLog(c.w.q)) then list[#list + 1] = c end
  end
  return list
end

local function CheapestSet(cands, need)
  if need <= 0 then return {} end
  local U = math.ceil(need / 25)
  local groups, keys = {}, {}
  for _, c in ipairs(cands) do
    local g = groups[c.id]
    if not g then g = {}; groups[c.id] = g; keys[#keys + 1] = c.id end
    g[#g + 1] = c
  end
  table.sort(keys)
  local INF = math.huge
  local dp = { [0] = 0 }
  for u = 1, U do dp[u] = INF end
  local picks = {}
  for gi, key in ipairs(keys) do
    if Job.on then Job.Tick() end
    local nd, pk = {}, {}
    for u = 0, U do nd[u] = dp[u] end
    for _, c in ipairs(groups[key]) do
      local r = math.floor(c.rep / 25)
      for u = 0, U do
        if dp[u] < INF then
          local v = math.min(U, u + r)
          if dp[u] + c.cost < nd[v] then nd[v] = dp[u] + c.cost; pk[v] = { c = c, from = u } end
        end
      end
    end
    picks[gi], dp = pk, nd
  end
  local u = U
  while u > 0 and dp[u] == INF do u = u - 1 end   -- target out of reach: the most rep there is
  local set = {}
  for gi = #keys, 1, -1 do
    local p = picks[gi][u]
    if p then set[#set + 1] = p.c; u = p.from end
  end
  return set
end

local function GreedyFast(start, owned, cands, need, seed)
  local route, rep, keys, set = {}, 0, {}, {}
  for _, p in ipairs(owned) do route[#route + 1] = p end
  -- a starting set (the writs at your flight-path hubs): kept, and the quickest extras added to it
  for _, c in ipairs(seed or {}) do
    if not keys[c.id] then
      keys[c.id] = true; c.inGreedy = true
      local _, at = InsertAt(start, route, c.pos)
      table.insert(route, at, c); set[#set + 1] = c; rep = rep + c.rep
    end
  end
  while rep < need do
    if Job.on then Job.Tick() end
    local best, bestScore, bestAt
    for _, c in ipairs(cands) do
      if not keys[c.id] and not c.inGreedy then
        local dt, at = InsertAt(start, route, c.pos)
        local score = (dt + 20) / math.min(c.rep, need - rep) + c.cost * 1e-7
        if not bestScore or score < bestScore then best, bestScore, bestAt = c, score, at end
      end
    end
    if not best then break end
    best.inGreedy, keys[best.id] = true, true
    table.insert(route, bestAt, best); set[#set + 1] = best; rep = rep + best.rep
  end
  for _, c in ipairs(cands) do c.inGreedy = nil end
  return set
end

local function Improve(start, owned, cands, need, seed)
  if RepOf(seed) < need then return seed end   -- can't reach the target: nothing to swap or drop
  local function Eval(set) return PathSecs(start, BestOrder(start, Join(owned, set), true)) end
  -- only the 30 writs closest to this route are worth trying as swaps
  local route = Join(owned, seed)
  local function Near(c)
    local best = Secs(start, c.pos)
    for _, p in ipairs(route) do local t = Secs(p.pos, c.pos); if t < best then best = t end end
    return best
  end
  local near = {}
  for _, c in ipairs(cands) do near[#near + 1] = { c = c, d = Near(c) } end
  table.sort(near, function(a, b) return a.d < b.d end)
  cands = {}
  for i = 1, math.min(30, #near) do cands[i] = near[i].c end
  local cur, curT = seed, Eval(seed)
  for _ = 1, 10 do
    local bestT, bestCost, bestSet = curT, CostOf(cur), nil
    local function Try(set)
      local t = Eval(set)
      if t < bestT - 1 or (t < bestT + 1 and CostOf(set) < bestCost) then bestT, bestCost, bestSet = t, CostOf(set), set end
    end
    local have, total = {}, RepOf(cur)
    for _, c in ipairs(cur) do have[c.id] = c end
    for i = 1, #cur do
      if Job.on then Job.Tick() end
      if total - cur[i].rep >= need then                  -- drop one
        local t = {}; for j, c in ipairs(cur) do if j ~= i then t[#t + 1] = c end end
        Try(t)
      end
      for _, c in ipairs(cands) do                        -- swap one for another
        if not have[c.id] and total - cur[i].rep + c.rep >= need then
          local t = {}; for j, x in ipairs(cur) do t[j] = (j == i) and c or x end
          Try(t)
        end
      end
    end
    if not bestSet then break end
    cur, curT = bestSet, bestT
  end
  return cur
end

local function Finish(start, owned, set, target, mine, mode)
  local route = BestOrder(start, Join(owned, set))
  local rep, cost, pouches, bought, ownedUsed, used = 0, 0, 0, 0, 0, {}
  for _, p in ipairs(route) do
    rep, cost, pouches = rep + p.rep, cost + p.cost, pouches + PouchAverage(p.w.tier)
    if p.have then ownedUsed = ownedUsed + 1 else bought = bought + 1 end
    used[p.id] = true
  end
  -- your writs that still need an item and weren't worth it for this target wait for another day, with why
  local later = {}
  for _, l in ipairs(mine.later or {}) do later[#later + 1] = l end
  for _, p in ipairs(mine.paidOwned or {}) do
    if not used[p.id] then
      later[#later + 1] = { id = p.id, w = p.w, why = ("its item costs %s: not needed for this target"):format(Coins(p.cost)) }
    end
  end
  return ApplyTeleports({ route = route, rep = rep, cost = cost, secs = PathSecs(start, route), pouches = pouches, target = target,
           start = start, later = later, unknown = mine.unknown, bought = bought, ownedUsed = ownedUsed, mode = mode,
           set = set })
end

-- Optimized (1.17.0): the third plan, between Cheapest and Fastest. It prices a minute of travel at the going rate
-- between the two (what Fastest pays per minute it saves over Cheapest) and takes the plan with the least gold +
-- priced time. So it costs no more than Fastest, takes no longer than Cheapest, and only pays for a minute where
-- the minute is cheap.

-- a set's writs, picked one at a time by (gold + priced travel) per rep, then improved by dropping or swapping
-- writs while that total goes down; rate = copper per second of travel
local BuildOptimized
do
-- Each writ's best spot in the route is kept between picks: a new stop only splits one leg, so a writ whose best
-- spot was that leg is worked out again, and every other writ only checks the two new legs.
local function GreedyWeighted(start, owned, cands, need, rate)
  local route, rep, set = {}, 0, {}
  for _, p in ipairs(owned) do route[#route + 1] = p end
  local open = {}   -- { c, dt = extra seconds at its best spot, before = the stop it goes in front of (nil: the end) }
  local function Spot(o) local dt, at = InsertAt(start, route, o.c.pos); o.dt, o.before = dt, route[at] end
  for _, c in ipairs(cands) do local o = { c = c }; Spot(o); open[#open + 1] = o end
  while rep < need do
    if Job.on then Job.Tick() end
    local best, bestScore
    for _, o in ipairs(open) do
      local score = (o.c.cost + rate * (o.dt + 20)) / math.min(o.c.rep, need - rep)
      if not bestScore or score < bestScore then best, bestScore = o, score end
    end
    if not best then break end
    local c, before = best.c, best.before
    local at = #route + 1
    if before then for i, p in ipairs(route) do if p == before then at = i; break end end end
    table.insert(route, at, c); set[#set + 1] = c; rep = rep + c.rep
    local prevPos = at == 1 and start or route[at - 1].pos
    local keep = {}
    for _, o in ipairs(open) do
      if o.c.id ~= c.id then
        keep[#keep + 1] = o
        if o.before == before then Spot(o)   -- its leg was the one split
        else
          local x = o.c.pos
          local d1 = Secs(prevPos, x) + Secs(x, c.pos) - Secs(prevPos, c.pos)
          if d1 < o.dt then o.dt, o.before = d1, c end
          local d2 = Secs(c.pos, x) + (before and (Secs(x, before.pos) - Secs(c.pos, before.pos)) or 0)
          if d2 < o.dt then o.dt, o.before = d2, before end
        end
      end
    end
    open = keep
  end
  return set
end
local function ImproveWeighted(start, owned, cands, need, seed, rate)
  if RepOf(seed) < need then return seed end
  local function Score(set) return CostOf(set) + rate * PathSecs(start, BestOrder(start, Join(owned, set), true)) end
  -- swaps worth trying: the 20 writs closest to the route and the 20 cheapest for their rep
  local route = Join(owned, seed)
  local function Near(c)
    local best = Secs(start, c.pos)
    for _, p in ipairs(route) do local t = Secs(p.pos, c.pos); if t < best then best = t end end
    return best
  end
  local byNear, byCost, pick, seen = {}, {}, {}, {}
  for _, c in ipairs(cands) do byNear[#byNear + 1] = { c = c, d = Near(c) }; byCost[#byCost + 1] = c end
  table.sort(byNear, function(a, b) return a.d < b.d end)
  table.sort(byCost, function(a, b) return a.cost / a.rep < b.cost / b.rep end)
  for i = 1, math.min(20, #byNear) do local c = byNear[i].c; if not seen[c] then seen[c] = true; pick[#pick + 1] = c end end
  for i = 1, math.min(20, #byCost) do local c = byCost[i]; if not seen[c] then seen[c] = true; pick[#pick + 1] = c end end
  -- each try is timed on the current order (the writ taken out, the new one put in its best spot): quick, and
  -- only the winner of a round is put in the best order again
  local cur, curS = seed, Score(seed)
  for _ = 1, 8 do
    local order = BestOrder(start, Join(owned, cur), true)
    local bestS, bestSet = curS - 1, nil
    local have, total, cost = {}, RepOf(cur), CostOf(cur)
    for _, c in ipairs(cur) do have[c.id] = true end
    for i = 1, #cur do
      if Job.on then Job.Tick() end
      local without = {}
      for _, p in ipairs(order) do if p ~= cur[i] then without[#without + 1] = p end end
      local base = PathSecs(start, without)
      if total - cur[i].rep >= need then                  -- drop one
        local s = cost - cur[i].cost + rate * base
        if s < bestS then local t = {}; for j, c in ipairs(cur) do if j ~= i then t[#t + 1] = c end end; bestS, bestSet = s, t end
      end
      for _, c in ipairs(pick) do                         -- swap one for another
        if not have[c.id] and total - cur[i].rep + c.rep >= need then
          local s2 = cost - cur[i].cost + c.cost + rate * (base + (InsertAt(start, without, c.pos)))
          if s2 < bestS then local t = {}; for j, x in ipairs(cur) do t[j] = (j == i) and c or x end; bestS, bestSet = s2, t end
        end
      end
    end
    if not bestSet then break end
    local s = Score(bestSet)
    if s >= curS - 1 then break end
    cur, curS = bestSet, s
  end
  return cur
end

-- res.optimized: the Optimized plan (res.cheap or res.fast when nothing between them is worth it). It can also find
-- a quicker Fastest than res.fast; then that becomes res.fast.
function BuildOptimized(res, target)
  local cheap, fast, x = res.cheap, res.fast, res.ctx
  local dc, dt = fast.cost - cheap.cost, cheap.secs - fast.secs
  local goal = math.min(target, cheap.rep)
  res.optimized = cheap
  -- nothing to trade: Fastest costs no more (it's just better), or Cheapest is no slower
  if dt <= 0 then return end
  if dc <= 0 then res.optimized = fast; return end
  local going = dc / dt                                  -- copper per second Fastest pays to save time
  -- the plans to choose from: both ends, and the best plan at a third of the going rate, at it, and at three times
  -- it, so there are plans either side of the going rate to pick from
  local pool, seen, made = { cheap, fast }, {}, 0
  local function Ids(p) local t = {}; for _, s in ipairs(p.route) do t[#t + 1] = s.id end; table.sort(t); return table.concat(t, ",") end
  seen[Ids(cheap)], seen[Ids(fast)] = true, true
  local function Gen(rate)
    local ok, set = Job.Try(function()
      return ImproveWeighted(x.start, x.owned, x.cands, x.need, GreedyWeighted(x.start, x.owned, x.cands, x.need, rate), rate)
    end)
    made = made + 1; Job.At(made / 4)
    if not (ok and set) then return end
    local ok2, p = Job.Try(Finish, x.start, x.owned, set, target, x.mine, "optimized")
    if ok2 and p and p.rep >= goal and not seen[Ids(p)] then seen[Ids(p)] = true; pool[#pool + 1] = p end
  end
  if x and x.need > 0 and fast.rep >= goal then
    for _, m in ipairs({ 0.33, 1, 3 }) do Gen(going * m) end
  end
  -- a plan found here can beat Fastest at its own game: then it's Fastest (by the same rule as PlanBoth's: of the
  -- plans within 10% or 3 minutes of the quickest, the cheapest), and the going rate is worked out again
  local quickest
  for _, p in ipairs(pool) do if p.rep >= goal and (not quickest or p.secs < quickest) then quickest = p.secs end end
  if quickest and quickest < fast.secs then
    local pick
    for _, p in ipairs(pool) do
      if p.rep >= goal and p.secs <= math.max(quickest * 1.10, quickest + 180) and (not pick or p.cost < pick.cost) then pick = p end
    end
    if pick and pick ~= fast and pick.secs < fast.secs then
      pick.mode, pick.short = "fast", fast.short
      fast = pick; res.fast = pick
      dc, dt = fast.cost - cheap.cost, cheap.secs - fast.secs
      if dt <= 0 then res.optimized = cheap; Job.At(1); return end
      if dc <= 0 then res.optimized = fast; Job.At(1); return end
      going = dc / dt
      Gen(going)
    end
  end
  Job.At(1)
  local best, bestS
  for _, p in ipairs(pool) do
    if p.rep >= goal and p.secs >= fast.secs and p.cost <= fast.cost then
      local s = p.cost + going * p.secs
      if not bestS or s < bestS - 0.5 then best, bestS = p, s end
    end
  end
  res.optimized = best or cheap
end
end

local PlanBothInner
local PlanBoth
do
local PlanBothOnce
function PlanBoth(target, zoneOnly, quick)
  -- the travel map and times are worked out afresh once, then shared by every pass below
  Travel.Reset(); ResetMemo()
  local keep = Job.keep
  Job.keep = true
  local ok, res = Job.Try(PlanBothOnce, target, zoneOnly, quick)
  Job.keep, quickOnly = keep, false
  if not ok then error(res, 0) end
  return res
end
function PlanBothOnce(target, zoneOnly, quick)
  quickOnly = quick and true or false
  Job.Span(0, quick and 0.6 or 0.4)                     -- the loading bar: this pass, then the ones below
  local ok, res = Job.Try(PlanBothInner, target, zoneOnly)
  quickOnly = false
  if not ok then error(res, 0) end
  if quick then res.cheap.quick, res.fast.quick = true, true; Job.Span(0.6, 1); BuildOptimized(res, target); return res end
  -- Fastest also weighs the hub plan (customers next to your flight paths: fly in, hand in, fly out) and
  -- takes it when it reaches the target in less time
  quickOnly = true
  Job.Span(0.4, 0.45)
  local ok2, hub = Job.Try(PlanBothInner, target, zoneOnly)
  quickOnly = false
  Job.Span(0.45, 0.65)
  -- the hub writs as a start, topped up with the quickest other writs until the target is reached
  local seeded
  if ok2 and hub and hub.fast and #hub.fast.route > 0 then
    local ids = {}
    for _, p in ipairs(hub.fast.route) do ids[p.id] = true end
    local ok3, s3 = Job.Try(PlanBothInner, target, zoneOnly, ids)
    if ok3 and s3 then seeded = s3.fast; seeded.hubs = true end
    hub.fast.hubs = true
  end
  -- Fastest: the quickest way to the target, without overpaying for a minute or two: of the plans within 10%
  -- (or 3 minutes) of the quickest, the cheapest
  local options = { res.fast, res.cheap }
  if ok2 and hub and hub.fast then options[#options + 1] = hub.fast end
  if seeded then options[#options + 1] = seeded end
  local goal = math.min(target, res.cheap.rep)
  local quickest
  for _, o in ipairs(options) do if o.rep >= goal and (not quickest or o.secs < quickest) then quickest = o.secs end end
  if quickest then
    local pick
    for _, o in ipairs(options) do
      if o.rep >= goal and o.secs <= math.max(quickest * 1.10, quickest + 180) and (not pick or o.cost < pick.cost) then pick = o end
    end
    if pick and pick ~= res.fast then
      if pick == res.cheap then pick = Finish(pick.start, {}, pick.route, target, { later = pick.later, unknown = pick.unknown }, "fast") end
      res.fast = pick
    end
  end
  Job.Span(0.65, 1)
  BuildOptimized(res, target)
  return res
end
end
local COMMITTED_FOR = 6 * 3600
function PlanBothInner(target, zoneOnly, seedIds)
  local mine = PlanOwned(nil, nil, nil, nil, true)
  -- writs you have whose items you have too cost nothing: always used. Writs you have that still need an item
  -- bought compete on price like any writ you'd buy, so a small target doesn't pay for items it doesn't need.
  -- A writ WritPath bought for you in the last few hours is committed: you planned it, so every new plan keeps it
  -- and buys its item (planning again for a bigger target mustn't strand a writ you just paid for). Older spare
  -- writs still compete on price.
  local start, owned, paidOwned = mine.start, {}, {}
  local paid = WritPathNav and WritPathNav.paidFor or {}
  local function JustBought(id) local b = paid[id]; return b and (b.t or 0) > time() - COMMITTED_FOR end
  for _, p in ipairs(mine.route) do
    if (p.cost or 0) > 0 and not JustBought(p.id) then paidOwned[#paidOwned + 1] = p
    else owned[#owned + 1] = p end
  end
  local cands = Buyable(zoneOnly)
  Job.At(0.1)
  for _, p in ipairs(paidOwned) do cands[#cands + 1] = p end
  mine.paidOwned = paidOwned
  local need = target - RepOf(owned)
  local cheapSet = CheapestSet(cands, need)
  local cheap = Finish(start, owned, cheapSet, target, mine, "cheap")
  Job.At(0.3)
  local fast
  if RepOf(cheapSet) < need then
    -- the target is out of reach today: every writ has to be used, so there's nothing to choose
    -- between and the fastest plan is the same trip
    fast = cheap
  else
    local seed
    if seedIds then
      seed = {}
      for _, c in ipairs(cands) do if seedIds[c.id] then seed[#seed + 1] = c end end
    end
    local fastA = Improve(start, owned, cands, need, GreedyFast(start, owned, cands, need, seed))
    Job.At(0.65)
    local fastB = Improve(start, owned, cands, need, cheapSet)
    Job.At(0.9)
    local fa, fb = Finish(start, owned, fastA, target, mine, "fast"), Finish(start, owned, fastB, target, mine, "fast")
    fast = (fb.secs < fa.secs or (fb.secs == fa.secs and fb.cost < fa.cost)) and fb or fa
  end
  if cheap.secs < fast.secs then fast = Finish(start, owned, cheapSet, target, mine, "fast") end   -- never slower
  if fast.cost < cheap.cost and fast.rep >= math.min(target, cheap.rep) then cheap = Finish(start, owned, fast.set, target, mine, "cheap") end
  -- the same writs are the same trip: share the quicker route so the two can't disagree on time
  local function Ids(plan) local t = {}; for _, p in ipairs(plan.route) do t[#t + 1] = p.id end; table.sort(t); return table.concat(t, ",") end
  if Ids(cheap) == Ids(fast) then
    local best = (fast.secs < cheap.secs) and fast or cheap
    cheap.route, cheap.secs, fast.route, fast.secs = best.route, best.secs, best.route, best.secs
  end
  -- when the target can't be reached: the most rep today, and what holds it back
  local function Ceiling(list) return RepOf(owned) + RepOf(list) end
  local short = { max = Ceiling(cands), withZone = (not zoneOnly) and Ceiling(Buyable(true)) or nil }
  cheap.short, fast.short = short, short
  return { cheap = cheap, fast = fast,
           ctx = { start = start, owned = owned, cands = cands, need = need, mine = mine, zoneOnly = zoneOnly } }
end

-- the plan for a choice ("cheap", "optimized" or "fast") out of PlanBoth's answer
local function Chosen(res, key)
  if not res then return nil end
  if key == "optimized" or key == "balanced" then return res.optimized or res.cheap end
  return res[key] or res.cheap
end

-- one plan: "cheap", "optimized", "fast", or a number (gold plus travel at that many copper per minute, greedy)
local function Plan(target, mode, zoneOnly)
  if mode == "cheap" or mode == "fast" or mode == "optimized" then return Chosen(PlanBoth(target, zoneOnly), mode) end
  local mine = PlanOwned()
  local start, owned = mine.start, mine.route
  local cands = Buyable(zoneOnly)
  local route, rep, keys, set = Join(owned, {}), RepOf(owned), {}, {}
  while rep < target do
    local best, bestScore, bestAt
    for _, c in ipairs(cands) do
      if not c.taken and not keys[c.id] then
        local dt, at = InsertAt(start, route, c.pos)
        local score = (c.cost + mode * dt / 60) / math.min(c.rep, target - rep)
        if not bestScore or score < bestScore then best, bestScore, bestAt = c, score, at end
      end
    end
    if not best then break end
    best.taken, keys[best.id] = true, true
    table.insert(route, bestAt, best); set[#set + 1] = best; rep = rep + best.rep
  end
  return Finish(start, owned, set, target, mine, mode)
end

---------------------------------------------------------------- turning a plan into guide steps
local function Crossing(toInst)
  local horde = UnitFactionGroup("player") == "Horde"
  local dest = toInst == 1 and "Kalimdor" or "the Eastern Kingdoms"
  if horde then return "{zeppelin} Cross to " .. G .. dest .. "|r: zeppelin Orgrimmar - Undercity (or boat Ratchet - Booty Bay)" end
  return "{boat} Cross to " .. G .. dest .. "|r: boat Menethil Harbor - Theramore or Auberdine (or the tram via Ironforge)"
end

-- guide steps for the way from one place to the next
local function TravelSteps(steps, from, to, suggested)
  local legs = Travel.Legs(from, to)
  for _, leg in ipairs(legs) do
    if leg.learn and suggested then suggested[leg.fpid] = true end   -- learned on the way: no separate suggestion
    if leg.kind == "unknown" then
      steps[#steps + 1] = { lines = { Crossing(to.inst) }, done = { arrive = { leg.into } } }
    else
      local what = leg.kind == "cross" and ("To " .. MapName(leg.into))
                or leg.kind == "fly" and (leg.fp or "Flight master")
                -- a zeppelin or airship leaves from a tower, a boat from a dock (1.18.1)
                or (leg.text or ""):find("take the zeppelin") and "Zeppelin tower"
                or (leg.text or ""):find("take the airship") and "Airship tower" or "Dock"
      -- a flight is done once you take off, a boat or zeppelin once you land (not on reaching the dock)
      local done = leg.kind == "fly" and { taxi = true, arrive = { leg.into } }
                or leg.kind == "sail" and { sail = true, arrive = { leg.into } } or { arrive = { leg.into } }
      -- a road or path: its waypoints (way) guide the arrow; the step itself shows no coordinates
      local way
      if leg.way and #leg.way > 1 then
        way = {}
        for _, q in ipairs(leg.way) do way[#way + 1] = { q.map, q.x, q.y, what } end
      end
      steps[#steps + 1] = { at = { leg.at.map, leg.at.x, leg.at.y, what }, way = way, lines = { leg.text, leg.warn }, done = done, fpid = leg.fpid,
                              flyTo = leg.kind == "fly" and leg.toFp or nil, flyToName = leg.kind == "fly" and leg.toName or nil }
    end
  end
  return legs.finalWarn   -- danger on the last stretch, to the stop itself
end

local FP_DETOUR, GREY_ = 1e9, "|cFFAAAAAA"   -- any flight path you lack in a zone the route takes you to
local function Steps(plan)
  local steps, buy, quests, items, suggested = {}, {}, {}, {}, {}
  for _, p in ipairs(plan.route) do
    if not p.have then buy[#buy + 1] = "{buy} " .. Y .. "Craftsman's Writ: " .. p.w.name .. "|r" end
    if p.need > 0 then
      buy[#buy + 1] = "{buy} " .. Y .. (ItemName(p.w.req) or p.w.name) .. "|r" .. (p.need > 1 and (" x" .. p.need) or "")
    end
    quests[#quests + 1] = p.w.q
    items[#items + 1] = { p.w.req, p.w.n or 1, p.w.q }
  end
  local first = { "{buy} At the auction house buy:" }
  for _, l in ipairs(buy) do first[#first + 1] = l end
  first[#first + 1] = W_ .. "Then right-click every writ to accept it|r"
  if #buy == 0 then first = { "{buy} You have every writ and item: right-click each writ to accept it" } end
  steps[1] = { lines = first, done = { ready = { quests = quests, items = items } } }

  local prev, last = plan.start, nil
  for ri, p in ipairs(plan.route) do
    local tl = plan.tele and plan.tele[ri]
    -- the next writ for the customer you're already at (the game's limit is per writ, not per customer):
    -- no travel, just hand it in too
    local same = last and not tl and last.c.key == p.c.key and last.c.map == p.c.map
                 and math.abs(last.c.x - p.c.x) < 0.5 and math.abs(last.c.y - p.c.y) < 0.5
    if same then
      steps[#steps + 1] = { at = { p.c.map, p.c.x, p.c.y, p.c.npc or p.w.name },
                            lines = { "{turnin} Also hand in " .. Y .. p.w.name .. "|r to " .. G .. (p.c.npc or "the same customer") .. "|r" },
                            done = { quests = { p.w.q } }, writ = p.id }
    else
      local warn
      -- a customer with a way in (a ramp, a gap in a wall): the route goes to that spot first, then on foot to them
      local base = WritPath_Customers and WritPath_Customers[p.w.c]
      local via = base and base.via and p.pos and Travel.Point(p.pos.map, base.via[1], base.via[2])
      local dest = via or p.pos
      if tl and p.pos then
        local tp = tl.tp
        steps[#steps + 1] = { lines = { ("{hs} %s to %s%s|r %s(saves ~%d min%s)|r"):format(tp.text, G, tp.destName or MapName(tp.dest.map),
                                GREY_, math.floor(tl.save / 60 + 0.5), tp.rune and ", uses a Rune of Teleportation" or "") },
                              done = { arrive = { tp.dest.map } }, teleport = tp.key }
        warn = TravelSteps(steps, tp.dest, dest, suggested)
      elseif prev and p.pos then warn = TravelSteps(steps, prev, dest, suggested) end
      if via then
        steps[#steps + 1] = { at = { via.map, via.x, via.y, "The way in" }, done = { via = true },
                              lines = { ("{goto} Ride to %s%.1f, %.1f|r first: the way in to %s"):format(G, via.x, via.y, p.c.npc or "the customer"),
                                        base.via[3] and (GREY_ .. base.via[3] .. "|r") or nil } }
      end
      local zone, lines = MapName(p.c.map), {}
      lines[#lines + 1] = "{goto} Go to " .. G .. (p.c.npc or "the writ customer") .. "|r in " .. zone
      if warn then lines[#lines + 1] = warn end
      lines[#lines + 1] = "{turnin} Hand in " .. Y .. p.w.name .. "|r"
      if not p.c.exact then lines[#lines + 1] = W_ .. "Exact spot unknown: once you accept the writ, its map pin sets the arrow|r" end
      -- a customer who walks a patrol: where to look
      if base and base.patrol then lines[#lines + 1] = GREY_ .. base.patrol .. "|r" end
      -- a flight path you don't have in this customer's zone: worth grabbing while you're there, on the way in when
      -- the flight master is nearer to where you come from than the customer is, otherwise right after
      local fp = Travel.UnlearnedNear and Travel.UnlearnedNear(p.pos, FP_DETOUR)
      local fpStep
      if fp and not suggested[fp.id] and not (WritPathNav and WritPathNav.skipFp and WritPathNav.skipFp[fp.id]) then
        suggested[fp.id] = true
        local town = (fp.name or "the flight master"):match("^([^,]+)") or fp.name
        fpStep = { at = { fp.map, fp.x, fp.y, "Flight master" },
                   lines = { "{fp} Learn the flight path at " .. G .. town .. "|r while you're here",
                             GREY_ .. "Talk to the flight master. Not needed? Tick the box to skip it.|r" },
                   done = { taxiMap = true }, fpid = fp.id }
      end
      local fpPoint = fpStep and Travel.Point(fp.map, fp.x, fp.y)
      local before = fpPoint and prev and p.pos and prev.inst == fpPoint.inst
                     and Travel.Dist(prev, fpPoint) < Travel.Dist(prev, p.pos)
      if fpStep and before then steps[#steps + 1] = fpStep end
      steps[#steps + 1] = { at = { p.c.map, p.c.x, p.c.y, p.c.npc or p.w.name }, lines = lines,
                            done = { quests = { p.w.q } }, writ = p.id }
      if fpStep and not before then steps[#steps + 1] = fpStep end
    end
    last = p
    prev = p.pos or prev
  end
  return steps
end

---------------------------------------------------------------- planner window
-- Styled through EllesmereUI's skinning API when it's installed (its theme, font and accent, kept in sync);
-- otherwise a plain flat dark look. Every text has a set width and wraps; the window grows to fit.
local W = 470                     -- window width
local PAD = 12
local INNER = W - PAD * 2
local GREY = "|cFFAAAAAA"

local f = CreateFrame("Frame", "WritPathPlanner", UIParent, "BackdropTemplate")
f:SetSize(W, 160); f:SetPoint("CENTER"); f:SetFrameStrata("DIALOG"); f:Hide()
f:SetMovable(true); f:EnableMouse(true); f:RegisterForDrag("LeftButton"); f:SetClampedToScreen(true)
f:SetScript("OnDragStart", f.StartMoving); f:SetScript("OnDragStop", f.StopMovingOrSizing)
tinsert(UISpecialFrames, "WritPathPlanner")   -- Escape closes it

local fonts, buttons, skin = {}, {}, nil   -- skin: EllesmereUI's skinning API, once it has called us
local function Text(parent, template, width, justify)
  local fs = parent:CreateFontString(nil, "OVERLAY", template or "GameFontHighlightSmall")
  fs:SetJustifyH(justify or "LEFT"); fs:SetJustifyV("TOP"); fs:SetWordWrap(true)
  if fs.SetNonSpaceWrap then fs:SetNonSpaceWrap(true) end
  if width then fs:SetWidth(width) end
  fonts[#fonts + 1] = fs
  if skin then skin.Font(fs) end   -- rows made after login get the EllesmereUI font too
  return fs
end
local function Btn(parent, label)
  local btn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate"); btn:SetHeight(22); btn:SetText(label)
  buttons[#buttons + 1] = btn
  return btn
end
local function FitWidth(btn)
  local fs = btn:GetFontString()
  local w = fs and fs:GetStringWidth()
  btn:SetWidth(math.max(60, (type(w) == "number" and w or 40) + 26))
end

local head = Text(f, "GameFontNormal"); head:SetPoint("TOPLEFT", PAD, -9); head:SetText("Writ Planner")
local closeX = CreateFrame("Button", nil, f, "UIPanelCloseButton"); closeX:SetSize(22, 22); closeX:SetPoint("TOPRIGHT", -3, -3)

-- one planner: a rep target plans what to buy (your own writs first); no target plans just the writs you have
local tabBar = f:CreateTexture(nil, "OVERLAY"); tabBar:SetHeight(2); tabBar:SetColorTexture(1, 0.82, 0, 1); tabBar:Hide()
-- how old the prices are: Auctionator's last full scan, and the oldest price the shown plan uses
-- on the title line, so the rep row below has the full width and the window can be narrow
local ageText = Text(f, "GameFontHighlightSmall", nil, "RIGHT"); ageText:SetWordWrap(false)
ageText:SetPoint("TOPRIGHT", f, "TOPRIGHT", -30, -11); ageText:SetPoint("LEFT", head, "RIGHT", 8, 0)

-- the rep target and the Plan button
local buyRow = CreateFrame("Frame", nil, f); buyRow:SetSize(INNER, 24)
-- what to plan for: reputation (writs) or Merchant's Favor (Waylaid Crates)
local modeBtn = Btn(buyRow, "Rep"); modeBtn:SetPoint("LEFT", 0, 0)
local repL = Text(buyRow); repL:SetPoint("LEFT", modeBtn, "RIGHT", 8, 0); repL:SetText("target"); repL:SetWordWrap(false)
local repBox = CreateFrame("EditBox", nil, buyRow, "InputBoxTemplate"); repBox:SetSize(54, 20); repBox:SetAutoFocus(false)
repBox:SetNumeric(true); repBox:SetText(""); repBox:SetPoint("LEFT", repL, "RIGHT", 10, 0)
local planBtn = Btn(buyRow, "Plan"); planBtn:SetPoint("LEFT", repBox, "RIGHT", 12, 0)
-- Favor only: count what's already in your bags as free, or buy everything
local bagsChk = CreateFrame("CheckButton", nil, buyRow, "UICheckButtonTemplate"); bagsChk:SetSize(22, 22)
bagsChk:SetPoint("LEFT", planBtn, "RIGHT", 10, 0)
local bagsL = Text(buyRow); bagsL:SetPoint("LEFT", bagsChk, "RIGHT", 2, 0); bagsL:SetText("Bags"); bagsL:SetWordWrap(false)
bagsChk:Hide(); bagsL:Hide()
-- plan with your Hearthstone or not (per character, WritPathChar.noHearth; also /writs hearth). Only the Hearthstone:
-- Astral Recall and mage or druid teleports are still used.
local hearthChk = CreateFrame("CheckButton", nil, buyRow, "UICheckButtonTemplate"); hearthChk:SetSize(22, 22)
local hearthL = Text(buyRow); hearthL:SetPoint("LEFT", hearthChk, "RIGHT", 2, 0); hearthL:SetText("Hearth"); hearthL:SetWordWrap(false)
local function PlaceHearth()
  hearthChk:ClearAllPoints()
  if bagsChk:IsShown() then hearthChk:SetPoint("LEFT", bagsL, "RIGHT", 8, 0) else hearthChk:SetPoint("LEFT", planBtn, "RIGHT", 10, 0) end
  hearthChk:SetChecked(not (WritPathChar and WritPathChar.noHearth))
end
PlaceHearth()
for _, w in ipairs({ repBox, planBtn }) do
  w:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP"); GameTooltip:SetText("Plan")
    GameTooltip:AddLine("With a rep target: the cheapest writs to reach it, the fastest, and the optimized mix of the two, starting from the writs you have.", 1, 1, 1, true)
    GameTooltip:AddLine("Leave it empty: just the writs you have, in the shortest order.", 1, 1, 1, true)
    GameTooltip:Show()
  end)
  w:SetScript("OnLeave", function() GameTooltip:Hide() end)
end
-- customers known only by their zone are always included: accepting the writ shows its map pin, and WritPath
-- reads the exact spot from it before you travel
local ZONE_ONLY = true
buyRow:Hide()

-- the three answers for a rep target, side by side (Cheapest, Optimized, Fastest) to compare at a glance: the name,
-- the gold up front (large), the time and rep, the net gold. Click one to see its writs; the chosen one has an
-- accent border and tint.
local CARD_GAP = 6
local CARD_W = math.floor((INNER - CARD_GAP * 2) / 3)
local function Card()
  local c = CreateFrame("Button", nil, f, "BackdropTemplate"); c:SetWidth(CARD_W)
  local tw = CARD_W - 16
  -- a dot before the name: grey, or the accent on the chosen card
  c.dot = c:CreateTexture(nil, "OVERLAY"); c.dot:SetSize(6, 6); c.dot:SetPoint("TOPLEFT", 8, -10)
  c.dot:SetTexture("Interface/BUTTONS/WHITE8X8"); c.dot:SetVertexColor(0.4, 0.4, 0.4, 1)
  if c.CreateMaskTexture then
    local m = c:CreateMaskTexture(); m:SetAllPoints(c.dot)
    m:SetTexture("Interface/CHARACTERFRAME/TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    c.dot:AddMaskTexture(m)
  end
  c.name = Text(c, "GameFontHighlightSmall", tw - 10); c.name:SetPoint("TOPLEFT", 18, -7); c.name:SetWordWrap(false)
  c.cost = Text(c, "GameFontHighlight", tw); c.cost:SetPoint("TOPLEFT", c.name, "BOTTOMLEFT", 0, -5)
  c.meta = Text(c, "GameFontHighlightSmall", tw); c.meta:SetPoint("TOPLEFT", c.cost, "BOTTOMLEFT", 0, -3)
  c.net = Text(c, "GameFontHighlightSmall", tw); c.net:SetPoint("TOPLEFT", c.meta, "BOTTOMLEFT", 0, -3)
  -- chosen: a tint and a 1 px accent border, drawn over whatever skin the card has
  c.tint = c:CreateTexture(nil, "ARTWORK"); c.tint:SetPoint("TOPLEFT", 1, -1); c.tint:SetPoint("BOTTOMRIGHT", -1, 1)
  c.edges = {}
  for i, pts in ipairs({ { "TOPLEFT", "TOPRIGHT" }, { "BOTTOMLEFT", "BOTTOMRIGHT" }, { "TOPLEFT", "BOTTOMLEFT" }, { "TOPRIGHT", "BOTTOMRIGHT" } }) do
    local e = c:CreateTexture(nil, "OVERLAY"); e:SetPoint(pts[1]); e:SetPoint(pts[2])
    if i <= 2 then e:SetHeight(1) else e:SetWidth(1) end
    c.edges[i] = e
  end
  c.sel = { c.tint, c.edges[1], c.edges[2], c.edges[3], c.edges[4] }
  function c.sel:Show() for _, t in ipairs(self) do t:Show() end end
  function c.sel:Hide() for _, t in ipairs(self) do t:Hide() end end
  function c.sel:SetColorTexture(r, g, b)
    self[1]:SetColorTexture(r, g, b, 0.12); for i = 2, #self do self[i]:SetColorTexture(r, g, b, 1) end
  end
  c.sel:SetColorTexture(1, 0.82, 0); c.sel:Hide()
  local hl = c:CreateTexture(nil, "HIGHLIGHT"); hl:SetPoint("TOPLEFT", 1, -1); hl:SetPoint("BOTTOMRIGHT", -1, 1)
  hl:SetColorTexture(1, 1, 1, 0.05)
  c:Hide(); return c
end
local cards = { cheap = Card(), optimized = Card(), fast = Card() }
-- the loading bar while the plans are worked out (Job): where the cards go, with how far it's got
local loadBar = CreateFrame("StatusBar", nil, f, "BackdropTemplate")
loadBar:SetHeight(18); loadBar:SetMinMaxValues(0, 1); loadBar:SetValue(0)
loadBar:SetStatusBarTexture("Interface/BUTTONS/WHITE8X8")
loadBar:SetStatusBarColor(1, 0.82, 0, 1)
-- the colour of EllesmereUI's XP bar (its gradient too) when it has one, else the accent
function loadBar.XPColor()
  local holder = _G.EllesmereEAB_XPBar
  local bar = type(holder) == "table" and rawget(holder, "_bar")
  local tex = loadBar:GetStatusBarTexture()
  if type(bar) ~= "table" or not bar.GetStatusBarColor then return false end
  local m = rawget(bar, "_xpGrad")
  if type(m) == "table" and m.on and tex and tex.SetGradient and CreateColor then
    loadBar:SetStatusBarColor(1, 1, 1, 1)
    tex:SetGradient(m.dir, CreateColor(m[1], m[2], m[3], m[4]), CreateColor(m[5], m[6], m[7], m[8]))
    return true
  end
  local r, g, b = bar:GetStatusBarColor()
  if type(r) ~= "number" or (r == 1 and g == 1 and b == 1) then r, g, b = 0.60, 0.40, 0.85 end   -- its XP purple, until painted
  loadBar:SetStatusBarColor(r, g, b, 1)
  return true
end
if loadBar.SetBackdrop then
  loadBar:SetBackdrop({ bgFile = "Interface/BUTTONS/WHITE8X8", edgeFile = "Interface/BUTTONS/WHITE8X8", edgeSize = 1 })
  loadBar:SetBackdropColor(0.1, 0.1, 0.12, 1); loadBar:SetBackdropBorderColor(0, 0, 0, 1)
end
loadBar.text = Text(loadBar, "GameFontHighlightSmall", nil, "CENTER"); loadBar.text:SetPoint("CENTER", 0, 0); loadBar.text:SetWordWrap(false)
loadBar:Hide()

-- the list, summary and notes scroll; tabs and cards stay at the top, the buttons at the bottom
local SB = 22                      -- room for the scroll bar
local LIST_W = INNER - SB
local scroll = CreateFrame("ScrollFrame", "WritPathPlannerScroll", f, "UIPanelScrollFrameTemplate")
scroll.scrollBarHideable = true    -- the bar hides itself when everything fits
local content = CreateFrame("Frame", nil, scroll); content:SetSize(LIST_W, 10)
scroll:SetScrollChild(content)
scroll:EnableMouseWheel(true)
local function Bar()
  local b = rawget(scroll, "ScrollBar") or scroll.ScrollBar
  if type(b) ~= "table" then b = _G["WritPathPlannerScrollScrollBar"] end
  return type(b) == "table" and b or nil
end

-- writ entries, one block each: number, tier badge and name on top; customer, zone and minutes underneath with
-- chips ("needs item", a teleport, "spot not exact") on the right; the price top right; a thin line under each.
-- Other entries (Favor, left out) are two plain lines.
local COST_W = 92
local rowPool = {}
local Row
do
local TIERC = { Ap = { 0.70, 0.70, 0.72 }, J = { 0.29, 0.87, 0.50 }, E = { 0.22, 0.74, 0.97 }, A = { 0.75, 0.52, 0.99 } }
local CHIP = { warn = { 0.26, 0.13, 0.02, "|cFFFEF08A" }, good = { 0.08, 0.33, 0.18, "|cFFBBF7D0" },
  bad = { 0.40, 0.08, 0.08, "|cFFFFDAD6" }, danger = { 0.60, 0.05, 0.05, "|cFFFFFFFF" }, info = { 0.05, 0.29, 0.43, "|cFFBAE6FD" } }
local NUM_W, BADGE = 22, 16
local function Edges(fr, list)
  for i, pts in ipairs({ { "TOPLEFT", "TOPRIGHT" }, { "BOTTOMLEFT", "BOTTOMRIGHT" }, { "TOPLEFT", "BOTTOMLEFT" }, { "TOPRIGHT", "BOTTOMRIGHT" } }) do
    local e = fr:CreateTexture(nil, "OVERLAY"); e:SetPoint(pts[1]); e:SetPoint(pts[2])
    if i <= 2 then e:SetHeight(1) else e:SetWidth(1) end
    list[i] = e
  end
end
local function Chip(r, k)
  local c = CreateFrame("Frame", nil, r)
  c.bg = c:CreateTexture(nil, "BACKGROUND"); c.bg:SetAllPoints(c)
  c.t = Text(c, "GameFontHighlightSmall", nil, "CENTER"); c.t:SetPoint("CENTER", 0, 0); c.t:SetWordWrap(false)
  r.chips[k] = c
  return c
end
local function Fill(r, e)
  local lw = LIST_W
  for _, c in ipairs(r.chips) do c:Hide() end
  local writ = e.writ and true or false
  for _, x in ipairs({ r.num, r.badge, r.title, r.sub, r.price }) do if writ then x:Show() else x:Hide() end end
  if writ then r.left:Hide(); r.right:Hide() else r.left:Show(); r.right:Show() end
  if not writ then
    r.left:SetWidth(lw - COST_W - 6); r.left:SetText(e[1]); r.right:SetText(e[2])
    return math.max(r.left:GetStringHeight(), r.right:GetStringHeight()) + 14
  end
  r.num:SetText(e.numText or (e.num .. "."))
  local tc = TIERC[e.tier] or { 0.6, 0.6, 0.6 }
  r.badge.bg:SetColorTexture(tc[1] * 0.3, tc[2] * 0.3, tc[3] * 0.3, 1)
  for _, ed in ipairs(r.badge.edges) do ed:SetColorTexture(tc[1], tc[2], tc[3], 1) end
  r.badge.t:SetText(e.tier or "?")
  local bw = r.badge.t:GetStringWidth(); r.badge:SetWidth(math.max(BADGE, (type(bw) == "number" and bw or 8) + 8))
  r.price:SetText(e.price)
  local bwid = r.badge:GetWidth(); bwid = type(bwid) == "number" and bwid or BADGE
  r.title:SetWidth(lw - NUM_W - bwid - 10 - COST_W); r.title:SetText(e.name)
  local x = 0
  -- placed from the right edge leftward, last chip first, so they read left to right in list order
  for k = #e.chips, 1, -1 do
    local chip = e.chips[k]
    local c = r.chips[k] or Chip(r, k)
    local st = CHIP[chip[2]]
    c.bg:SetColorTexture(st[1], st[2], st[3], 1); c.t:SetText(st[4] .. chip[1] .. "|r")
    local w = c.t:GetStringWidth(); w = (type(w) == "number" and w or 50) + 12
    c:SetSize(w, 16); c:ClearAllPoints(); c:SetPoint("TOPRIGHT", r, "TOPRIGHT", -x, -27); c:Show()
    x = x + w + 4
  end
  r.sub:SetWidth(math.max(60, lw - NUM_W - x - 6)); r.sub:SetText(e.sub)
  return 28 + math.max(r.sub:GetStringHeight(), #e.chips > 0 and 16 or 0) + 9
end
function Row(i)
  local r = rowPool[i]
  if r then return r end
  r = CreateFrame("Frame", nil, content); r:SetWidth(LIST_W)
  r.left = Text(r, nil, LIST_W - COST_W - 6); r.left:SetPoint("TOPLEFT", 0, -6); r.left:SetSpacing(2)
  r.right = Text(r, nil, COST_W, "RIGHT"); r.right:SetPoint("TOPRIGHT", 0, -6)
  r.num = Text(r, "GameFontDisableSmall", NUM_W); r.num:SetPoint("TOPLEFT", 0, -9); r.num:SetWordWrap(false)
  r.badge = CreateFrame("Frame", nil, r); r.badge:SetSize(BADGE, BADGE); r.badge:SetPoint("TOPLEFT", NUM_W, -6)
  r.badge.bg = r.badge:CreateTexture(nil, "BACKGROUND"); r.badge.bg:SetAllPoints(r.badge)
  r.badge.edges = {}; Edges(r.badge, r.badge.edges)
  r.badge.t = Text(r.badge, "GameFontHighlightSmall", nil, "CENTER"); r.badge.t:SetPoint("CENTER", 0, 0); r.badge.t:SetWordWrap(false)
  r.title = Text(r, "GameFontHighlight"); r.title:SetPoint("LEFT", r.badge, "RIGHT", 7, 0); r.title:SetWordWrap(false)
  r.price = Text(r, "GameFontHighlight", COST_W, "RIGHT"); r.price:SetPoint("TOPRIGHT", 0, -8); r.price:SetWordWrap(false)
  r.sub = Text(r, "GameFontHighlightSmall"); r.sub:SetPoint("TOPLEFT", NUM_W, -29)
  r.chips = {}
  r.line = r:CreateTexture(nil, "BACKGROUND"); r.line:SetHeight(1)
  r.line:SetPoint("BOTTOMLEFT", 0, 0); r.line:SetPoint("BOTTOMRIGHT", 0, 0); r.line:SetColorTexture(1, 1, 1, 0.08)
  r.Fill = Fill
  rowPool[i] = r
  return r
end
-- above the writs: "13 steps · Optimized route" and how many items still have to be bought
local head = CreateFrame("Frame", nil, content); head:SetHeight(20)
head.l = Text(head, "GameFontHighlightSmall"); head.l:SetPoint("LEFT", 0, 0); head.l:SetWordWrap(false)
head.r = Text(head, "GameFontHighlightSmall", nil, "RIGHT"); head.r:SetPoint("RIGHT", 0, 0); head.r:SetWordWrap(false)
head.line = head:CreateTexture(nil, "BACKGROUND"); head.line:SetHeight(1)
head.line:SetPoint("BOTTOMLEFT", 0, 0); head.line:SetPoint("BOTTOMRIGHT", 0, 0); head.line:SetColorTexture(1, 1, 1, 0.12)
head:Hide()
rowPool.head = head
end

local summary = Text(content, nil, LIST_W)
local note = Text(content, "GameFontDisableSmall", LIST_W)
local goBtn = Btn(f, "Start route"); goBtn:Disable()
local clearBtn = Btn(f, "Clear")   -- clears the route, the plan and its shopping (asks first)
clearBtn:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", PAD, PAD)
-- Auto-fly (off unless you tick it; WritPathNav.autoFly, also /writs autofly): see Nav.lua's WritPath_AutoFly
local flyChk = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate"); flyChk:SetSize(22, 22)
flyChk:SetPoint("LEFT", clearBtn, "RIGHT", 12, 0)
local flyL = Text(f); flyL:SetPoint("LEFT", flyChk, "RIGHT", 2, 0); flyL:SetText("Auto-fly"); flyL:SetWordWrap(false)

---------------------------------------------------------------- the EllesmereUI look (or a plain fallback)
local accent = { 1, 0.82, 0 }
local function Accent()
  if skin and skin.GetAccentColor then local r, g, b = skin.GetAccentColor(); if r then accent = { r, g, b } end end
  tabBar:SetColorTexture(accent[1], accent[2], accent[3], 1)
  for _, c in pairs(cards) do c.sel:SetColorTexture(accent[1], accent[2], accent[3], 1) end
  if not loadBar.XPColor() then loadBar:SetStatusBarColor(accent[1], accent[2], accent[3], 1) end
end
local function ApplySkin(S)
  skin = S
  S.Shell(f)
  S.CloseButton(closeX)
  for _, btn in ipairs(buttons) do S.Button(btn); if S.StateButtonLabel then S.StateButtonLabel(btn) end end
  S.EditBox(repBox, { padInput = true })
  if S.Checkbox then for _, chk in ipairs({ bagsChk, hearthChk, flyChk }) do if not chk.wpSkinned then chk.wpSkinned = true; S.Checkbox(chk) end end end
  for _, c in pairs(cards) do S.Panel(c, { inset = true }) end
  if Bar() and S.ScrollBar then S.ScrollBar(Bar()) end
  for _, fs in ipairs(fonts) do S.Font(fs) end
  Accent()
  if S.OnLooksChanged then S.OnLooksChanged(Accent) end
end
if EllesmereUI and EllesmereUI.RegisterSkin then EllesmereUI.RegisterSkin("WritPath", ApplySkin) end
WritPath_Skin = function() return skin end   -- for windows made later (the Discord link box)

local function PlainLook()   -- no EllesmereUI (or its skinning is off for WritPath): flat dark with thin borders
  if skin then return end
  local flat = { bgFile = "Interface/BUTTONS/WHITE8X8", edgeFile = "Interface/BUTTONS/WHITE8X8", edgeSize = 1 }
  f:SetBackdrop(flat); f:SetBackdropColor(0.06, 0.06, 0.07, 0.96); f:SetBackdropBorderColor(0, 0, 0, 1)
  for _, c in pairs(cards) do c:SetBackdrop(flat); c:SetBackdropColor(0.1, 0.1, 0.12, 1); c:SetBackdropBorderColor(0, 0, 0, 1) end
end

---------------------------------------------------------------- filling the window
local current, plans, choice
---------------------------------------------------------------- runs: the planner's estimate against your real time
-- Start route opens a run with the estimate; closing the auction house marks the end of buying; each hand-in on
-- the route is timed; the last one closes the run and says how it went. WritPathNav.runs keeps the last 20.
-- After 3 finished runs the planner's minutes are scaled to your pace (the median of your last 5).
local function FmtMin(secs)
  local m = math.floor((secs or 0) / 60 + 0.5)
  if m >= 60 then return ("%d h %02d m"):format(math.floor(m / 60), m % 60) end
  return m .. " m"
end
-- a run counts toward your pace only when it was (nearly) finished: its estimate is for the whole route, so a
-- route cleared early would look far too quick. And only when its estimate came from today's planner: PACE_V goes
-- up whenever the planner's times change (1.15.6: runs before it were timed by older planners, and with breaks).
local PACE_V = 2
local function Counts(run)
  local done, writs = run.done or 0, run.writs or 0
  return run.pv == PACE_V and run.travel and run.est and run.est > 0 and done >= 3 and (writs == 0 or done >= 0.75 * writs)
end
function WritPath_Pace()
  local r = {}
  for i = #(WritPathNav and WritPathNav.runs or {}), 1, -1 do
    local run = WritPathNav.runs[i]
    if Counts(run) then r[#r + 1] = run.travel / run.est end
    if #r == 5 then break end
  end
  if #r < 3 then return 1, #r end
  table.sort(r)
  local med = r[math.floor((#r + 1) / 2)]
  return math.max(0.5, math.min(3, med)), #r
end
local function Minutes(secs) return math.floor((secs or 0) * (WritPath_Pace()) / 60 + 0.5) end

local function CloseRun(reason)
  local run = WritPathNav and WritPathNav.run
  if not run then return end
  WritPathNav.run = nil
  if (run.done or 0) == 0 then return end   -- nothing handed in: not a run worth keeping
  -- travel: from leaving the auction house (or the start) to the last hand-in, less the time you stood still
  run.travel = math.max(0, (run.last or run.start) - (run.boughtAt or run.start) - (run.idleAtLast or 0))
  run.total = (run.last or run.start) - run.start
  WritPathNav.runs = WritPathNav.runs or {}
  table.insert(WritPathNav.runs, run)
  while #WritPathNav.runs > 20 do table.remove(WritPathNav.runs, 1) end
  Print(("Run done%s: %d writs, %d rep in %s of travel%s; the planner said %s."):format(reason and (" (" .. reason .. ")") or "",
    run.done, run.rep or 0, FmtMin(run.travel), run.boughtAt and (" (+" .. FmtMin(run.boughtAt - run.start) .. " buying)") or "", FmtMin(run.est)))
end
WritPath_CloseRun = CloseRun

local function StartRun(plan)
  CloseRun("a new route started")
  WritPathNav.run = { start = time(), est = plan.secs or 0, writs = #plan.route, rep = 0, done = 0, pv = PACE_V, idle = 0,
                      quick = plan.quick or nil, mode = plan.mine and "mine" or (WritPathNav.planChoice or "cheap"), ids = {} }
  for _, p in ipairs(plan.route) do WritPathNav.run.ids[p.w.q] = REP[p.w.tier] or 0 end
end
-- buying ends when you close the auction house
function WritPath_RunBought()
  local run = WritPathNav and WritPathNav.run
  if run and (run.done or 0) == 0 then run.boughtAt = time(); run.idle = 0 end   -- the clock starts now
end

-- the clock stops while you stand still: after 60 seconds without moving, until you move again. Not while the
-- guide has you waiting for a boat or zeppelin (that's part of the trip), and not on a flight.
local IDLE_AFTER = 60
local stillFor, idleTick, lastPos = 0, 0, nil
local function Where()
  if UnitPosition then
    local y, x, _, inst = UnitPosition("player")
    if x then return x, y, inst, 1 end   -- yards
  end
  local p = Travel and Travel.PlayerPoint and Travel.PlayerPoint()
  if p then return p.x, p.y, p.map, 0.02 end   -- zone percent
end
local function WaitingForShip()
  local route = WritPath_CurrentRoute and WritPath_CurrentRoute()
  local s = route and route[WritPathNav.step or 1]
  return s and s.done and s.done.sail
end
local function IdleTick(dt)
  local run = WritPathNav and WritPathNav.run
  if not run then stillFor, lastPos = 0, nil; return end
  local x, y, where, near = Where()
  local moved = not (x and lastPos and lastPos[3] == where and math.abs(x - lastPos[1]) <= lastPos[4] and math.abs(y - lastPos[2]) <= lastPos[4])
  if x then lastPos = { x, y, where, near } end
  if moved or (UnitOnTaxi and UnitOnTaxi("player")) or WaitingForShip() then stillFor = 0; return end
  stillFor = stillFor + dt
  if stillFor > IDLE_AFTER then run.idle = (run.idle or 0) + math.min(dt, stillFor - IDLE_AFTER) end
end
WritPath_RunIdleTick = IdleTick   -- for tests
local idleFrame = CreateFrame("Frame")
idleFrame:SetScript("OnUpdate", WritPath_Timed("run timer", function(_, e)
  idleTick = idleTick + e
  if idleTick < 1 then return end
  IdleTick(idleTick); idleTick = 0
end))
local function RunTurnin(q)
  local run = WritPathNav and WritPathNav.run
  if not (run and run.ids and run.ids[q]) then return end
  run.done = (run.done or 0) + 1
  run.rep = (run.rep or 0) + run.ids[q]
  run.last = time()
  run.idleAtLast = run.idle or 0   -- standing still after the last hand-in isn't part of the run
  run.ids[q] = nil
  if not next(run.ids) then CloseRun() end
end

function WritPath_RunReport()
  local runs = WritPathNav and WritPathNav.runs or {}
  if #runs == 0 then Print("No finished runs yet: start a route from the planner and hand its writs in."); return end
  for i = math.max(1, #runs - 9), #runs do
    local r = runs[i]
    Print(("%s  %d%s writs, %d rep%s: travel %s (planner %s, x%.2f)%s%s%s"):format(date("%m-%d %H:%M", r.start), r.done or 0,
      (r.writs and r.writs ~= r.done) and (" of " .. r.writs) or "", r.rep or 0,
      r.quick and " (Quick)" or "", FmtMin(r.travel), FmtMin(r.est), (r.est or 0) > 0 and r.travel / r.est or 0,
      r.boughtAt and (", buying " .. FmtMin(r.boughtAt - r.start)) or "",
      (r.idleAtLast or 0) >= 60 and (", " .. FmtMin(r.idleAtLast) .. " standing still left out") or "",
      Counts(r) and "" or (r.pv ~= PACE_V and " |cFFAAAAAA(older planner: not used for your pace)|r"
                                         or " |cFFAAAAAA(not finished: not used for your pace)|r")))
  end
  local pace, n = WritPath_Pace()
  Print(n >= 3 and ("Planner times are scaled x%.2f to your pace (median of your last %d runs)."):format(pace, n)
                or ("Planner times use the plain estimate until %d more runs are finished."):format(3 - n))
end

-- what still has to be bought for a plan: writs you don't have, items you're short of
local function ShoppingFor(plan)
  local list = {}
  for _, p in ipairs(plan and plan.route or {}) do
    if not p.have then list[#list + 1] = { id = p.id, name = ItemName(p.id) or ("Craftsman's Writ: " .. p.w.name), n = 1 } end
    if p.need and p.need > 0 then list[#list + 1] = { id = p.w.req, name = ItemName(p.w.req), n = p.need } end
  end
  return list
end

-- the list for the "Buy next" button at the auction house: how many of each thing the plan needs in your
-- bags (an item two writs both ask for is counted for both), with the price the plan was built on
local function BuyList(plan)
  local byId, order = {}, {}
  local function Add(id, n, name)
    if not id then return end
    local e = byId[id]
    if not e then e = { id = id, name = name, total = 0, unit = Price(id) }; byId[id] = e; order[#order + 1] = e end
    e.total = e.total + n
  end
  for _, p in ipairs(plan and plan.route or {}) do
    if not p.have then Add(p.id, 1, ItemName(p.id) or ("Craftsman's Writ: " .. p.w.name)) end
    Add(p.w.req, p.w.n or 1, ItemName(p.w.req))
  end
  local list = {}
  for _, e in ipairs(order) do if Count(e.id) < e.total then list[#list + 1] = e end end
  return list
end



---------------------------------------------------------------- room in your bags and quest log
-- A big plan can need more bag spaces and quest log slots than you have: say so in red before you buy.
local function StackOf(id, default)
  local st = C_Item and C_Item.GetItemMaxStackByID and C_Item.GetItemMaxStackByID(id)
  if not st and GetItemInfo then st = select(8, GetItemInfo(id)) end
  return (type(st) == "number" and st > 0) and st or default
end
-- the new bag spaces `extra` more of an item takes (a part stack you have fills up first)
local function NewSlots(id, extra, default)
  if extra <= 0 then return 0 end
  local have, st = Count(id), StackOf(id, default)
  return math.ceil((have + extra) / st) - math.ceil(have / st)
end
local function FreeBagSlots()
  local get = (C_Container and C_Container.GetContainerNumFreeSlots) or GetContainerNumFreeSlots
  if not get then return nil end
  local free = 0
  for bag = 0, NUM_BAG_SLOTS or 4 do
    local n, family = get(bag)
    if n and (family or 0) == 0 then free = free + n end   -- a profession bag won't take writs or crates
  end
  return free
end
local function FreeQuestSlots()
  local max = (C_QuestLog.GetMaxNumQuestsCanAccept and C_QuestLog.GetMaxNumQuestsCanAccept())
    or MAX_QUESTLOG_QUESTS or MAX_QUESTS or 20
  local quests
  if C_QuestLog.GetNumQuestLogEntries then quests = select(2, C_QuestLog.GetNumQuestLogEntries())
  elseif GetNumQuestLogEntries then quests = select(2, GetNumQuestLogEntries()) end
  if not quests then return nil end
  return math.max(0, max - quests)
end
-- bag spaces and quest log slots a plan still needs: writ scrolls you buy and the items to fill them, quests
-- you haven't accepted yet; for Favor, crates and fillings (a crate is handed in as soon as it's accepted)
local function Room(plan)
  local bags, quests, want = 0, 0, {}
  local CRATE = {}
  if plan.favor then
    for _, c in ipairs(WritPath_Crates or {}) do CRATE[c[1]] = true end
    for id, n in pairs(plan.used or {}) do want[id] = n end
  else
    for _, p in ipairs(plan.route or {}) do
      if not p.have then want[p.id] = (want[p.id] or 0) + 1 end
      if p.w.req then want[p.w.req] = (want[p.w.req] or 0) + (p.w.n or 1) end
      if not InLog(p.w.q) then quests = quests + 1 end
    end
  end
  for id, n in pairs(want) do
    local extra = (plan.favor and plan.noBags) and n or (n - Count(id))
    local writ = WritPath_Writs[id] ~= nil
    bags = bags + NewSlots(id, extra, (writ or CRATE[id]) and 1 or 20)
  end
  return bags, quests
end
local lastRoom
local function WarnRoom(plan)
  if not plan or not ((plan.route and #plan.route > 0) or (plan.picks and #plan.picks > 0)) then return end
  local bags, quests = Room(plan)
  local freeBags, freeQuests = FreeBagSlots(), FreeQuestSlots()
  local short = {}
  if freeBags and bags > freeBags then short[#short + 1] = ("%d bag spaces (you have %d free)"):format(bags, freeBags) end
  if freeQuests and quests > freeQuests then short[#short + 1] = ("%d quest log slots (you have %d free)"):format(quests, freeQuests) end
  local msg = #short > 0 and ("|cFFFF3333This plan needs " .. table.concat(short, " and ") .. "!|r") or nil
  if msg and msg ~= lastRoom then
    Print(msg)
    -- and across the middle of the screen as a raid warning (WritPath's colours, as in chat), with its sound
    if RaidNotice_AddMessage and RaidWarningFrame then
      RaidNotice_AddMessage(RaidWarningFrame, "|cff33ff99WritPath|r " .. msg, ChatTypeInfo and ChatTypeInfo["RAID_WARNING"] or { r = 1, g = 1, b = 1 })
      if PlaySound and SOUNDKIT and SOUNDKIT.RAID_WARNING then PlaySound(SOUNDKIT.RAID_WARNING) end
    end
  end
  lastRoom = msg
end


local function ShortText(plan)
  local sh = plan.short or {}
  local t = ("Short of %d: %d rep is the most you can do today (each writ once a day, only writs with a price and a known customer)."):format(plan.target, sh.max or plan.rep)
  if sh.withZone and sh.withZone > (sh.max or 0) then
    t = t .. (" Tick \"Include customers known by zone only\" to reach up to %d."):format(sh.withZone)
  end
  return t
end

local function Ago(secs)
  if secs < 3600 then return math.max(1, math.floor(secs / 60)) .. " min" end
  if secs < 2 * 86400 then return math.floor(secs / 3600) .. " h" end
  return math.floor(secs / 86400) .. " days"
end

local WhyNone
-- why nothing could be planned, counted by reason ("120 no AH price · 30 customer unknown")
function WhyNone()
  local _, skipped = Candidates(ZONE_ONLY)
  local counts, order = {}, {}
  for _, sk in ipairs(skipped) do
    local k = sk.why:gsub(" %(.*%)", ""):gsub("no AH price for .*", "no AH price for an item it asks for")
    if not counts[k] then order[#order + 1] = k end
    counts[k] = (counts[k] or 0) + 1
  end
  table.sort(order, function(a, b) return counts[a] > counts[b] end)
  local parts = {}
  for i = 1, math.min(4, #order) do parts[#parts + 1] = counts[order[i]] .. " " .. order[i] end
  if #parts == 0 then return "" end
  return "\n" .. GREY .. "Why: " .. table.concat(parts, " · ") .. ". Prices come from WritPath's own scan (Scan at the auction house) or Auctionator's.|r"
end

local function PriceAge(plan)
  local last = math.max(AuctionatorTime(), WritPath_ScanTime and WritPath_ScanTime() or 0)
  local t
  if last > 0 then
    local secs = time() - last
    t = (secs > 86400 and W_ or GREY) .. "AH " .. Ago(secs):gsub(" min", "m"):gsub(" h", "h"):gsub(" days", "d") .. "|r"
  else
    t = W_ .. "No AH scan|r"
  end
  -- prices also update from ordinary AH searches: the oldest one this plan relies on
  local api = Auctionator and Auctionator.API and Auctionator.API.v1
  local oldest
  if api and api.GetAuctionAgeByItemID then
    local function Check(id)
      local ok, days = pcall(api.GetAuctionAgeByItemID, "WritPath", id)
      if ok and type(days) == "number" and (not oldest or days > oldest) then oldest = days end
    end
    for _, p in ipairs(plan and plan.route or {}) do
      if not p.have then Check(p.id) end
      if p.need and p.need > 0 and p.w.req then Check(p.w.req) end
    end
  end
  if oldest and oldest >= 1 then
    t = t .. GREY .. " · |r" .. (oldest >= 3 and W_ or GREY) .. "oldest " .. oldest .. "d|r"
  end
  return t
end

local lastTop = -62
local function Show(plan, top)
  current, lastTop = plan, top
  WarnRoom(plan)
  ageText:SetText(PriceAge(plan))
  local y = 0
  local entries, prev = {}, plan.start
  local favorSummary, favorNote
  if plan.favor then entries, favorSummary, favorNote = WritPath_FavorView(plan) end
  for i, p in ipairs(plan.favor and {} or plan.route) do
    local tl = plan.tele and plan.tele[i]
    local leg = (prev and p.pos) and Minutes(Secs(prev, p.pos) - (tl and tl.save or 0)) or nil
    prev = p.pos or prev
    local chips = {}
    if tl then chips[#chips + 1] = { (tl.tp.text:gsub("^Use your ", ""):gsub("^Cast ", "")), "good" } end
    if p.need > 0 then chips[#chips + 1] = { "needs item", "warn" } end
    local zlo, zhi = Travel.ZoneDanger(p.c.map)   -- a zone whose mobs start well above your level
    if zlo then chips[#chips + 1] = { ("lvl %d-%d zone"):format(zlo, zhi), "danger" } end
    if not p.c.exact then chips[#chips + 1] = { "spot not exact", "bad" } end
    local BLUE = "|cFF38BDF8"
    entries[#entries + 1] = { writ = true, num = i, tier = p.w.tier and p.w.tier:sub(1, 1), name = p.w.name, chips = chips,
      sub = GREY .. (p.c.npc or "writ customer") .. " · " .. MapName(p.c.map) .. (leg and (" · ~" .. leg .. " min") or "") .. "|r",
      price = plan.mine and (p.need > 0 and (BLUE .. Coins(p.cost) .. "|r") or "") or (p.have and (GREY .. "yours|r") or (BLUE .. Coins(p.cost) .. "|r")) }
  end
  for _, l in ipairs(plan.later or {}) do entries[#entries + 1] = { W_ .. "Left out:|r " .. l.w.name .. "\n" .. GREY .. l.why .. "|r", "" } end
  for _, l in ipairs(plan.unknown or {}) do entries[#entries + 1] = { W_ .. "Not placed yet:|r " .. l.w.name .. "\n" .. GREY .. l.why .. "|r", "" } end
  local head = rowPool.head
  if plan.favor and #(plan.picks or {}) > 0 then
    local n = 0; for _, p in ipairs(plan.picks) do n = n + p.count end
    head.l:SetText(GREY .. n .. (n == 1 and " crate · " or " crates · ") .. "Merchant's Favor|r")
    head.r:SetText("|cFFFACC15" .. plan.earned .. " Favor|r")
    head:ClearAllPoints(); head:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0); head:SetWidth(LIST_W); head:Show()
    y = -22
  elseif not plan.favor and not plan.intro and #plan.route > 0 then
    local need, which = 0, plan.mine and "your writs, shortest order" or "route"
    for _, p in ipairs(plan.route) do if p.need > 0 then need = need + 1 end end
    for k, nm in pairs({ cheap = "Cheapest route", optimized = "Optimized route", fast = "Fastest route" }) do
      if plans and plans[k] == plan then which = nm end
    end
    head.l:SetText(GREY .. #plan.route .. (#plan.route == 1 and " step · " or " steps · ") .. which .. "|r")
    head.r:SetText(need > 0 and ("|cFFFACC15" .. need .. (need == 1 and " item needed|r" or " items needed|r")) or (G .. "items in your bags|r"))
    head:ClearAllPoints(); head:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0); head:SetWidth(LIST_W); head:Show()
    y = -22
  else head:Hide() end
  for i = 1, math.max(#entries, #rowPool) do
    local r = Row(i)
    if entries[i] then
      r:SetWidth(LIST_W)
      local h = r:Fill(entries[i])
      r:SetHeight(h); r:ClearAllPoints(); r:SetPoint("TOPLEFT", content, "TOPLEFT", 0, y); r:Show()
      y = y - h
    else r:Hide() end
  end

  y = y - 6
  summary:ClearAllPoints(); summary:SetPoint("TOPLEFT", content, "TOPLEFT", 0, y)
  local net = (plan.pouches or 0) - plan.cost
  if plan.intro then
    summary:SetText(plan.intro)
  elseif plan.favor then
    summary:SetText(favorSummary)
  elseif #plan.route == 0 then
    summary:SetText(W_ .. (plan.mine and (plan.owned == 0 and "No writs in your bags or quest log."
      or "None of your writs can go today: see the lines above.")
      or ("Nothing to plan: no writ with a known customer and an AH price is free today." .. WhyNone())) .. "|r")
  elseif plan.mine then
    summary:SetText(("%s%d writs today, %d rep|r · ~%d min · pouches ~%s%s"):format(G, #plan.route, plan.rep,
      Minutes(plan.secs), Coins(plan.pouches), plan.cost > 0 and (" · missing items " .. Coins(plan.cost)) or ""))
  else
    summary:SetText(("%s%d rep|r: %d yours + %d to buy · cost %s · ~%d min · net %s%s|r"):format(G, plan.rep,
      plan.ownedUsed or 0, plan.bought or 0, Coins(plan.cost), Minutes(plan.secs), net >= 0 and G or "|cFFFF5722", Coins(net))
      .. (plan.rep < plan.target and ("\n" .. W_ .. ShortText(plan) .. "|r") or ""))
  end
  y = y - summary:GetStringHeight() - 6

  local fps, own = Travel.KnownFlightPaths()
  note:ClearAllPoints(); note:SetPoint("TOPLEFT", content, "TOPLEFT", 0, y)
  local roads, ships = Travel.Learned()
  if plan.intro then note:SetText(plan.introNote or "") elseif plan.favor then note:SetText(favorNote) else
  note:SetText((plan.mine and "Shortest order from where you stand. "
    or "Prices from your last auction house scan; times are estimates. ")
    .. (select(2, WritPath_Pace()) >= 3 and ("Times are scaled to your pace (x%.2f). "):format((WritPath_Pace())) or "")
    .. ("WritPath knows %d road crossings and %d ships from your travels; more as you ride. "):format(roads, ships)
    .. (fps == 0 and "No flight paths known yet: open any flight master's map once on each continent."
     or (own >= fps and (fps .. " flight paths known.")
     or (fps .. " flight paths known (" .. (fps - own) .. " from RestedXP until you open a flight master's map on that continent)."))))
  end
  y = y - note:GetStringHeight() - 4

  -- the scroll area takes what's left of half the screen; the window is never taller than that
  local listH = -y
  content:SetHeight(listH)
  local BOTTOM = 22 + PAD + 10                          -- buttons and the gap above them
  local maxH = math.floor((UIParent:GetHeight() or 768) * 0.5)
  local viewH = math.min(listH, math.max(90, maxH + top - BOTTOM))
  -- a size you dragged it to: the window grows no taller than that (the list scrolls inside it), and shrinks
  -- to fit when there's less to show
  local size = WritPathNav and WritPathNav.plannerSize
  if size and size.h then viewH = math.min(listH, math.max(90, size.h + top - BOTTOM)) end
  scroll:ClearAllPoints(); scroll:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, top); scroll:SetSize(LIST_W, viewH)
  scroll:SetVerticalScroll(0)
  local bar = Bar()
  if bar then
    if listH > viewH + 1 then bar:Show() else bar:Hide() end
  end

  goBtn:SetText(plan.favor and "Start buying" or "Start route")
  if (plan.favor and #plan.picks > 0) or (not plan.favor and #plan.route > 0) then goBtn:Enable() else goBtn:Disable() end
  FitWidth(goBtn); FitWidth(clearBtn)
  goBtn:ClearAllPoints(); goBtn:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -PAD, PAD)
  f:SetHeight(-top + viewH + BOTTOM)
end

-- resizing: the grip in the bottom-right corner. Widths re-flow as you drag; the list is laid out again when you
-- let go, and the size is kept for next time.
local function Relayout(w)
  W = math.floor(w); INNER = W - PAD * 2; CARD_W = math.floor((INNER - CARD_GAP * 2) / 3); LIST_W = INNER - SB
  f:SetWidth(W); buyRow:SetWidth(INNER); content:SetWidth(LIST_W)
  for _, c in pairs(cards) do
    c:SetWidth(CARD_W); for _, fs in ipairs({ c.cost, c.meta, c.net }) do fs:SetWidth(CARD_W - 16) end; c.name:SetWidth(CARD_W - 26)
  end
  for _, r in ipairs(rowPool) do r:SetWidth(LIST_W) end
  summary:SetWidth(LIST_W); note:SetWidth(LIST_W)
end
f:SetResizable(true)
if f.SetResizeBounds then f:SetResizeBounds(380, 220, 1100, 1200) elseif f.SetMinResize then f:SetMinResize(380, 220); f:SetMaxResize(1100, 1200) end
local grip = CreateFrame("Button", nil, f)
grip:SetSize(16, 16); grip:SetPoint("BOTTOMRIGHT", -2, 2)
local lvl = f:GetFrameLevel(); if type(lvl) == "number" then grip:SetFrameLevel(lvl + 20) end   -- above the buttons
grip:SetNormalTexture("Interface/ChatFrame/UI-ChatIM-SizeGrabber-Up")
grip:SetHighlightTexture("Interface/ChatFrame/UI-ChatIM-SizeGrabber-Highlight")
grip:SetPushedTexture("Interface/ChatFrame/UI-ChatIM-SizeGrabber-Down")
local sizing = false
grip:SetScript("OnMouseDown", function() sizing = true; f:StartSizing("BOTTOMRIGHT") end)
grip:SetScript("OnMouseUp", function()
  f:StopMovingOrSizing(); sizing = false
  WritPathNav.plannerSize = { w = math.floor(f:GetWidth()), h = math.floor(f:GetHeight()) }
  Relayout(f:GetWidth())
  if current and (current.favor or #(current.route or {}) > 0 or current.mine) then
    if cards.cheap:IsShown() and plans and WritPath_PlannerReselect then WritPath_PlannerReselect() else Show(current, lastTop) end
  else WritPath_PlannerStart() end
end)
f:SetScript("OnSizeChanged", function(_, w) if sizing then Relayout(w) end end)
WritPath_PlannerRelayout = Relayout   -- for tests
WritPath_PlannerGrip = grip

-- the three cards, one row each: Cheapest, Optimized, Fastest; click one to see its writs
local CardText
do
local function SameWrits(a, b)
  if a == b then return true end
  if #a.route ~= #b.route then return false end
  local ids = {}; for _, p in ipairs(b.route) do ids[p.id] = true end
  for _, p in ipairs(a.route) do if not ids[p.id] then return false end end
  return true
end
local NAMES = { cheap = "Cheapest", optimized = "Optimized", fast = "Fastest" }
-- fills a card: name, gold up front, time and rep, net; the rest (labels, "same writs as") is in its tooltip
function CardText(key, plan)
  local c = cards[key]
  local tag
  if key == "optimized" and SameWrits(plan, plans.cheap) then tag = "The same writs as Cheapest."
  elseif key == "optimized" and SameWrits(plan, plans.fast) then tag = "The same writs as Fastest."
  elseif key ~= "optimized" and SameWrits(plans.cheap, plans.fast) then tag = "Cheapest and Fastest are the same writs."
  elseif plan.hubs or plan.quick then tag = "Planned by flight paths." end
  local net = plan.pouches - plan.cost
  local netC = net >= 0 and "|cFF4ADE80" or "|cFFFF5555"
  c.name:SetText(G .. NAMES[key] .. "|r")
  c.cost:SetText(Coins(plan.cost))
  c.meta:SetText(("%s~%dm · %d rep|r"):format(GREY, Minutes(plan.secs), plan.rep))
  c.net:SetText(netC .. "net " .. Coins(net) .. "|r")
  c.tip = { NAMES[key], ("Up front: %s"):format(Coins(plan.cost)), ("Time to complete: ~%d min"):format(Minutes(plan.secs)),
    ("Rep: %d"):format(plan.rep), ("Estimated net: %s (coin pouches minus what you spend)"):format(Coins(net)), tag }
end
for _, c in pairs(cards) do
  c:SetScript("OnEnter", function(self)
    if not self.tip then return end
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOM"); GameTooltip:SetText(self.tip[1])
    for i = 2, 6 do if self.tip[i] then GameTooltip:AddLine(self.tip[i], 1, 1, 1, true) end end
    GameTooltip:Show()
  end)
  c:SetScript("OnLeave", function() GameTooltip:Hide() end)
end
end

local CARDS_TOP = -60
local function LayoutCards()
  local h = 0
  for _, c in pairs(cards) do
    local ch = 7 + 5 + 3 + 3 + 9
    for _, fs in ipairs({ c.name, c.cost, c.meta, c.net }) do ch = ch + fs:GetStringHeight() end
    h = math.max(h, ch)
  end
  local prev
  for _, k in ipairs({ "cheap", "optimized", "fast" }) do
    local c = cards[k]
    c:SetHeight(h); c:ClearAllPoints()
    if prev then c:SetPoint("TOPLEFT", prev, "TOPRIGHT", CARD_GAP, 0) else c:SetPoint("TOPLEFT", PAD, CARDS_TOP) end
    prev = c
  end
  return CARDS_TOP - h - 10
end

local function Select(key)
  choice = key; WritPathNav.planChoice = key
  for k, c in pairs(cards) do
    if k == key then c.sel:Show(); c.dot:SetVertexColor(accent[1], accent[2], accent[3], 1)
    else c.sel:Hide(); c.dot:SetVertexColor(0.4, 0.4, 0.4, 1) end
  end
  Show(plans[key], LayoutCards())
end
WritPath_PlannerReselect = function() Select(choice or "cheap") end   -- the resize grip lays the cards out again
for k, c in pairs(cards) do c:SetScript("OnClick", function() Select(k) end) end
local function ShowCards(on)
  for _, c in pairs(cards) do if on then c:Show() else c:Hide() end end
  loadBar:Hide()
end
-- the loading bar: shown (with how far the plans have got) or hidden
local function Loading(p)
  if not p then loadBar:Hide(); Job.onStep = nil; return end
  loadBar:ClearAllPoints()
  loadBar:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, CARDS_TOP - 4); loadBar:SetPoint("TOPRIGHT", f, "TOPRIGHT", -PAD, CARDS_TOP - 4)
  loadBar:SetValue(p); loadBar.text:SetText(("Working out the plans... %d%%"):format(math.floor(p * 100)))
  if not loadBar:IsShown() then loadBar.XPColor() end   -- the XP bar may have been restyled since
  loadBar:Show()
end

local function Warm(plan)   -- ask the client for item names it hasn't loaded yet
  if not (C_Item and C_Item.RequestLoadItemDataByID) then return end
  for _, p in ipairs(plan.route) do pcall(C_Item.RequestLoadItemDataByID, p.id); if p.w.req then pcall(C_Item.RequestLoadItemDataByID, p.w.req) end end
end

local function DoMine()
  buyRow:ClearAllPoints(); buyRow:SetPoint("TOPLEFT", PAD, -32); buyRow:Show()
  ShowCards(false)
  WritPathNav.planMode = "mine"
  local plan = PlanOwned(nil, nil, nil, true); Warm(plan)   -- just what you can hand in now
  Show(plan, -62)
end

local function Favor() return WritPathNav and WritPathNav.planFor == "favor" end
local DoFavor
local WalkHere   -- below (walking yards): ground distances from where you stand, then a callback
local DoPlanNow
local function DoPlan(buy)
  -- with Shortest Path Forever: a rep target is planned once the ground distances from where you stand are in (a
  -- few seconds at most), not twice; the other views show at once and again when they arrive
  if WalkHere and WalkHere(function() if f:IsShown() then DoPlanNow(buy) end end) then DoPlanNow(buy, true); return end
  DoPlanNow(buy)
end
function DoPlanNow(buy, wait)   -- buy: plan for a target even if the box is empty (the last target, or 1000)
                                -- wait: a rep target waits (the ground distances are on their way)
  if Favor() then DoFavor(buy); return end
  local target = tonumber(repBox:GetText())
  if buy and not (target and target > 0) then target = WritPathNav.plan and WritPathNav.plan.target or 1000 end
  if not target or target <= 0 then DoMine(); return end   -- no target: just the writs you have
  buyRow:ClearAllPoints(); buyRow:SetPoint("TOPLEFT", PAD, -32); buyRow:Show()
  WritPathNav.planMode = "buy"
  if not HavePrices() then
    ShowCards(false)
    Show({ route = {}, start = nil, pouches = 0, cost = 0, rep = 0, target = 0, secs = 0 }, -62)
    summary:SetText(W_ .. "No prices yet: open the auction house and press \"WritPath: scan writs\" (or install Auctionator).|r"); return
  end
  local zoneOnly = ZONE_ONLY
  WritPathNav.plan = { target = target, zoneOnly = zoneOnly }
  -- worked out a few milliseconds a frame (Job): the window says so until the plans are in
  local finished = not wait and Job.Start(function() return PlanBoth(target, zoneOnly) end, function(res)
    plans = res   -- Fastest weighs the flight-path hub plan by itself
    Loading(nil)
    for _, k in ipairs({ "cheap", "optimized", "fast" }) do
      Warm(plans[k]); CardText(k, plans[k])
    end
    ShowCards(true)
    local key = WritPathNav.planChoice
    if key == "balanced" then key = "optimized" end
    Select((key == "cheap" or key == "optimized" or key == "fast") and key or "cheap")
  end)
  -- the plans for this target already showing (worked out again with fresh ground distances): they stay until the
  -- new ones are in; otherwise the window waits
  if not finished and not (plans and plans.cheap and plans.cheap.target == target) then
    plans = nil
    ShowCards(false)
    Show({ route = {}, start = nil, pouches = 0, cost = 0, rep = 0, target = 0, secs = 0 }, CARDS_TOP - 32)
    summary:SetText("")
    Loading(wait and 0 or Job.p)
    Job.onStep = Loading
  end
end
-- Merchant's Favor: the cheapest crates and fillings for a Favor target (Favor.lua)
function DoFavor(saved)   -- saved: use the last Favor target when the box is empty
  local target = tonumber(repBox:GetText())
  if not (target and target > 0) then
    if not (saved and WritPathNav.favorTarget) then WritPath_PlannerStart(); return end   -- nothing asked for yet
    target = WritPathNav.favorTarget
  end
  buyRow:ClearAllPoints(); buyRow:SetPoint("TOPLEFT", PAD, -32); buyRow:Show()
  ShowCards(false)
  WritPathNav.planMode = "favor"
  WritPathNav.favorTarget = target
  if not HavePrices() then
    Show({ favor = true, picks = {}, route = {}, earned = 0, target = target, cost = 0, back = 0, lockedOut = 0 }, -62)
    summary:SetText(W_ .. "No prices yet: open the auction house and press Scan (or install Auctionator).|r"); return
  end
  Show(WritPath_FavorPlan(target, WritPathNav.favorNoBags), -62)
end
local function SetMode(favor)
  WritPathNav.planFor = favor and "favor" or "rep"
  modeBtn:SetText(favor and "Favor" or "Rep"); FitWidth(modeBtn)
  bagsChk:SetChecked(not WritPathNav.favorNoBags)
  if favor then bagsChk:Show(); bagsL:Show() else bagsChk:Hide(); bagsL:Hide() end
  PlaceHearth()
  repBox:SetText("")   -- you type the target: nothing planned you didn't ask for
end
modeBtn:SetScript("OnClick", function()
  SetMode(not Favor())
  WritPath_PlannerStart()   -- switching never plans by itself: Plan does
end)
bagsChk:SetScript("OnClick", function(self) WritPathNav.favorNoBags = not self:GetChecked() or nil; DoPlan() end)
bagsChk:SetScript("OnEnter", function(self)
  GameTooltip:SetOwner(self, "ANCHOR_TOP"); GameTooltip:SetText("Bags")
  GameTooltip:AddLine("On: crates and materials already in your bags are used first, for free.", 1, 1, 1, true)
  GameTooltip:AddLine("Off: the plan buys everything and leaves what's in your bags alone.", 1, 1, 1, true)
  GameTooltip:Show()
end)
bagsChk:SetScript("OnLeave", function() GameTooltip:Hide() end)
WritPath_BagsCheck = bagsChk   -- for tests
if skin and skin.Checkbox and not bagsChk.wpSkinned then bagsChk.wpSkinned = true; skin.Checkbox(bagsChk) end   -- EllesmereUI skinned the window before this existed
-- the Hearthstone on or off: the shown plan (and a route under way) is planned again
function WritPath_SetHearth(on)
  WritPathChar = WritPathChar or {}
  WritPathChar.noHearth = (not on) or nil
  hearthChk:SetChecked(on)
  if WritPath_RouteActive and WritPath_RouteActive() and WritPath_RerouteNow then WritPath_RerouteNow("hearthstone " .. (on and "on" or "off"), true) end
end
hearthChk:SetScript("OnClick", function(self)
  WritPath_SetHearth(self:GetChecked() and true or false)
  DoPlan()
end)
hearthChk:SetScript("OnEnter", function(self)
  GameTooltip:SetOwner(self, "ANCHOR_TOP"); GameTooltip:SetText("Use your Hearthstone")
  GameTooltip:AddLine("On: plans may use your Hearthstone where it saves the most time.", 1, 1, 1, true)
  GameTooltip:AddLine("Off: never. Keep it for getting home. (Astral Recall and teleport spells are still used.)", 1, 1, 1, true)
  GameTooltip:Show()
end)
hearthChk:SetScript("OnLeave", function() GameTooltip:Hide() end)
WritPath_HearthCheck = hearthChk   -- for tests
if skin and skin.Checkbox and not hearthChk.wpSkinned then hearthChk.wpSkinned = true; skin.Checkbox(hearthChk) end
flyChk:SetScript("OnShow", function(self) self:SetChecked(WritPathNav and WritPathNav.autoFly and true or false) end)
flyChk:SetScript("OnClick", function(self) WritPath_SetAutoFly(self:GetChecked() and true or false) end)
flyChk:SetScript("OnEnter", function(self)
  GameTooltip:SetOwner(self, "ANCHOR_TOP"); GameTooltip:SetText("Auto-fly")
  GameTooltip:AddLine("On a \"fly from A to B\" step, talking to A's flight master takes the flight to B for you.", 1, 1, 1, true)
  GameTooltip:AddLine("Only on that step and at that flight master. Hold Shift as you talk to choose yourself.", 1, 1, 1, true)
  GameTooltip:Show()
end)
flyChk:SetScript("OnLeave", function() GameTooltip:Hide() end)
WritPath_AutoFlyCheck = flyChk
if skin and skin.Checkbox and not flyChk.wpSkinned then flyChk.wpSkinned = true; skin.Checkbox(flyChk) end
modeBtn:SetScript("OnEnter", function(self)
  GameTooltip:SetOwner(self, "ANCHOR_TOP"); GameTooltip:SetText("Plan for")
  GameTooltip:AddLine("Rep: the writs to reach a reputation target (empty: just the writs you have).", 1, 1, 1, true)
  GameTooltip:AddLine("Favor: the cheapest Waylaid Crates and fillings to earn that much Merchant's Favor.", 1, 1, 1, true)
  GameTooltip:Show()
end)
modeBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)
planBtn:SetScript("OnClick", function() DoPlan() end)
repBox:SetScript("OnEnterPressed", function(bx) bx:ClearFocus(); DoPlan() end)
closeX:SetScript("OnClick", function() f:Hide() end)

goBtn:SetScript("OnClick", function()
  if current and current.favor then
    if #current.picks > 0 then WritPath_FavorStart(current); f:Hide() end
    return
  end
  if not current or #current.route == 0 then return end
  -- planning again while a route is still under way (a bigger target, say): the same money session and run go
  -- on, so what you already spent and when you started aren't forgotten
  local again = WritPath_RouteActive and WritPath_RouteActive() and WritPathMoney and WritPathMoney.session and true or false
  WritPathNav.plannedCost = WritPathNav.plannedCost or {}
  for _, p in ipairs(current.route) do WritPathNav.plannedCost[p.w.q] = p.cost end
  -- the writs of this plan, so the route can be rebuilt without one that can't be bought
  WritPathNav.planIds, WritPathNav.dropped = {}, {}
  WritPathNav.skipWrit, WritPathNav.skipFp = nil, nil   -- a new route: nothing skipped yet
  for _, p in ipairs(current.route) do WritPathNav.planIds[p.id] = true end
  WritPath_SetRoute(Steps(current), ("Writs: %d rep"):format(current.rep),
                    ("Planned writs handed in: |cFF00FF25%d rep|r"):format(current.rep))
  WritPathNav.doneRep = current.rep   -- the last line shows the rep really handed in against this
  if again then
    local s = WritPathMoney.session
    s.cost, s.rep = (s.spent or 0) + current.cost, current.rep   -- planned: spent so far plus what's left to buy
    if WritPath_MoneyUpdate then WritPath_MoneyUpdate() end
  elseif WritPath_StartMoneySession then WritPath_StartMoneySession(current.cost, current.rep) end
  if WritPath_SetShopList then WritPath_SetShopList(BuyList(current)) end
  local run = WritPathNav.run
  if again and run then
    local done = run.done or 0
    run.est = (current.secs or 0) + (run.boughtAt and math.max(0, time() - run.boughtAt - (run.idle or 0)) or 0)
    run.writs, run.ids = #current.route + done, {}
    for _, p in ipairs(current.route) do run.ids[p.w.q] = REP[p.w.tier] or 0 end
  else
    StartRun(current)
  end
  f:Hide()
  Print(("Route set: %d writs, %d rep, ~%d min."):format(#current.route, current.rep, Minutes(current.secs))
        .. (current.later and #current.later > 0 and (" " .. #current.later .. " left out.") or ""))
end)

-- Clear everything a plan set up: the guide's route, the money session, the buy list at the auction house and the
-- planner itself (and an old "WritPath" list in Auctionator, from when WritPath made one). What WritPath has learned stays.
local function EmptyAuctionatorList()
  local api = Auctionator and Auctionator.API and Auctionator.API.v1
  if not (api and api.GetShoppingListItems and api.DeleteShoppingListItem) then return end
  local ok, items = pcall(api.GetShoppingListItems, "WritPath", "WritPath")
  if not (ok and type(items) == "table") then return end   -- no such list
  for i = #items, 1, -1 do pcall(api.DeleteShoppingListItem, "WritPath", "WritPath", items[i]) end
end
function WritPath_ClearAll()
  CloseRun("cleared")
  if WritPath_SetRoute then WritPath_SetRoute(nil) end
  if WritPath_StartMoneySession then WritPath_StartMoneySession(nil) end
  if WritPath_SetShopList then WritPath_SetShopList(nil) end
  WritPathNav.shopAt, WritPathNav.plannedCost = nil, {}
  WritPathNav.plan, WritPathNav.planChoice = nil, nil
  WritPathNav.planIds, WritPathNav.dropped = nil, nil
  EmptyAuctionatorList()
  current, plans, choice = nil, nil, nil
  repBox:SetText("")
  WritPath_PlannerStart("Cleared.")
  Print("Route and plan cleared.")
end
-- the planner with nothing planned yet: what to do, for the mode it's in
function WritPath_PlannerStart(first)
  ShowCards(false)
  buyRow:ClearAllPoints(); buyRow:SetPoint("TOPLEFT", PAD, -32); buyRow:Show()
  repBox:SetText("")
  local H = "|cFFFFD100"
  local intro, introNote
  if WritPathNav and WritPathNav.planFor == "favor" then
    local NL = string.char(10)
    intro = ((first and (G .. first .. "|r ") or "") .. H .. "Plan Merchant's Favor|r" .. NL
      .. "1. At the auction house, press " .. H .. "Scan|r (the WritPath Scanner panel) so prices are fresh." .. NL
      .. "2. Type how much Favor you want and press " .. H .. "Plan|r. Untick " .. H .. "Bags|r to buy everything." .. NL
      .. "3. Press " .. H .. "Start buying|r: the shopping list opens at the auction house. Fill each crate (right-click it)"
      .. " and talk to Dokimi at the camp west of the Crossroads to hand them in.")
    introNote = GREY .. "Click Favor to switch back to planning writs for reputation.|r"
  else
    local NL = string.char(10)
    intro = ((first and (G .. first .. "|r ") or "") .. H .. "Plan writs|r" .. NL
      .. "1. At the auction house, press " .. H .. "Scan|r (the WritPath Scanner panel) so prices are fresh." .. NL
      .. "2. Type a rep target and press " .. H .. "Plan|r. Leave it empty to plan just the writs you already have." .. NL
      .. "3. Pick " .. H .. "Cheapest|r or " .. H .. "Fastest|r and press " .. H .. "Start route|r: the shopping list opens at the"
      .. " auction house, and the guide takes you to each customer.")
    introNote = GREY .. "Click Rep to plan Merchant's Favor instead (the cheapest Waylaid Crates).|r"
  end
  Show({ route = {}, start = nil, pouches = 0, cost = 0, rep = 0, target = 0, secs = 0, intro = intro, introNote = introNote }, -62)
  current = nil   -- nothing planned: reopening the planner shows this again
end
-- WritPath's own confirm window. Not Blizzard's StaticPopup: an addon using those shared popups taints them,
-- and the next protected thing Blizzard does with one gets blocked and blamed on WritPath.
local confirm
local function Confirm()
  if confirm then return confirm end
  local W = 300
  confirm = CreateFrame("Frame", "WritPathConfirm", UIParent, "BackdropTemplate")
  -- above every other window (the planner is a dialog too), with a solid background behind its text
  confirm:SetWidth(W); confirm:SetPoint("CENTER", 0, 120); confirm:SetFrameStrata("FULLSCREEN_DIALOG"); confirm:SetToplevel(true)
  local bg = confirm:CreateTexture(nil, "BACKGROUND", nil, -8); bg:SetAllPoints(); bg:SetColorTexture(0.06, 0.06, 0.07, 1)
  confirm:EnableMouse(true); confirm:SetClampedToScreen(true); confirm:Hide()
  tinsert(UISpecialFrames, "WritPathConfirm")   -- Escape answers No
  local msg = confirm:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  msg:SetWidth(W - 24); msg:SetWordWrap(true); msg:SetJustifyH("CENTER"); msg:SetPoint("TOP", 0, -14)
  msg:SetText("Clear the WritPath route, the planner and its shopping list?\n\n" .. GREY
    .. "What WritPath has learned about customers and roads stays.|r")
  local yes = CreateFrame("Button", nil, confirm, "UIPanelButtonTemplate"); yes:SetSize(110, 22); yes:SetText(YES or "Yes")
  local no = CreateFrame("Button", nil, confirm, "UIPanelButtonTemplate"); no:SetSize(110, 22); no:SetText(NO or "No")
  yes:SetPoint("TOPRIGHT", msg, "BOTTOM", -4, -12); no:SetPoint("TOPLEFT", msg, "BOTTOM", 4, -12)
  yes:SetScript("OnClick", function() confirm:Hide(); WritPath_ClearAll() end)
  no:SetScript("OnClick", function() confirm:Hide() end)
  confirm:SetHeight(14 + msg:GetStringHeight() + 12 + 22 + 14)
  if skin then
    skin.Shell(confirm); skin.Button(yes); skin.Button(no); skin.Font(msg)
    if skin.StateButtonLabel then skin.StateButtonLabel(yes); skin.StateButtonLabel(no) end
  else
    local flat = { bgFile = "Interface/BUTTONS/WHITE8X8", edgeFile = "Interface/BUTTONS/WHITE8X8", edgeSize = 1 }
    confirm:SetBackdrop(flat); confirm:SetBackdropColor(0.06, 0.06, 0.07, 0.97); confirm:SetBackdropBorderColor(0, 0, 0, 1)
  end
  return confirm
end
function WritPath_AskClear() local c = Confirm(); c:Show(); c:Raise() end
WritPath_PlannerInternals_Confirm = function() return confirm end   -- for tests
clearBtn:SetScript("OnClick", WritPath_AskClear)

function WritPath_OpenPlanner(mode)   -- mode: "mine" (just your writs), "buy" (the last rep target), or nil
  if WritPath_WalkPrefetch then WritPath_WalkPrefetch() end   -- walking yards still to work out: start on them
  local o = WritPathNav.plan
  if mode == "mine" then repBox:SetText("")
  elseif o and (mode == "buy" or WritPathNav.planMode ~= "mine") then repBox:SetText(o.target) end
  if mode == "favor" then WritPathNav.planFor = "favor" elseif mode then WritPathNav.planFor = "rep" end
  SetMode(Favor())
  if not Favor() then
    if mode == "mine" then repBox:SetText("")
    elseif o and (mode == "buy" or WritPathNav.planMode ~= "mine") then repBox:SetText(o.target) end
  end
  FitWidth(planBtn)
  local size = WritPathNav.plannerSize
  if size and size.w then Relayout(size.w) end
  f:Show()
  -- nothing planned yet this session and no particular view asked for: say what to do, don't plan by itself
  if not mode and not current then WritPath_PlannerStart(); return end
  DoPlan(mode == "buy" or mode == "favor")
end
-- something new was learned (a customer's spot or name): an open planner shows it straight away
function WritPath_PlannerLearned()
  if f:IsShown() then
    DoPlan(WritPathNav.planMode == "buy")
  end
end

function WritPath_TogglePlanner(mode)
  if f:IsShown() then f:Hide() else WritPath_OpenPlanner(mode) end
end


---------------------------------------------------------------- events
local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:RegisterEvent("QUEST_ACCEPTED")
ev:RegisterEvent("QUEST_DETAIL")        -- a writ opened from your bags: accept it for you
ev:RegisterEvent("QUEST_COMPLETE")      -- the reward window: you're at the customer
ev:RegisterEvent("QUEST_PROGRESS")
ev:RegisterEvent("GOSSIP_SHOW")         -- talking to a customer: open the writ you can hand in
ev:RegisterEvent("QUEST_GREETING")
ev:RegisterEvent("QUEST_TURNED_IN")
ev:RegisterEvent("TAXIMAP_OPENED")
ev:SetScript("OnEvent", WritPath_Timed("planner events", function(_, event, a1)
  -- the camp's crate takers: every finished quest handed in there (Sealed crates, the camp's own quests)
  local CAMP = { ["Dokimi"] = true, ["Marcy Baker"] = true }
  local function AtCamp() local n = UnitName and (UnitName("npc") or UnitName("target")); return n and CAMP[n] or false end
  local function CrateTitle(t) return t and (t:find("Crate") or t:find("Shipping Container")) and true or false end
  if event == "QUEST_COMPLETE" or event == "QUEST_PROGRESS" then
    NoteTurnin()   -- first: who you're handing in to, and where
    -- hand a writ in for you: "Continue" on the progress page, then the reward (a writ has no reward choice;
    -- if one ever does, you choose). /writs accept turns this off with the auto-accept.
    if WritPathNav and WritPathNav.noAutoAccept then return end
    local q = GetQuestID and GetQuestID()
    if not ((q and q > 0 and WritPath_IsWritQuest(q)) or AtCamp()) then return end
    if event == "QUEST_PROGRESS" then
      if IsQuestCompletable and IsQuestCompletable() and CompleteQuest then CompleteQuest() end
    elseif GetQuestReward and (not GetNumQuestChoices or GetNumQuestChoices() <= 1) then
      GetQuestReward(1)
    end
    return
  end
  if event == "GOSSIP_SHOW" or event == "QUEST_GREETING" then
    -- a customer's window lists quests: open a finished writ (talk again for the next one)
    if WritPathNav and WritPathNav.noAutoAccept then return end
    if event == "GOSSIP_SHOW" and C_GossipInfo and C_GossipInfo.GetActiveQuests then
      local camp = AtCamp()
      for _, info in ipairs(C_GossipInfo.GetActiveQuests() or {}) do
        if info.isComplete and info.questID and (camp or WritPath_IsWritQuest(info.questID)) then
          C_GossipInfo.SelectActiveQuest(info.questID); return
        end
      end
    elseif event == "QUEST_GREETING" and GetNumActiveQuests and GetActiveQuestID then
      local camp = AtCamp()
      for i = 1, GetNumActiveQuests() do
        local q = GetActiveQuestID(i)
        local done = IsActiveQuestCompleted == nil or IsActiveQuestCompleted(i)   -- missing on some clients: try anyway
        if q and (camp or WritPath_IsWritQuest(q)) and done then SelectActiveQuest(i); return end
      end
    end
    return
  end
  if event == "QUEST_DETAIL" then
    -- only Craftsman's Writs, never other quests; /writs accept turns this off and on
    if WritPathNav and WritPathNav.noAutoAccept then return end
    local q = GetQuestID and GetQuestID()
    local title = GetTitleText and GetTitleText()
    if q and q > 0 and (WritPath_IsWritQuest(q) or CrateTitle(title)) and AcceptQuest then AcceptQuest() end
    return
  end
  if event == "QUEST_TURNED_IN" then
    LearnTurnin(a1)
    RunTurnin(a1)
    local q = a1
    C_Timer.After(1.5, function() if WritPath_RerouteFromHere then WritPath_RerouteFromHere(q) end end)
    return
  end
  if event == "TAXIMAP_OPENED" then
    local n = Travel.RecordFlightPaths()
    if n and n > 0 then
      Print(("Recorded %d flight paths for route planning."):format(n))
      C_Timer.After(0.5, function() WritPath_RerouteNow("new flight paths") end)
    end
  elseif event == "PLAYER_LOGIN" then
    WritPathLearned = WritPathLearned or {}
    C_Timer.After(1, PlainLook)
    C_Timer.After(5, Learn)
  else
    C_Timer.After(1, Learn)   -- the map pin appears a moment after accepting
  end
end))

-- for Money.lua at a turn-in: name, tier and cost of a writ quest. The cost is what you paid at the auction
-- house for this writ and its items (each unit used once), else what the plan expected.
local function TakePaid(id, n)
  local p = WritPathNav and WritPathNav.paidFor and WritPathNav.paidFor[id]
  if not (p and p.qty > 0) then return nil end
  local take = math.min(n, p.qty)
  local c = p.paid / p.qty * take
  p.qty, p.paid = p.qty - take, p.paid - c
  return c * n / take
end
local writQuests
function WritPath_IsWritQuest(q)
  if not writQuests then writQuests = {}; for _, w in pairs(DB) do if w.q then writQuests[w.q] = true end end end
  return writQuests[q] or false
end

function WritPath_WritByQuest(q)
  for id, w in pairs(DB) do
    if w.q == q then
      -- what the writ and its item cost: what you paid at the auction house, else today's price (an estimate:
      -- bought elsewhere, or already in your bags)
      local n = w.n or 1
      local writ, item = TakePaid(id, 1), w.req and TakePaid(w.req, n)
      local est = false
      if not writ then writ = Price(id); est = true end
      if not item and w.req then local u = Price(w.req, n); item = u and u * n; est = true end
      local cost
      if writ or item then cost = math.floor((writ or 0) + (item or 0) + 0.5)
      else cost = WritPathNav and WritPathNav.plannedCost and WritPathNav.plannedCost[q] end
      return w.name, w.tier, cost, writ and math.floor(writ + 0.5), item and math.floor(item + 0.5), est
    end
  end
end

-- After buying: the route is rebuilt from the writs and items you actually have (bags and mail), so a writ
-- that wasn't bought drops out, an item you're still missing shows up as a shopping step, and the shopping
-- list keeps only what that route needs. Called when you close the auction house.
-- The rest of the trip, worked out again from where you stand with everything WritPath knows now: after each
-- hand-in (q = the quest just handed in), and whenever you gain a flight path. Only the writs still on the
-- route are used, the remaining customers go in the best order from here, and a "learn the flight path" step
-- still ahead of you is kept.
local function Sig(list, from)   -- the next few steps, as text, to tell whether a re-plan changes anything
  local t = {}
  for i = from, math.min(#list, from + 2) do t[#t + 1] = table.concat(list[i].lines or {}, "|") end
  return table.concat(t, "#")
end
local function Reroute(q, why, quiet)
  if not (WritPathNav and WritPathNav.route and #WritPathNav.route > 0) then return end
  local left, onRoute, keep = {}, q == nil, nil
  for i, st in ipairs(WritPathNav.route) do
    if st.writ and DB[st.writ] then
      if q and DB[st.writ].q == q then
        onRoute = true
        local nxt = WritPathNav.route[i + 1]
        if nxt and nxt.done and nxt.done.taxiMap then keep = nxt end
      elseif not Done(DB[st.writ].q) and not (WritPathNav.skipWrit and WritPathNav.skipWrit[st.writ]) then
        left[st.writ] = true   -- a writ you ticked off stays off
      end
    end
  end
  if not onRoute or not next(left) then return end
  -- once you've left the auction house, a writ still missing its item comes off the route (it's listed as waiting)
  local past = (WritPathNav.step or 1) > 1
  local plan = PlanOwned(left, q, nil, past)
  if #plan.route == 0 then return end
  local steps = Steps(plan)
  if keep then table.insert(steps, 2, keep) end
  -- a quiet re-plan (on entering a zone) leaves the route alone when the way ahead comes out the same
  if quiet and Sig(steps, 2) == Sig(WritPathNav.route, WritPathNav.step or 1) then return end
  WritPath_SetRoute(steps, WritPathNav.title, WritPathNav.doneText)
  -- you'd already left the auction house: the new route doesn't send you back to its "buy" step (an item still
  -- missing shows at that writ's customer step instead)
  if past and steps[1] and steps[1].done and steps[1].done.ready then
    WritPathNav.manual[1] = true
    if WritPath_Refresh then WritPath_Refresh() end
  end
  local nxt = plan.route[1]
  local waiting = {}
  for _, l in ipairs(plan.later or {}) do if l.why:find("^needs its item") then waiting[#waiting + 1] = l.w.name end end
  Print(("Rerouted from here%s: next %s (%s), %d writs left, ~%d min.%s"):format(why and (" (" .. why .. ")") or "",
    nxt.w.name, nxt.c.npc or MapName(nxt.c.map), #plan.route, math.floor((plan.secs or 0) / 60 + 0.5),
    #waiting > 0 and (" Left out until you have the item: " .. table.concat(waiting, ", ") .. ".") or ""))
end
Reroute = WritPath_Timed("replanning", Reroute)
-- with Shortest Path Forever, the ground distances from where you stand come first (a few seconds at most)
local function RerouteGround(q, why, quiet)
  if not (WalkHere and WalkHere(function() Reroute(q, why, quiet) end)) then Reroute(q, why, quiet) end
end
function WritPath_RerouteFromHere(q) RerouteGround(q) end
function WritPath_RerouteNow(why, quiet) RerouteGround(nil, why, quiet) end

-- entering a new zone: plan the rest of the trip again (at most every 20 seconds, never in the air)
local lastZoneReplan = 0
local zoneWatch = CreateFrame("Frame")
zoneWatch:RegisterEvent("ZONE_CHANGED_NEW_AREA")
zoneWatch:SetScript("OnEvent", function()
  C_Timer.After(2, function()
    if WritPath_Open(UnitOnTaxi, "player") or GetTime() - lastZoneReplan < 20 then return end
    lastZoneReplan = GetTime()
    RerouteGround(nil, "new zone", true)
  end)
end)

function WritPath_ReplanFromBags()
  if not (WritPathNav and WritPathNav.route and #WritPathNav.route > 0) then return end
  if WritPath_RouteActive and not WritPath_RouteActive() then return end   -- a finished route stays finished
  local before = {}
  for _, st in ipairs(WritPathNav.route) do if st.writ then before[st.writ] = true end end
  -- writs dropped from the plan (nothing to buy for them) stay out, even if you have them
  local gone = {}
  for id in pairs(WritPathNav.dropped or {}) do gone[id] = true end
  for id in pairs(WritPathNav.skipWrit or {}) do gone[id] = true end   -- and the ones you ticked off
  local only
  if next(gone) then only = {}; for id in pairs(DB) do if not gone[id] then only[id] = true end end end
  local plan = PlanOwned(only)
  local after, short, dropped, added = {}, {}, {}, {}
  for _, p in ipairs(plan.route) do
    after[p.id] = true
    if p.need and p.need > 0 then short[#short + 1] = p.w.name end
  end
  for id in pairs(before) do if not after[id] and DB[id] then dropped[#dropped + 1] = DB[id].name end end
  for id in pairs(after) do if not before[id] then added[#added + 1] = DB[id].name end end
  if #dropped == 0 and #added == 0 and #short == 0 then
    Print("You have every writ and item the route needs.")
    return
  end
  table.sort(dropped); table.sort(added); table.sort(short)
  WritPath_SetRoute(Steps(plan), ("Writs: %d rep"):format(plan.rep), ("Planned writs handed in: |cFF00FF25%d rep|r"):format(plan.rep))
  if WritPathMoney and WritPathMoney.session then WritPathMoney.session.rep = plan.rep end
  -- the run times the writs that are actually on the route now
  local run = WritPathNav.run
  if run and run.ids then
    local onRoute = {}
    for _, p in ipairs(plan.route) do onRoute[p.w.q] = REP[p.w.tier] or 0 end
    run.ids, run.est = onRoute, plan.secs or run.est
  end
  local needed = {}
  for _, e in ipairs(BuyList(plan)) do needed[e.id] = e end
  if WritPath_PruneShopList then WritPath_PruneShopList(needed) end
  if WritPath_MoneyUpdate then WritPath_MoneyUpdate() end
  local msg = ("Route rebuilt from what you bought: %d writs, %d rep, ~%d min."):format(#plan.route, plan.rep, math.floor((plan.secs or 0) / 60 + 0.5))
  if #dropped > 0 then msg = msg .. " Dropped (writ not bought): " .. table.concat(dropped, ", ") .. "." end
  if #short > 0 then msg = msg .. " Still missing the item for: " .. table.concat(short, ", ") .. " (on the shopping list)." end
  if #added > 0 then msg = msg .. " Added (writs you have): " .. table.concat(added, ", ") .. "." end
  if plan.later and #plan.later > 0 then msg = msg .. " " .. #plan.later .. " writs left out (see the planner)." end
  Print(msg)
end

-- A writ, or the item it asks for, isn't on the auction house (or was skipped at the shopping list): the
-- route is rebuilt without that writ, and the plan's cost, rep and time follow.
function WritPath_DropFromPlan(ids, why)
  local ids0 = WritPathNav and WritPathNav.planIds
  if not (ids0 and WritPathNav.route and #WritPathNav.route > 0) then return end
  WritPathNav.dropped = WritPathNav.dropped or {}
  local names, saved = {}, 0
  for _, id in ipairs(ids or {}) do
    if ids0[id] and not WritPathNav.dropped[id] then
      WritPathNav.dropped[id] = true
      names[#names + 1] = DB[id] and DB[id].name or tostring(id)
      local q = DB[id] and DB[id].q
      saved = saved + (q and WritPathNav.plannedCost and WritPathNav.plannedCost[q] or 0)
    end
  end
  if #names == 0 then return end
  local keep = {}
  for id in pairs(ids0) do if not WritPathNav.dropped[id] then keep[id] = true end end
  local plan = PlanOwned(keep, nil, true)
  -- below the rep target while still shopping: plan again (same choice, Cheapest or Fastest) to stay at or over
  -- it; what you've bought stays in, the dropped writs stay out
  local target = WritPathNav.plan and WritPathNav.plan.target
  local added, addedCost = {}, 0
  if target and plan.rep < target and (WritPathNav.step or 1) <= 1 then
    local ok, plans = pcall(PlanBoth, target, ZONE_ONLY)
    local new = ok and Chosen(plans, WritPathNav.planChoice or "cheap")
    if new and new.rep > plan.rep then
      plan = new
      WritPathNav.plannedCost = WritPathNav.plannedCost or {}
      local ids = {}
      for _, p in ipairs(plan.route) do
        ids[p.id] = true
        if not ids0[p.id] then
          added[#added + 1] = p.w.name; addedCost = addedCost + (p.cost or 0)
          WritPathNav.plannedCost[p.w.q] = p.cost
        end
      end
      for id in pairs(WritPathNav.dropped) do ids[id] = nil end
      -- writs the new plan left out come off the planned cost too, not just the dropped ones
      for id in pairs(ids0) do
        local q = DB[id] and DB[id].q
        if not ids[id] and not WritPathNav.dropped[id] and q and WritPathNav.plannedCost then saved = saved + (WritPathNav.plannedCost[q] or 0) end
      end
      WritPathNav.planIds = ids
    end
  end
  WritPath_SetRoute(Steps(plan), ("Writs: %d rep"):format(plan.rep), ("Planned writs handed in: |cFF00FF25%d rep|r"):format(plan.rep))
  local s = WritPathMoney and WritPathMoney.session
  if s then s.rep = plan.rep; s.cost = math.max(0, (s.cost or 0) - saved + addedCost) end
  local run = WritPathNav.run
  if run and run.ids then
    local onRoute = {}
    for _, p in ipairs(plan.route) do onRoute[p.w.q] = REP[p.w.tier] or 0 end
    run.ids, run.est = onRoute, plan.secs or run.est
  end
  local needed = {}
  for _, e in ipairs(BuyList(plan)) do needed[e.id] = e end
  if WritPath_PruneShopList then WritPath_PruneShopList(needed) end
  if WritPath_MoneyUpdate then WritPath_MoneyUpdate() end
  table.sort(names)
  table.sort(added)
  Print(("Dropped from the plan (%s): %s.%s Route now %d writs, %d rep, ~%d min."):format(why or "skipped",
    table.concat(names, ", "), #added > 0 and (" Added to stay at your target: " .. table.concat(added, ", ") .. ".") or "",
    #plan.route, plan.rep, Minutes(plan.secs or 0)))
end

-- exposed for the test harness
---------------------------------------------------------------- walking yards (Shortest Path Forever, 1.16.2)
-- With Shortest Path Forever installed, the real walking yards between writ customers are worked out in the
-- background, one customer at a time (its EstimateWalks: one search from a customer to every other customer within
-- WALK_REACH yards), and saved in WritPathWalks, where Travel.Time uses them. Done once; again only for customers
-- not worked out yet, or all of them when its walking data changes. Its searches run on its own frame budget.
local WALK_OWNER = "WritPath planner"
local WALK_REACH = 2500   -- yards: further apart than this, a flight, a road or a ship is the way anyway
local WALK_RETRY = 30     -- seconds before trying again when it's busy (combat, loading)
local walkBusy = false
local function WalkAPI()
  local api = ShortestPathForever and ShortestPathForever.API
  if type(api) == "table" and (api.version == 1 or api.version == 2) and type(api.EstimateWalks) == "function"
     and type(api.NavVersion) == "function" then return api end
end
local function WalkStore(api)
  WritPathWalks = type(WritPathWalks) == "table" and WritPathWalks or {}
  local W = WritPathWalks
  local ok, v = pcall(api.NavVersion)
  v = ok and tostring(v) or "?"
  if W.v ~= v then W.v, W.rows, W.skip = v, {}, {} end   -- new walking data: work everything out again
  W.rows, W.skip = W.rows or {}, W.skip or {}
  return W
end
-- the next customer with walks still to work out, and the customers to work them out to
local function WalkNext(W)
  local spots, seen = {}, {}
  for id in pairs(DB) do
    local c = Customer(id)
    local p = c and c.exact and Pos(c.map, c.x, c.y)
    if p and p.wx then
      local k = Travel.WalkKey(p)
      if not seen[k] then seen[k] = true; spots[#spots + 1] = { p = p, k = k } end
    end
  end
  table.sort(spots, function(x, y) return x.k < y.k end)   -- the same order every time
  for _, a in ipairs(spots) do
    if not W.skip[a.k] then
      local row = W.rows[a.k]
      local to = {}
      for _, b in ipairs(spots) do
        if b.k ~= a.k and b.p.inst == a.p.inst and math.sqrt((a.p.wx - b.p.wx) ^ 2 + (a.p.wy - b.p.wy) ^ 2) <= WALK_REACH
           and not (row and row[b.k] ~= nil) and not (W.rows[b.k] and W.rows[b.k][a.k] ~= nil) and #to < 256 then
          to[#to + 1] = b
        end
      end
      if #to > 0 then return a, to end
    end
  end
end
local walkNew = false   -- distances saved since the last time the work ran out
local function Prefetch()
  if walkBusy then return end
  local api = WalkAPI(); if not api then return end
  local W = WalkStore(api)
  local a, to = WalkNext(W)
  if not a then
    -- all worked out: a plan made before they were here is made again with them (quietly: the route only changes
    -- if the way ahead does), and an open planner shows its plan again
    if walkNew then
      walkNew = false
      if WritPath_RouteActive and WritPath_RouteActive() then WritPath_RerouteNow("ground distances", true) end
      if f:IsShown() then DoPlan(WritPathNav.planMode == "buy") end
    end
    return
  end
  local targets = {}
  for i, b in ipairs(to) do targets[i] = { map = b.p.map, x = b.p.x / 100, y = b.p.y / 100 } end
  walkBusy = true
  local ok, cancel, why = pcall(api.EstimateWalks, WALK_OWNER, { map = a.p.map, x = a.p.x / 100, y = a.p.y / 100 }, targets,
    function(costs, reason)
      walkBusy = false
      if WritPathWalks ~= W then return end   -- the store was replaced meanwhile
      if reason or type(costs) ~= "table" then
        W.skip[a.k] = tostring(reason or "error")   -- this spot isn't on its walking map: don't ask again
      else
        local row = W.rows[a.k] or {}; W.rows[a.k] = row
        for i, b in ipairs(to) do
          local c = costs[i]
          if type(c) == "number" then row[b.k] = math.floor(c + 0.5) elseif c == false then row[b.k] = false end
        end
        walkNew = true
      end
      C_Timer.After(0.5, function() WritPath_WalkPrefetch() end)   -- the next customer
    end)
  if ok and type(cancel) == "function" then return end
  walkBusy = false
  local reason = ok and why or "error"
  if reason == "combat" or reason == "loading" then C_Timer.After(WALK_RETRY, function() WritPath_WalkPrefetch() end)
  else W.skip[a.k] = tostring(reason); C_Timer.After(0.5, function() WritPath_WalkPrefetch() end) end
end
WritPath_WalkPrefetch = WritPath_Timed("walking yards", Prefetch)

-- From where you stand: one search to the writ customers within HERE_REACH, just before a plan or a replan, so its
-- first leg is timed by the ground way too. done() runs when the answer is in, or after HERE_WAIT seconds at most.
-- Returns false (and doesn't call done) when there's nothing to ask: no Shortest Path Forever, or asked from this
-- spot within the last HERE_FRESH seconds.
local HERE_OWNER, HERE_REACH, HERE_WAIT, HERE_FRESH = "WritPath here", 4000, 4, 60
local hereAt
WalkHere = function(done)
  local api = WalkAPI()
  local p = api and PlayerPos()
  if not (p and p.wx) then return false end
  if hereAt and GetTime() - hereAt.t < HERE_FRESH and hereAt.p.inst == p.inst
     and math.sqrt((hereAt.p.wx - p.wx) ^ 2 + (hereAt.p.wy - p.wy) ^ 2) <= 30 then return false end
  local list, seen = {}, {}
  for id in pairs(DB) do
    local c = Customer(id)
    local q = c and c.exact and Pos(c.map, c.x, c.y)
    if q and q.wx and q.inst == p.inst then
      local k = Travel.WalkKey(q)
      local d = math.sqrt((q.wx - p.wx) ^ 2 + (q.wy - p.wy) ^ 2)
      if not seen[k] and d <= HERE_REACH then seen[k] = true; list[#list + 1] = { q = q, k = k, d = d } end
    end
  end
  if #list == 0 then return false end
  table.sort(list, function(x, y) return x.d < y.d end)
  local targets = {}
  for i = 1, math.min(256, #list) do targets[i] = { map = list[i].q.map, x = list[i].q.x / 100, y = list[i].q.y / 100 } end
  local finished = false
  local function Finish() if not finished then finished = true; done() end end
  hereAt = { p = p, t = GetTime() }   -- asked from here: not again for a minute, answer or not
  local ok, cancel = pcall(api.EstimateWalks, HERE_OWNER, { map = p.map, x = p.x / 100, y = p.y / 100 }, targets,
    function(costs, reason)
      if not reason and type(costs) == "table" then
        local rows = {}
        for i = 1, #targets do
          local c = costs[i]
          if type(c) == "number" then rows[list[i].k] = math.floor(c + 0.5) elseif c == false then rows[list[i].k] = false end
        end
        Travel.SetHere(p, rows)
      end
      Finish()
    end)
  if not (ok and type(cancel) == "function") then hereAt = nil; return false end
  C_Timer.After(HERE_WAIT, Finish)   -- a plan isn't held up for long
  return true
end
local walkLogin = CreateFrame("Frame")
walkLogin:RegisterEvent("PLAYER_LOGIN")
walkLogin:SetScript("OnEvent", function() C_Timer.After(60, function() WritPath_WalkPrefetch() end) end)

WritPath_PlannerInternals = { Job = Job, Shown = function() return current end, LearnTurnin = LearnTurnin, NoteTurnin = NoteTurnin, BuyList = BuyList, PriceAgeText = function() return PriceAge(current) end, Scroll = scroll, Content = content, ApplySkin = ApplySkin, PlainLook = PlainLook, PlanBoth = PlanBoth, ShoppingFor = ShoppingFor, Plan = Plan, PlanOwned = PlanOwned, BestOrder = BestOrder, Steps = Steps, TravelSteps = TravelSteps, Travel = Travel, Customer = Customer, Candidates = Candidates, Learn = Learn, Room = Room, WarnRoom = WarnRoom }

WritPath_PlannerInternals.StartRun, WritPath_PlannerInternals.RunTurnin = StartRun, RunTurnin   -- for tests
WritPath_PlannerInternals.Go = function(plan) current = plan; local h = rawget(goBtn, "_s_OnClick") or goBtn:GetScript("OnClick"); h(goBtn) end
WritPath_ReplanFromBags = WritPath_Timed("replanning (bags)", WritPath_ReplanFromBags)

---------------------------------------------------------------- map pins (1.18.0)
-- A map pin you drop yourself becomes a route: the same travel steps a writ route gets (roads, flights, boats,
-- danger warnings), then the pin, and the arrow leads you there. A writ route in progress wins: a pin dropped then
-- is left alone. Clearing the pin clears its route, and a new pin replaces it. WritPath's own pins (the next road
-- waypoint, set as you go) are told apart by being on the route. /writs pins turns it off (WritPathNav.noPins).
-- (no locals of its own here: Planner.lua's main chunk is at Lua's 200-local limit)
WritPath_PlannerInternals.PinRoute = function()
  if not WritPathNav or WritPathNav.noPins then return end
  local wp = C_Map.GetUserWaypoint and C_Map.GetUserWaypoint()
  if not wp then   -- cleared: its route goes too
    if WritPathNav.pinRoute then WritPath_SetRoute(nil) end
    return
  end
  if not wp.position then return end
  local map, x, y = wp.uiMapID, wp.position.x * 100, wp.position.y * 100
  for _, s in ipairs(WritPath_CurrentRoute and WritPath_CurrentRoute() or {}) do   -- WritPath's own pin: on the route
    for _, g in ipairs(s.way or {}) do
      if g[1] == map and math.abs(g[2] - x) < 0.3 and math.abs(g[3] - y) < 0.3 then return end
    end
    if s.at and s.at[1] == map and math.abs(s.at[2] - x) < 0.3 and math.abs(s.at[3] - y) < 0.3 then return end
  end
  if not WritPathNav.pinRoute and WritPath_RouteActive() then return end  -- a writ route in progress wins
  if Travel.IsContinent(map) then                                         -- dropped on the continent map
    local z, zx, zy = Travel.Place(map, x / 100, y / 100)
    if z then map, x, y = z, zx, zy end
  end
  local from, to = Travel.PlayerPoint(), Travel.Point(map, x, y)
  if not (from and to) then return end
  local steps = {}
  local warn = TravelSteps(steps, from, to)
  steps[#steps + 1] = { at = { map, x, y, "Map pin" }, lines = { "{goto} To your map pin", warn }, done = { pin = true } }
  WritPath_SetRoute(steps, "Map pin", "You're at your map pin.")
  WritPathNav.pinRoute = true
end
WritPath_PlannerInternals.PinRoute = WritPath_Timed("map pin route", WritPath_PlannerInternals.PinRoute)
WritPath_PlannerInternals.pinEvents = CreateFrame("Frame")
WritPath_PlannerInternals.pinEvents:RegisterEvent("USER_WAYPOINT_UPDATED")
-- a moment later: the pin is set, and a road waypoint WritPath sets itself is on the route by then
WritPath_PlannerInternals.pinEvents:SetScript("OnEvent", function()
  C_Timer.After(0.1, function() WritPath_PlannerInternals.PinRoute() end)
end)
