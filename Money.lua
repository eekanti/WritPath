-- WritPath money: logs each writ turn-in with what it cost and what its Coin Pouch paid.
-- A pouch is matched to money when a Coin Pouch leaves your bags and your gold goes up
-- within a few seconds of it. The payout goes to the oldest unpaid turn-in of that tier.
-- /writs money  prints the log

-- what each writ cost you (writ + item, Auctionator scan 2026-11-14 16:43), in copper
local WRITS = {
  [94288] = { "Mithril Frag Bomb", "Expert", 5869 },
  [94290] = { "Mechanical Repair Kit", "Expert", 7032 },
  [94259] = { "Nature Protection Potion", "Expert", 7210 },
  [94265] = { "Goblin Rocket Fuel", "Expert", 7868 },
  [94283] = { "Goblin Land Mine", "Expert", 8190 },
  [94286] = { "Flash Bomb", "Expert", 8214 },
  [94263] = { "Fire Protection Potion", "Expert", 8300 },
  [94275] = { "Solid Sharpening Stone", "Expert", 8336 },
  [94256] = { "Frost Protection Potion", "Expert", 7700 },   -- scan 2026-11-14 18:23
}
local POUCHES = { [284584] = "Journeyman", [284585] = "Expert", [284586] = "Artisan" }

local function Print(msg) DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99WritPath|r " .. msg) end

local function Coins(c, signed)
  local neg = c < 0; c = math.abs(math.floor(c + 0.5))
  local g, s, k = math.floor(c / 10000), math.floor(c / 100) % 100, c % 100
  local t = {}
  if g > 0 then t[#t + 1] = g .. "g" end
  if s > 0 or g > 0 then t[#t + 1] = s .. "s" end
  t[#t + 1] = k .. "c"
  local str = table.concat(t, " ")
  if signed then return (neg and "|cFFFF5722-" or "|cFF00FF25+") .. str .. "|r" end
  return (neg and "-" or "") .. str
end

local function Count(id) return WritPath_BagCount(id) end   -- in your bags, not worn (WritPath.lua)

local function Totals()
  local got, spent, unpaid = 0, 0, 0
  for _, e in ipairs(WritPathMoney.log) do
    got = got + (e.paid or 0) + (e.questMoney or 0)
    spent = spent + (e.cost or 0)
    if e.turnedIn and not e.paid then unpaid = unpaid + 1 end
  end
  return got, spent, got - spent, unpaid
end

-- the plan you're running: what it cost when you started it (writs and items to buy; your own writs count
-- as nothing) against the pouches from its turn-ins so far. WritPathMoney.session is set by Start route.
local function SessionTotals()
  local s = WritPathMoney.session
  if not s then return nil end
  local got, unpaid = 0, 0
  for _, e in ipairs(WritPathMoney.log) do
    if (e.t or 0) >= s.start and e.turnedIn then
      got = got + (e.paid or 0) + (e.questMoney or 0)
      if not e.paid then unpaid = unpaid + 1 end
    end
  end
  -- once you've bought something, the cost is what you really paid, plus the planned price of anything
  -- still on the shopping list; before that, it's the plan's estimate
  local cost, rem = s.cost or 0, 0
  if s.spent then
    rem = WritPath_ShopRemaining and WritPath_ShopRemaining() or 0
    cost = s.spent + rem
  end
  return got, cost, got - cost, unpaid, s.spent and (s.cost or 0) or nil, rem
end

---------------------------------------------------------------- footer under the guide window
local guide = WritPathGuide
local footer = CreateFrame("Frame", nil, guide, "BackdropTemplate")
footer:SetHeight(22)
footer:SetPoint("TOPLEFT", guide, "BOTTOMLEFT", 0, 2); footer:SetPoint("TOPRIGHT", guide, "BOTTOMRIGHT", 0, 2)
footer:SetBackdrop({ bgFile = "Interface/BUTTONS/WHITE8X8", edgeFile = "Interface/BUTTONS/WHITE8X8", edgeSize = 1,
                     insets = { left = 1, right = 1, top = 1, bottom = 1 } })
footer:SetBackdropColor(0.11, 0.10, 0.09, 1); footer:SetBackdropBorderColor(0, 0, 0, 1)
if EllesmereUI and EllesmereUI.RegisterSkin then EllesmereUI.RegisterSkin("WritPathMoney", function(S) S.Panel(footer, { inset = true }) end) end
-- one text that wraps to the footer's width; the footer grows to fit, so nothing is ever cut off
local ftext = footer:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
ftext:SetJustifyH("LEFT"); ftext:SetJustifyV("TOP"); ftext:SetWordWrap(true); ftext:SetSpacing(2)
ftext:SetPoint("TOPLEFT", 8, -6); ftext:SetPoint("RIGHT", footer, "RIGHT", -8, 0)
WritPath_FooterText = ftext   -- Nav.lua gives it the EllesmereUI font

local function Update()
  local got, cost, net, unpaid, planned, rem = SessionTotals()
  if not got then
    ftext:SetText("|cFFAAAAAANo plan running. Start one from the planner to track its cost and pouches here.|r")
  else
    local extra = ""
    if planned then
      extra = (" |cFFAAAAAA(planned %s%s)|r"):format(Coins(planned), (rem or 0) > 0 and (", ~" .. Coins(rem) .. " still to buy") or "")
    end
    ftext:SetText(("|TInterface/MONEYFRAME/UI-GoldIcon:0|t This plan: cost %s%s |cFFAAAAAA·|r pouches %s |cFFAAAAAA·|r net %s%s"):format(
      Coins(cost), extra, Coins(got), Coins(net, true),
      unpaid > 0 and ("\n|cFFFCDC00" .. unpaid .. (unpaid == 1 and " pouch" or " pouches") .. " not opened yet|r") or ""))
  end
  ftext:SetWidth(math.max(100, (footer:GetWidth() or 300) - 16))
  footer:SetHeight(ftext:GetStringHeight() + 14)
end
footer:SetScript("OnSizeChanged", function() Update() end)

WritPath_SessionTotals = SessionTotals   -- for the test harness
WritPath_MoneyUpdate = function() Update() end   -- the buyer calls this after each purchase

-- Start route opens a session with the plan's cost; clearing the plan closes it
function WritPath_StartMoneySession(cost, rep)
  WritPathMoney.session = cost and { start = time(), cost = cost, rep = rep } or nil
  Update()
end

---------------------------------------------------------------- matching pouches to money
local lastMoney, counts = 0, {}
local pouch, gain          -- { tier, t } and { amount, t }, waiting to be paired

local function Record(tier, amount)
  local entry
  for _, e in ipairs(WritPathMoney.log) do
    if e.turnedIn and not e.paid and e.tier == tier then entry = e; break end
  end
  if not entry then   -- a pouch from a turn-in made before tracking started
    entry = { name = "Earlier " .. tier .. " writ", tier = tier, turnedIn = true, t = time() }
    table.insert(WritPathMoney.log, entry)
  end
  entry.paid = amount
  local _, _, net = SessionTotals()
  Print(("Coin Pouch: %s for %s.%s"):format(Coins(amount), entry.name,
    net and (" This plan's net so far: " .. Coins(net, true)) or ""))
  Update()
end

local function TryMatch()
  local now = GetTime()
  if pouch and now - pouch.t > 10 then pouch = nil end
  if gain and now - gain.t > 10 then gain = nil end
  if not (pouch and gain) then return end
  -- money right after the pouch left the bags, or just before (the two events can come in either order)
  if (gain.t >= pouch.t and gain.t - pouch.t <= 10) or (pouch.t > gain.t and pouch.t - gain.t <= 2) then
    Record(pouch.tier, gain.amount); pouch, gain = nil, nil
  end
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_LOGIN")
ev:RegisterEvent("QUEST_TURNED_IN")
ev:RegisterEvent("BAG_UPDATE_DELAYED")
ev:RegisterEvent("PLAYER_MONEY")
ev:SetScript("OnEvent", function(_, event, a1, _, a3)
  if event == "PLAYER_LOGIN" then
    if not WritPathMoney then
      -- seeded with what was known before tracking: Mithril Frag Bomb's pouch paid 80s
      WritPathMoney = { log = { { q = 94288, name = "Mithril Frag Bomb", tier = "Expert", cost = 5869,
                                  turnedIn = true, paid = 8000, t = time() } } }
    end
    -- payouts reported by hand before tracking ran (2026-11-14); added once each
    for _, m in ipairs({ { 94265, 6800 }, { 94286, 6800 } }) do
      local have = false
      for _, e in ipairs(WritPathMoney.log) do if e.q == m[1] then have = true end end
      if not have then
        local w = WRITS[m[1]]
        table.insert(WritPathMoney.log, { q = m[1], name = w[1], tier = w[2], cost = w[3],
                                          turnedIn = true, paid = m[2], t = time() })
      end
    end
    lastMoney = GetMoney()
    for id in pairs(POUCHES) do counts[id] = Count(id) end
    Update()

  elseif event == "QUEST_TURNED_IN" then
    local qid, money = a1, a3
    -- what this writ cost: the writ and its item, from what you paid (or today's price where WritPath
    -- didn't see the purchase); the old fixed table only for a writ the planner doesn't know
    local w
    if WritPath_WritByQuest then
      local nm, tier, cost, writ, item, est = WritPath_WritByQuest(qid)
      if nm then w = { nm, tier, cost, writ, item, est } end
    end
    w = w or WRITS[qid]
    local title = C_QuestLog.GetTitleForQuestID and C_QuestLog.GetTitleForQuestID(qid)
    if w or (title and title:find("Craftsman's Writ")) then
      table.insert(WritPathMoney.log, {
        q = qid, name = w and w[1] or title:gsub("Craftsman's Writ: ", ""), tier = w and w[2] or "Expert",
        cost = w and w[3], writCost = w and w[4], itemCost = w and w[5], est = w and w[6] or nil, turnedIn = true, questMoney = (money or 0) > 0 and money or nil, t = time() })
      Update()
    end

  elseif event == "BAG_UPDATE_DELAYED" then
    for id, tier in pairs(POUCHES) do
      local c = Count(id)
      if c < (counts[id] or 0) then pouch = { tier = tier, t = GetTime() } end
      counts[id] = c
    end
    TryMatch()

  elseif event == "PLAYER_MONEY" then
    local m = GetMoney()
    if m > lastMoney then gain = { amount = m - lastMoney, t = GetTime() } end
    lastMoney = m
    TryMatch()
  end
end)

function WritPath_MoneyReport()
  Print("Writ money:")
  for _, e in ipairs(WritPathMoney.log) do
    local paid = e.paid and Coins(e.paid) or "|cFFFCDC00not opened|r"
    local cost = e.cost and Coins(e.cost) or "?"
    if e.cost and (e.writCost or e.itemCost) then
      cost = cost .. (" |cFFAAAAAA(writ %s + item %s%s)|r"):format(Coins(e.writCost or 0), Coins(e.itemCost or 0), e.est and ", partly today's price" or "")
    end
    local net = (e.paid and e.cost) and ("  net " .. Coins(e.paid + (e.questMoney or 0) - e.cost, true)) or ""
    Print(("  %s (%s): cost %s, pouch %s%s"):format(e.name, e.tier, cost, paid, net))
  end
  local got, spent, net = Totals()
  Print(("Total: pouches %s, spent %s, net %s"):format(Coins(got), Coins(spent), Coins(net, true)))
end
