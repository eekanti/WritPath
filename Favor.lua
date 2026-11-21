-- WritPath: the cheapest way to earn Merchant's Favor. A Waylaid Crate filled with one of its bundles turns into
-- a Sealed crate; handed in at your faction's camp it pays Merchant's Favor and some silver. This works out which
-- crates and fillings cost the least per Favor at today's auction house prices, counting what's in your bags
-- first, and puts them on the shopping list.
--
-- Crates, fillings and rewards: wow-professions.com's WoW Forever Merchant's Favor guide (item ids from the
-- Wowhead links there). Artisan crates are left out: what they pay isn't known yet.

local G, W_, Y, GREY = "|cFF00FF25", "|cFFFCDC00", "|cFF00BCD4", "|cFFAAAAAA"
local function Print(msg) DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99WritPath|r " .. msg) end
local FAVOR_CURRENCY = 3402

-- { crate item id, name, level to open it, Favor, silver back (copper), { { item, count }, ... one of these } }
local S = { a = 250, A = 500, j = 500, J = 1000, e = 750, E = 1500 }   -- silver: white (raw) / green (crafted) crates
WritPath_Crates = {
  { 248684, "Apprentice Textiles", 10, 5, S.a, { { 2589, 40 }, { 2318, 20 } } },
  { 248683, "Apprentice Ore", 10, 5, S.a, { { 2770, 20 }, { 2771, 20 } } },
  { 248682, "Apprentice Herbs", 10, 5, S.a, { { 2447, 20 }, { 765, 20 }, { 2449, 10 }, { 785, 10 }, { 2450, 10 } } },
  { 248685, "Apprentice Curiosities", 10, 5, S.a, { { 10940, 20 }, { 10939, 4 }, { 10978, 6 }, { 11084, 2 } } },
  { 248702, "Apprentice Fabrics", 10, 10, S.A, { { 4231, 2 }, { 2996, 20 } } },
  { 248703, "Apprentice Ingots", 10, 10, S.A, { { 2840, 20 }, { 3576, 20 }, { 2841, 10 } } },
  { 248704, "Apprentice Parts", 10, 10, S.A, { { 4359, 16 }, { 4361, 16 }, { 4363, 4 } } },
  { 248688, "Journeyman Textiles", 10, 10, S.j, { { 2592, 40 }, { 4306, 40 }, { 2319, 20 } } },
  { 248687, "Journeyman Ore", 10, 10, S.j, { { 2775, 10 }, { 2772, 20 } } },
  { 248686, "Journeyman Herbs", 10, 10, S.j, { { 3820, 10 }, { 2453, 10 }, { 3355, 10 }, { 3369, 10 }, { 3356, 10 } } },
  { 248689, "Journeyman Curiosities", 10, 10, S.j, { { 11083, 20 }, { 11082, 4 }, { 11138, 6 }, { 11139, 2 } } },
  { 248705, "Journeyman Fabrics", 10, 20, S.J, { { 2997, 6 }, { 4305, 10 }, { 4233, 2 } } },
  { 248706, "Journeyman Ingots", 10, 20, S.J, { { 2842, 10 }, { 3575, 20 } } },
  { 248707, "Journeyman Parts", 10, 20, S.J, { { 4371, 8 }, { 4375, 7 }, { 4382, 4 }, { 10558, 45 } } },
  { 248693, "Expert Textiles", 20, 15, S.e, { { 4338, 40 }, { 4234, 20 } } },
  { 248692, "Expert Ore", 20, 15, S.e, { { 2776, 10 }, { 3858, 20 } } },
  { 248690, "Earthly Expert Herbs", 20, 15, S.e, { { 3357, 20 }, { 3818, 10 }, { 3821, 10 }, { 3358, 10 } } },
  { 248691, "Flowering Expert Herbs", 20, 15, S.e, { { 3819, 10 }, { 4625, 10 }, { 8831, 20 }, { 8836, 10 } } },
  { 248694, "Expert Curiosities", 20, 15, S.e, { { 11137, 20 }, { 11135, 4 }, { 11177, 6 }, { 11178, 2 } } },
  { 248708, "Expert Fabrics", 20, 30, S.E, { { 4339, 8 }, { 4236, 2 } } },
  { 248709, "Expert Ingots", 20, 30, S.E, { { 3860, 20 }, { 3859, 15 }, { 3577, 10 } } },
  { 248710, "Expert Parts", 20, 30, S.E, { { 4387, 8 }, { 10559, 5 }, { 10560, 12 }, { 10561, 5 } } },
}

local function Coins(c) return WritPath_Coins and WritPath_Coins(c) or (math.floor((c or 0) / 100 + 0.5) / 100 .. "g") end
local function ItemName(id)
  local n = C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(id)
  if not n and GetItemInfo then n = GetItemInfo(id) end
  return n
end
-- in your bags (not worn), plus what was bought for you and is still in the mail
local function Count(id) return WritPath_BagCount(id) + (WritPath_InMail and WritPath_InMail(id) or 0) end
function WritPath_FavorHave()
  local info = C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo and C_CurrencyInfo.GetCurrencyInfo(FAVOR_CURRENCY)
  return info and info.quantity or nil
end

-- the cheapest plan for `target` Favor: one crate at a time, always the crate and filling that add the least
-- cost per Favor, given what's already planned (the cheapest listings go first, so prices climb) and what you
-- own (free). Returns the planner's view of it.
function WritPath_FavorPlan(target, noBags)   -- noBags: plan as if your bags were empty (buy everything)
  local Price = WritPath_Price
  local level = WritPath_Open(UnitLevel, "player") or 60
  local used, owned = {}, {}
  local function Own(id) if owned[id] == nil then owned[id] = noBags and 0 or Count(id) end; return owned[id] end
  local function Buy(id, want)   -- cost of having `want` of it: buy what you don't own
    local need = want - Own(id)
    if need <= 0 then return 0 end
    local u = Price(id, need)
    return u and u * need or nil
  end
  local function Add(id, k)      -- what k more of it costs on top of the plan so far
    local u = used[id] or 0
    local a, b = Buy(id, u), Buy(id, u + k)
    if not (a and b) then return nil end
    return b - a
  end
  local picks, byKey, earned, cost, back = {}, {}, 0, 0, 0
  local lockedOut, steps = 0, 0
  for _, c in ipairs(WritPath_Crates) do if level < c[3] then lockedOut = lockedOut + 1 end end
  while earned < target and steps < 3000 do
    steps = steps + 1
    local best
    for _, c in ipairs(WritPath_Crates) do
      if level >= c[3] then
        local crate = Add(c[1], 1)
        if crate then
          for fi, f in ipairs(c[6]) do
            local fill = Add(f[1], f[2])
            if fill then
              local per = (crate + fill - c[5]) / c[4]
              if not best or per < best.per then best = { c = c, fi = fi, f = f, crate = crate, fill = fill, per = per } end
            end
          end
        end
      end
    end
    if not best then break end
    local c, f = best.c, best.f
    used[c[1]] = (used[c[1]] or 0) + 1
    used[f[1]] = (used[f[1]] or 0) + f[2]
    earned, cost, back = earned + c[4], cost + best.crate + best.fill, back + c[5]
    local key = c[1] .. ":" .. best.fi
    local p = byKey[key]
    if not p then p = { crate = c[1], name = c[2], favor = c[4], silver = c[5], mat = f[1], n = f[2], count = 0, cost = 0 }; byKey[key] = p; picks[#picks + 1] = p end
    p.count, p.cost = p.count + 1, p.cost + best.crate + best.fill
  end
  table.sort(picks, function(a, b) return (a.cost - a.silver * a.count) / (a.favor * a.count) < (b.cost - b.silver * b.count) / (b.favor * b.count) end)
  return { favor = true, target = target, earned = earned, cost = cost, back = back, picks = picks, used = used,
           owned = owned, lockedOut = lockedOut, route = {}, noBags = noBags or nil }
end

-- the planner's rows, summary and note for a Favor plan
function WritPath_FavorView(plan)
  local rows = {}
  -- what each pick takes from your bags (free), handed out in the plan's order
  local left = {}
  if not plan.noBags then for id, n in pairs(plan.owned or {}) do left[id] = n end end
  local function FromBags(id, want) local n = math.min(left[id] or 0, want); left[id] = (left[id] or 0) - n; return n end
  for _, p in ipairs(plan.picks) do
    local net = p.cost - p.silver * p.count
    local per = net / (p.favor * p.count)
    local mat = ItemName(p.mat) or ("item " .. p.mat)
    local crates, mats = FromBags(p.crate, p.count), FromBags(p.mat, p.count * p.n)
    local bags = {}
    if crates > 0 then bags[#bags + 1] = crates == p.count and "the crates" or (crates .. " crates") end
    if mats > 0 then bags[#bags + 1] = mats == p.count * p.n and ("the " .. mat) or (mats .. " " .. mat) end
    local note = #bags > 0 and ("\n" .. GREY .. "from your bags (free): " .. table.concat(bags, " and ") .. "|r") or ""
    -- the silver back pays for more than you spend: a profit, not a cost
    local perText = per < 0 and (G .. Coins(-per) .. " profit per Favor|r") or (GREY .. Coins(per) .. " per Favor|r")
    rows[#rows + 1] = {
      ("%s%dx|r Waylaid Crate: %s\n%sfill each with %d %s · %d Favor and %s back each|r%s"):format(G, p.count, p.name, GREY, p.n,
        mat, p.favor, Coins(p.silver), note),
      ("%s%s|r\n%s"):format(Y, Coins(p.cost), perText),
    }
  end
  local have = WritPath_FavorHave()
  local summary
  if #plan.picks == 0 then
    summary = W_ .. "Nothing to plan: no crate with an auction house price for both the crate and a filling. Scan the auction house first.|r"
  else
    local net = plan.cost - plan.back
    summary = ("%s%d Merchant's Favor|r from %d crates · cost %s · %s back on hand-in · %s per Favor"):format(G, plan.earned,
      (function() local n = 0; for _, p in ipairs(plan.picks) do n = n + p.count end; return n end)(),
      Coins(plan.cost), Coins(plan.back),
      net < 0 and (Coins(-net / math.max(1, plan.earned)) .. " profit") or Coins(net / math.max(1, plan.earned)))
    if plan.earned < plan.target then
      summary = summary .. "\n" .. W_ .. ("Only %d of %d: the auction house doesn't have enough crates or materials listed."):format(plan.earned, plan.target) .. "|r"
    end
  end
  local note = "Cheapest crate and filling first, at your last scan's prices"
    .. (plan.noBags and " (everything bought: what's in your bags is left alone). " or " (crates and materials in your bags count as free). ")
    .. ""
    .. "Fill each crate by right-clicking it, then hand the Sealed crates to Dokimi at the Durotar Supply camp, just west of the Crossroads "
    .. "(Alliance: Marcy Baker, Three Corners, Redridge). Artisan crates are left out until what they pay is known."
    .. (have and (" You have " .. have .. " Merchant's Favor.") or "")
    .. (plan.lockedOut > 0 and (" " .. plan.lockedOut .. " crates need a higher level.") or "")
  return rows, summary, note
end

-- start: everything to buy goes on the shopping list (next to any writ shopping)
function WritPath_FavorStart(plan)
  -- what each thing is for, shown on its row: "fills 4 Waylaid Crate: Journeyman Parts"
  local forText = {}
  for _, p in ipairs(plan.picks) do
    local crate = "Waylaid Crate: " .. p.name
    forText[p.crate] = ("Merchant's Favor: %d crate%s, %d Favor"):format(p.count, p.count == 1 and "" or "s", p.count * p.favor)
    local t = ("fills %d %s"):format(p.count, crate)
    forText[p.mat] = forText[p.mat] and (forText[p.mat] .. ", " .. t) or t
  end
  for id, t in pairs(forText) do if not t:find("^Merchant") then forText[id] = "For Merchant's Favor: " .. t end end
  local list = {}
  for id, n in pairs(plan.used) do
    if n > (plan.owned[id] or 0) then
      -- not using your bags: buy all of it on top of what you have (the list counts your bags as bought)
      local total = plan.noBags and (n + Count(id)) or n
      local isCrate
      for _, c in ipairs(WritPath_Crates) do if c[1] == id then isCrate = c end end
      list[#list + 1] = { id = id, name = ItemName(id) or (isCrate and ("Waylaid Crate: " .. isCrate[2])) or ("item " .. id),
                          total = total, unit = WritPath_Price(id, n - (plan.owned[id] or 0)), favor = true, forText = forText[id] }
    end
  end
  table.sort(list, function(a, b) return a.id < b.id end)
  -- which crates each thing is for, so skipping one drops what only it needed
  WritPathNav.favorPicks = {}
  for _, p in ipairs(plan.picks) do
    WritPathNav.favorPicks[#WritPathNav.favorPicks + 1] = { crate = p.crate, mat = p.mat, n = p.n, count = p.count, favor = p.favor }
  end
  -- a writ route still under way keeps its shopping next to this; otherwise this is the whole list
  if not (WritPath_RouteActive and WritPath_RouteActive()) then WritPathNav.shopList = {} end
  if WritPath_AddToShopList then WritPath_AddToShopList(list) end
  Print(("Favor shopping: %d crates for %d Merchant's Favor, %s at the auction house. Fill each crate (right-click), then hand the Sealed crates to Dokimi at the Durotar Supply camp, just west of the Crossroads."):format(
    (function() local n = 0; for _, p in ipairs(plan.picks) do n = n + p.count end; return n end)(), plan.earned, Coins(plan.cost)))
end

-- something on the shopping list was skipped: the crates that needed it go too, and their other half with them
function WritPath_FavorSkip(id)
  local picks = WritPathNav and WritPathNav.favorPicks
  if not picks then return end
  local dropped = 0
  for _, p in ipairs(picks) do
    if not p.dropped and (p.crate == id or p.mat == id) then p.dropped = true; dropped = dropped + p.count end
  end
  if dropped == 0 then return end
  -- what's still needed of each crate and material
  local need = {}
  for _, p in ipairs(picks) do
    if not p.dropped then
      need[p.crate] = (need[p.crate] or 0) + p.count
      need[p.mat] = (need[p.mat] or 0) + p.count * p.n
    end
  end
  for _, it in ipairs(WritPathNav.shopList or {}) do
    local mine = false
    for _, p in ipairs(picks) do if p.crate == it.id or p.mat == it.id then mine = true end end
    if mine and not it.skipped then
      it.total = need[it.id] or 0
      if it.total <= math.max(Count(it.id), (it.base or 0) + (it.bought or 0)) then it.skipped = true end
    end
  end
  Print(("%d crate%s dropped from the Favor shopping (nothing to fill %s with). Plan again for a replacement."):format(
    dropped, dropped == 1 and "" or "s", dropped == 1 and "it" or "them"))
end
