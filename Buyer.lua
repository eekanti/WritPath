-- WritPath Buy next: the plan's shopping list at the auction house, a click per purchase.
-- WoW only lets an addon buy inside a click, so WritPath searches by itself, shows what it found
-- on the button, and your click buys it. Then it moves on.
--   Forever runs the modern auction house (C_AuctionHouse), like Auctionator assumes:
--     items (writs, gear)        one click:  PlaceBid(auctionID, buyout)
--     commodities (potions, ...) two clicks: StartCommoditiesPurchase (a firm price quote), then Confirm
--   The classic auction house (QueryAuctionItems / PlaceAuctionBid) is kept as a fallback.
--   * cheapest first, never your own auctions
--   * stacks: the cheapest that doesn't give you more than you need, else the cheapest one
--   * price cap: more than 25% over the price the plan was built on isn't bought unless you say so
--   * purchases may arrive by mail: what WritPath bought counts as yours before it's in your bags
-- The list comes from the plan (Start route or Send to Auctionator in the planner).

local CAP = 1.25
local G, W_, Y, GREY = "|cFF00FF25", "|cFFFCDC00", "|cFF00BCD4", "|cFFAAAAAA"
local MODERN = C_AuctionHouse and C_AuctionHouse.SendSearchQuery and true or false
local function Print(msg) DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99WritPath|r " .. msg) end

local function Count(id)
  if C_Item and C_Item.GetItemCount then return C_Item.GetItemCount(id) or 0 end
  return GetItemCount and GetItemCount(id) or 0
end
local function ItemName(id)
  if C_Item and C_Item.GetItemNameByID then local n = C_Item.GetItemNameByID(id); if n then return n end end
  return GetItemInfo and (GetItemInfo(id)) or nil
end
local function Coins(c)
  c = math.floor((c or 0) + 0.5)
  local g, s = math.floor(c / 10000), math.floor(c / 100) % 100
  if g > 0 then return g .. "g " .. s .. "s" end
  if s > 0 then return s .. "s " .. c % 100 .. "c" end
  return c % 100 .. "c"
end

---------------------------------------------------------------- the list
-- { id, name, total = how many you need, unit = price the plan was built on, base = in your bags when the
--   list was made, bought = bought here since (may still be in the mail) }
function WritPath_SetShopList(list)
  for _, it in ipairs(list or {}) do it.base, it.bought = Count(it.id), 0 end
  WritPathNav.shopList = list
  WritPathNav.shopAt = time()
  if WritPath_BuyerRefresh then WritPath_BuyerRefresh() end
end

local state = { phase = "idle" }   -- idle, searching, ready, over, none, quote, confirm, buying, unsure, done
local function List() return WritPathNav and WritPathNav.shopList or {} end
local function Have(it) return math.max(Count(it.id), (it.base or 0) + (it.bought or 0)) end

-- bought here but not in your bags yet (auction house purchases often go to the mail): counts as yours
function WritPath_InMail(id)
  local n = 0
  for _, it in ipairs(List()) do
    if it.id == id then n = n + math.max(0, (it.base or 0) + (it.bought or 0) - Count(id)) end
  end
  return n
end
local function Need(it) return math.max(0, (it.total or 1) - Have(it)) end
local function NextItem()
  for i, it in ipairs(List()) do if not it.skipped and Need(it) > 0 then return i, it end end
end
local function Progress()
  local done, total = 0, 0
  for _, it in ipairs(List()) do total = total + 1; if Need(it) == 0 then done = done + 1 end end
  return done, total
end

-- the planned price of what's still to buy (for the footer's cost)
function WritPath_ShopRemaining()
  local c = 0
  for _, it in ipairs(List()) do c = c + Need(it) * (it.unit or 0) end
  return c
end

-- the route was rebuilt from what you have: keep what's needed for it and everything you've bought (it may
-- still be in the mail), drop the rest; anything newly needed is added
function WritPath_PruneShopList(needed)   -- needed = { [item id] = { total =, unit =, name = } }
  local keep, seen = {}, {}
  for _, it in ipairs(List()) do
    if needed[it.id] or (it.bought or 0) > 0 then keep[#keep + 1] = it; seen[it.id] = true end
  end
  for id, e in pairs(needed) do
    if not seen[id] then keep[#keep + 1] = { id = id, name = e.name, total = e.total, unit = e.unit, base = Count(id), bought = 0 } end
  end
  WritPathNav.shopList = keep
end

---------------------------------------------------------------- panel beside the auction house
local panel, title, itemText, statusText, mainBtn, altBtn, closeBtn
local fonts, btns, skin = {}, {}, nil
local function Text(parent, template, width)
  local fs = parent:CreateFontString(nil, "OVERLAY", template or "GameFontHighlightSmall")
  fs:SetJustifyH("LEFT"); fs:SetJustifyV("TOP"); fs:SetWordWrap(true); fs:SetWidth(width)
  fonts[#fonts + 1] = fs
  return fs
end
local function AHFrame() return AuctionHouseFrame or AuctionFrame end
local function Build()
  if panel then return end
  local W = 250
  panel = CreateFrame("Frame", "WritPathBuyer", UIParent, "BackdropTemplate")
  panel:SetWidth(W); panel:SetFrameStrata("HIGH"); panel:SetClampedToScreen(true)
  panel:SetMovable(true); panel:EnableMouse(true); panel:RegisterForDrag("LeftButton")
  panel:SetScript("OnDragStart", panel.StartMoving); panel:SetScript("OnDragStop", panel.StopMovingOrSizing)
  title = Text(panel, "GameFontNormal", W - 40); title:SetPoint("TOPLEFT", 10, -9)
  closeBtn = CreateFrame("Button", nil, panel, "UIPanelCloseButton"); closeBtn:SetSize(20, 20); closeBtn:SetPoint("TOPRIGHT", -3, -3)
  closeBtn:SetScript("OnClick", function() panel:Hide() end)
  itemText = Text(panel, "GameFontHighlight", W - 20)
  statusText = Text(panel, "GameFontHighlightSmall", W - 20)
  mainBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate"); mainBtn:SetHeight(26); btns[#btns + 1] = mainBtn
  altBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate"); altBtn:SetHeight(22); btns[#btns + 1] = altBtn
  if skin then
    skin.Shell(panel); skin.CloseButton(closeBtn)
    for _, b in ipairs(btns) do skin.Button(b); if skin.StateButtonLabel then skin.StateButtonLabel(b) end end
    for _, fs in ipairs(fonts) do skin.Font(fs) end
  else
    local flat = { bgFile = "Interface/BUTTONS/WHITE8X8", edgeFile = "Interface/BUTTONS/WHITE8X8", edgeSize = 1 }
    panel:SetBackdrop(flat); panel:SetBackdropColor(0.06, 0.06, 0.07, 0.96); panel:SetBackdropBorderColor(0, 0, 0, 1)
  end
end
local function Dock()   -- beside the auction house window, whichever one this client has
  local ah = AHFrame()
  panel:ClearAllPoints()
  if ah then panel:SetPoint("TOPLEFT", ah, "TOPRIGHT", 6, -24) else panel:SetPoint("LEFT", UIParent, "LEFT", 40, 0) end
end
if EllesmereUI and EllesmereUI.RegisterSkin then EllesmereUI.RegisterSkin("WritPathBuyer", function(S) skin = S end) end

local Search

local function Render()
  if not panel then return end
  local done, total = Progress()
  title:SetText(("Writ shopping  %s%d / %d|r"):format(GREY, done, total))
  local it, p = state.it, state.pick
  local main, alt, status
  local unit = it and it.unit and it.unit > 0 and Coins(it.unit) or "?"
  if not it then
    itemText:SetText(total == 0 and (GREY .. "No shopping list yet.|r") or (G .. "Everything on the list is bought.|r"))
    status = total == 0 and "Start a route (or press Send to Auctionator) in the planner." or "Nothing left to buy."
  else
    itemText:SetText((ItemName(it.id) or it.name or "?") .. (Need(it) > 1 and (" x" .. Need(it)) or ""))
    local ph = state.phase
    if ph == "searching" then status, main = "Searching the auction house...", "Searching..."
    elseif ph == "ready" then
      local each = p.qty > 1 and (" (" .. Coins(p.unit) .. " each)") or ""
      status = ("Cheapest: %s%s|r for %d%s. The plan expected %s each."):format(Y, Coins(p.total), p.qty, each, unit)
      if p.qty > Need(it) then status = status .. W_ .. (" Only sold as a stack of %d: you need %d.|r"):format(p.qty, Need(it)) end
      main = (p.kind == "commodity" and "Get price: " or "Buy for ") .. Coins(p.total)
      alt = "Skip"
    elseif ph == "over" then
      if p.qty > Need(it) then
        status = W_ .. ("Only sold as a stack of %d for %s (you need %d): more than %d%% over the %s the plan expected."):format(
          p.qty, Coins(p.total), Need(it), (CAP - 1) * 100, Coins((it.unit or 0) * Need(it))) .. "|r"
      else
        status = W_ .. ("Cheapest is %s each, more than %d%% over the %s the plan was built on."):format(Coins(p.unit), (CAP - 1) * 100, unit) .. "|r"
      end
      main, alt = "Skip", "Buy anyway: " .. Coins(p.total)
    elseif ph == "quote" then status, main = "Getting a firm price...", "Getting price..."
    elseif ph == "confirm" then
      status = ("Firm price: %s%s|r for %d (%s each).%s"):format(Y, Coins(state.quoteTotal), p.qty, Coins(state.quoteUnit),
        state.quoteUnit > p.unit * 1.0001 and (W_ .. " Higher than the search showed.|r") or "")
      local overCap = it.unit and it.unit > 0 and state.quoteUnit > it.unit * CAP
      main, alt = (overCap and "Confirm anyway: " or "Confirm: ") .. Coins(state.quoteTotal), "Cancel"
    elseif ph == "none" then status, main = W_ .. "Not on the auction house right now.|r", "Skip"
    elseif ph == "buying" then status, main = "Buying...", "Buying..."
    elseif ph == "unsure" then
      status, main = W_ .. "The game didn't confirm that purchase. Check your mail and bags before buying again.|r", "Search again"
    else status, main = "Ready.", "Find it" end
  end
  statusText:SetText(status or "")
  itemText:ClearAllPoints(); itemText:SetPoint("TOPLEFT", panel, "TOPLEFT", 10, -32)
  local y = -32 - itemText:GetStringHeight() - 6
  statusText:ClearAllPoints(); statusText:SetPoint("TOPLEFT", panel, "TOPLEFT", 10, y)
  y = y - statusText:GetStringHeight() - 10
  if main then
    mainBtn:SetText(main); mainBtn:Show()
    mainBtn:ClearAllPoints(); mainBtn:SetPoint("TOPLEFT", panel, "TOPLEFT", 10, y); mainBtn:SetPoint("RIGHT", panel, "RIGHT", -10, 0)
    local busy = state.phase == "searching" or state.phase == "buying" or state.phase == "quote"
    if busy then mainBtn:Disable() else mainBtn:Enable() end
    y = y - 30
  else mainBtn:Hide() end
  if alt then
    altBtn:SetText(alt); altBtn:Show()
    altBtn:ClearAllPoints(); altBtn:SetPoint("TOPLEFT", panel, "TOPLEFT", 10, y); altBtn:SetPoint("RIGHT", panel, "RIGHT", -10, 0)
    y = y - 26
  else altBtn:Hide() end
  panel:SetHeight(-y + 8)
end

---------------------------------------------------------------- searching (no click needed)
-- The item on the button is searched first; while you look at it, the next few on the list are searched
-- too, so after each purchase the next one is usually ready at once.
local queued, waiting = false, false   -- the item on the button: query to send / answer awaited
local cache = {}                       -- [item id] = { pick = what to buy or false, t = when }
local ahead = {}                       -- item ids being looked up in advance, in order
local aheadWaiting = nil               -- the advance lookup awaiting its answer
local FRESH, LOOKAHEAD = 45, 3          -- seconds an advance lookup stays good; how many items ahead

local function Entry(id) for _, it in ipairs(List()) do if it.id == id and Need(it) > 0 and not it.skipped then return it end end end

local Decide
function Search()
  state.pick = nil
  state.i, state.it = NextItem()
  if not state.it then state.phase = "done"; Render(); return end
  local c = cache[state.it.id]
  if c and GetTime() - c.t < FRESH then   -- looked up while you were busy with the one before
    cache[state.it.id] = nil
    Decide(c.pick or nil)
  else
    state.phase = "searching"; queued, waiting = true, false
    Render()
  end
end
WritPath_BuyerRefresh = function() if panel and panel:IsShown() then Search() end end

-- the next few items without an answer yet
local function PlanAhead()
  ahead = {}
  if not MODERN then return end
  local started = false
  for _, it in ipairs(List()) do
    if it == state.it then started = true
    elseif started and #ahead < LOOKAHEAD and not it.skipped and Need(it) > 0 and not (cache[it.id] and GetTime() - cache[it.id].t < FRESH) then
      ahead[#ahead + 1] = it.id
    end
  end
end

local function Ready()
  if MODERN then return not C_AuctionHouse.IsThrottledMessageSystemReady or C_AuctionHouse.IsThrottledMessageSystemReady() end
  return CanSendAuctionQuery and CanSendAuctionQuery()
end
local function SendQuery(id)
  if MODERN then
    -- one search: the game answers with commodity results or item results, whichever this item is
    C_AuctionHouse.SendSearchQuery(C_AuctionHouse.MakeItemKey(id), { sortOrder = 0, reverseSort = false }, true)
  else
    if SortAuctionSetSort then SortAuctionSetSort("list", "unitprice") end
    QueryAuctionItems(ItemName(id) or state.it.name, nil, nil, 0, nil, nil, false, true, nil)
  end
end

-- over the cap: judged on what you'd pay for what you need, so a stack bigger than you need counts in full
local function Over(it, pick)
  if not (it.unit and it.unit > 0) then return false end
  local need = math.max(1, Need(it))
  return pick.total > it.unit * math.min(pick.qty, need) * CAP + 0.5 or (pick.qty > need and pick.total > it.unit * need * CAP + 0.5)
end

function Decide(pick)
  state.pick = pick
  local it = state.it
  if not pick then state.phase = "none"
  elseif Over(it, pick) then state.phase = "over"
  else state.phase = "ready" end
  PlanAhead()
  Render()
end

-- commodities: the cheapest units first, as many as you need (or all there are)
local function ChooseCommodity(it, itemID)
  local need, got, total, top = Need(it), 0, 0, 0
  for i = 1, C_AuctionHouse.GetNumCommoditySearchResults(itemID) do
    local r = C_AuctionHouse.GetCommoditySearchResultInfo(itemID, i)
    local mine = r and (r.containsOwnerItem or (r.owners and r.owners[1] == "player"))
    if r and not mine and got < need then
      local take = math.min(r.quantity or 0, need - got)
      got, total, top = got + take, total + take * r.unitPrice, r.unitPrice
    end
  end
  if got == 0 then return false end
  return { kind = "commodity", itemID = itemID, qty = got, total = total, unit = total / got, top = top }
end

-- items: the cheapest auction that doesn't give you more than you need, else the cheapest one in total
local function ChooseItem(it, itemKey)
  local need, fit, any = Need(it), nil, nil
  for i = 1, C_AuctionHouse.GetNumItemSearchResults(itemKey) do
    local r = C_AuctionHouse.GetItemSearchResultInfo(itemKey, i)
    if r and r.buyoutAmount and r.buyoutAmount > 0 and not (r.containsOwnerItem or r.containsAccountItem) then
      local q = r.quantity or 1
      local l = { kind = "item", auctionID = r.auctionID, qty = q, total = r.buyoutAmount, unit = r.buyoutAmount / q }
      if q <= need and (not fit or l.unit < fit.unit) then fit = l end
      if not any or l.total < any.total then any = l end
    end
  end
  return fit or any or false
end

-- classic auction house
local function ChooseClassic()
  local it, me = state.it, UnitName("player")
  local need, fit, any = Need(it), nil, nil
  for i = 1, (GetNumAuctionItems("list")) or 0 do
    local info = { GetAuctionItemInfo("list", i) }
    local count, buyout, owner, itemId = info[3] or 1, info[10] or 0, info[14], info[17]
    if itemId == it.id and buyout > 0 and owner ~= me then
      local l = { kind = "classic", index = i, qty = count, total = buyout, unit = buyout / count, itemId = itemId }
      if count <= need and (not fit or l.unit < fit.unit) then fit = l end
      if not any or l.total < any.total then any = l end
    end
  end
  Decide(fit or any)
end

-- an answer came in: for the item on the button, or one looked up in advance
local function Answer(id, choose)
  if waiting and state.it and state.it.id == id then
    waiting = false
    Decide(choose(state.it) or nil)
  elseif aheadWaiting == id then
    aheadWaiting = nil
    local it = Entry(id)
    if it then cache[id] = { pick = choose(it), t = GetTime() } end
  end
end

---------------------------------------------------------------- buying (inside a click)
local boughtThisVisit = false
local pending = {}   -- [auctionID] = { it, qty, paid }: item buyouts waiting for the game to confirm them

-- what you paid: for the footer (this plan's real cost), the turn-in log, and better prices next time
local function NotePaid(id, qty, paid)
  WritPathNav.paidFor = WritPathNav.paidFor or {}
  local p = WritPathNav.paidFor[id] or { qty = 0, paid = 0 }
  p.qty, p.paid, p.t = p.qty + qty, p.paid + paid, time()
  WritPathNav.paidFor[id] = p
  local s = WritPathMoney and WritPathMoney.session
  if s then s.spent = (s.spent or 0) + paid end
  if WritPath_MoneyUpdate then WritPath_MoneyUpdate() end
end

local function Credit(it, qty, paid)
  it.bought = (it.bought or 0) + qty
  boughtThisVisit = true
  NotePaid(it.id, qty, paid or 0)
  Print(("Bought %s%s for %s."):format(ItemName(it.id) or it.name or "item", qty > 1 and (" x" .. qty) or "", Coins(paid or 0)))
end

local function Bought(qty)
  Credit(state.it, qty, state.paid)
  Search()
end

-- real prices seen at the auction house (what you'd pay per unit you need) feed the next plan
local function NoteSeen(it, pick)
  if not (pick and pick.qty and pick.qty > 0) then return end
  WritPathNav.seenPrice = WritPathNav.seenPrice or {}
  local need = math.max(1, math.min(Need(it), pick.qty))
  WritPathNav.seenPrice[it.id] = { u = math.floor(pick.total / need + 0.5), t = time() }
end

local function Buy()
  local p = state.pick
  state.since = GetTime()
  NoteSeen(state.it, p)
  if p.kind == "item" then
    state.phase, state.paid = "buying", p.total
    pending[p.auctionID] = { it = state.it, qty = p.qty, paid = p.total }
    C_AuctionHouse.PlaceBid(p.auctionID, p.total)
  elseif p.kind == "commodity" then
    state.phase = "quote"
    C_AuctionHouse.StartCommoditiesPurchase(p.itemID, p.qty)
  else
    local info = { GetAuctionItemInfo("list", p.index) }   -- still the same auction as shown?
    if not (info[17] == p.itemId and (info[3] or 1) == p.qty and (info[10] or 0) == p.total) then Search(); return end
    state.phase, state.paid, state.countBefore = "buying", p.total, Count(state.it.id)
    PlaceAuctionBid("list", p.index, p.total)
  end
  Render()
end

local function Click()
  local ph = state.phase
  if ph == "ready" then Buy()
  elseif ph == "confirm" then
    state.phase, state.paid, state.since = "buying", state.quoteTotal, GetTime()
    C_AuctionHouse.ConfirmCommoditiesPurchase(state.pick.itemID, state.pick.qty)
    Render()
  elseif ph == "over" or ph == "none" then state.it.skipped = true; Search()
  elseif ph ~= "searching" and ph ~= "buying" and ph ~= "quote" then Search() end
end
local function AltClick()
  local ph = state.phase
  if ph == "ready" then state.it.skipped = true; Search()
  elseif ph == "over" then Buy()
  elseif ph == "confirm" then
    if C_AuctionHouse.CancelCommoditiesPurchase then C_AuctionHouse.CancelCommoditiesPurchase() end
    Search()
  end
end

---------------------------------------------------------------- events
local ev = CreateFrame("Frame")
for _, e in ipairs({ "AUCTION_HOUSE_SHOW", "AUCTION_HOUSE_CLOSED", "UI_ERROR_MESSAGE", "CHAT_MSG_SYSTEM", "BAG_UPDATE_DELAYED" }) do ev:RegisterEvent(e) end
if MODERN then
  for _, e in ipairs({ "COMMODITY_SEARCH_RESULTS_UPDATED", "ITEM_SEARCH_RESULTS_UPDATED", "COMMODITY_PRICE_UPDATED",
                       "COMMODITY_PRICE_UNAVAILABLE", "COMMODITY_PURCHASE_SUCCEEDED", "COMMODITY_PURCHASE_FAILED",
                       "AUCTION_HOUSE_PURCHASE_COMPLETED" }) do pcall(ev.RegisterEvent, ev, e) end
else
  ev:RegisterEvent("AUCTION_ITEM_LIST_UPDATE")
end

local WON = ERR_AUCTION_WON_S and ERR_AUCTION_WON_S:gsub("%%s", "(.+)") or "You won an auction for (.+)"

ev:SetScript("OnEvent", function(_, event, a1, a2)
  if event == "AUCTION_HOUSE_SHOW" then
    Build(); Dock()
    mainBtn:SetScript("OnClick", Click); altBtn:SetScript("OnClick", AltClick)
    -- a list belongs to a plan: keep it while that route runs, or for a few hours after "Send to Auctionator"
    -- without a route. A leftover from an old plan is dropped instead of popping up at every visit.
    local routeOn = WritPathNav.route and #WritPathNav.route > 0
    local fresh = WritPathNav.shopAt and time() - WritPathNav.shopAt < 3 * 3600
    if not routeOn and not fresh then WritPathNav.shopList = nil end
    for _, it in ipairs(List()) do it.skipped = nil end
    cache, ahead, aheadWaiting, boughtThisVisit = {}, {}, nil, false
    -- only when the planner left you something to buy; an empty or finished list stays out of the way
    if not NextItem() then panel:Hide(); return end
    panel:Show()
    Search()
  elseif event == "AUCTION_HOUSE_CLOSED" then
    queued, waiting, aheadWaiting, ahead = false, false, nil, {}
    if boughtThisVisit and WritPath_RunBought then WritPath_RunBought() end
    if panel then panel:Hide() end
    -- done buying: if what you got isn't what was planned, the route is rebuilt from what you have
    if boughtThisVisit and WritPath_ReplanFromBags then boughtThisVisit = false; C_Timer.After(1, WritPath_ReplanFromBags) end
  elseif event == "AUCTION_HOUSE_PURCHASE_COMPLETED" then
    -- a buyout went through: credit the item that auction was for, even if the panel has moved on
    local p = pending[a1]
    if p then
      pending[a1] = nil
      if state.phase == "buying" and state.pick and state.pick.auctionID == a1 then Bought(p.qty)
      else Credit(p.it, p.qty, p.paid); if state.phase == "unsure" then Search() end end
    end
  elseif not (panel and panel:IsShown() and state.it) then
    return
  elseif event == "COMMODITY_SEARCH_RESULTS_UPDATED" then
    Answer(a1, function(it) return ChooseCommodity(it, a1) end)
  elseif event == "ITEM_SEARCH_RESULTS_UPDATED" then
    if a1 and a1.itemID then Answer(a1.itemID, function(it) return ChooseItem(it, a1) end) end
  elseif event == "AUCTION_ITEM_LIST_UPDATE" then
    if waiting then
      for i = 1, (GetNumAuctionItems("list")) or 0 do   -- wait until every seller's name has loaded
        if select(14, GetAuctionItemInfo("list", i)) == nil then return end
      end
      waiting = false; ChooseClassic()
    end
  elseif event == "COMMODITY_PRICE_UPDATED" then
    if state.phase == "quote" then
      state.quoteUnit, state.quoteTotal = a1, a2
      local it = state.it
      if it.unit and it.unit > 0 and a1 > it.unit * CAP and state.pick.unit <= it.unit * CAP then
        -- the firm price jumped over the cap: say so before anything is bought
        Print(("%s went up to %s each, over the cap."):format(ItemName(it.id) or it.name, Coins(a1)))
      end
      state.phase = "confirm"; Render()
    end
  elseif event == "COMMODITY_PRICE_UNAVAILABLE" or event == "COMMODITY_PURCHASE_FAILED" then
    if state.phase == "quote" or state.phase == "confirm" or state.phase == "buying" then Search() end
  elseif event == "COMMODITY_PURCHASE_SUCCEEDED" then
    if state.phase == "buying" and state.pick.kind == "commodity" then Bought(state.pick.qty) end
  elseif event == "CHAT_MSG_SYSTEM" then
    -- classic auction house only: "You won an auction for X", and only for the item on the button
    if not MODERN and state.phase == "buying" and state.pick.kind == "classic" and type(a1) == "string" then
      local name = a1:match(WON)
      if name and name == (ItemName(state.it.id) or state.it.name) then Bought(state.pick.qty) end
    end
  elseif event == "BAG_UPDATE_DELAYED" then
    if state.phase == "buying" and state.pick.kind == "classic" and Count(state.it.id) > (state.countBefore or 0) then Bought(state.pick.qty) end
  elseif event == "UI_ERROR_MESSAGE" then
    -- sold to someone else, or not enough gold: forget that auction and look again
    if state.phase == "buying" or state.phase == "quote" then
      if state.pick and state.pick.auctionID then pending[state.pick.auctionID] = nil end
      Search()
    end
  end
end)

-- queries go out as soon as the auction house allows one (the item on the button first, then the ones
-- ahead); a purchase that's never confirmed stops and asks
ev:SetScript("OnUpdate", function()
  if queued and state.it and Ready() then
    queued, waiting = false, true
    SendQuery(state.it.id)
  elseif MODERN and not queued and not waiting and not aheadWaiting and #ahead > 0 and Ready()
         and state.phase ~= "buying" and state.phase ~= "quote" and state.phase ~= "confirm" then
    aheadWaiting = table.remove(ahead, 1)
    SendQuery(aheadWaiting)
  end
  if (state.phase == "buying" or state.phase == "quote") and GetTime() - (state.since or 0) > 8 then
    state.phase = "unsure"; Render()
  end
end)

WritPath_BuyerInternals = { State = state, Click = Click, AltClick = AltClick, Search = Search, Cache = function() return cache end }
