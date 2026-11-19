// The cheapest way to a rep target from the player's own AH scan, ignoring travel: writs by net cost per rep
// (writ + item - average pouch), at most one writ per customer (the one-per-customer-per-day limit), then
// receipts priced the same way as research/forgery.md. A check on the planner's "Cheapest" card.
// node research/cheapest.js <SavedVariables/WritPath.lua> <addon dir> [target, default 1000]
const {lua,lauxlib,lualib,to_luastring}=require('fengari'); const fs=require('fs');
const [sv, addon, target] = process.argv.slice(2);
const L=lauxlib.luaL_newstate(); lualib.luaL_openlibs(L);
const run=(c,n)=>{ if(lauxlib.luaL_loadbuffer(L,to_luastring(c),null,to_luastring(n))||lua.lua_pcall(L,0,0,0)){ console.log('ERR',n,lua.lua_tojsstring(L,-1)); process.exit(1);} };
run(fs.readFileSync(sv,'utf8'),'sv');
run(fs.readFileSync(addon+'/WritDB.lua','utf8'),'db');
const pouch = fs.readFileSync(addon+'/Planner.lua','utf8').match(/local POUCH_GUESS = \{[^\n]*/);
run((pouch ? pouch[0] : 'local POUCH_GUESS = {}') + `
local TARGET = ${Number(target) || 1000}
local P = WritPathPrices.items
local function Units(id) local e = P[id]; if not e or not e.l then return {} end
  local t = {}; for _, x in ipairs(e.l) do for i = 1, (x[2] or 1) do t[#t + 1] = x[1] end end; table.sort(t); return t end
local function Cost(id, n) local u = Units(id); if #u < n then return nil end; local s = 0; for i = 1, n do s = s + u[i] end; return s end
local REP = { Journeyman = 75, Expert = 125, Artisan = 200 }
local function Pouch(tier) local s, n = 0, 0
  for _, e in ipairs(WritPathMoney and WritPathMoney.log or {}) do if e.tier == tier and e.paid then s, n = s + e.paid, n + 1 end end
  return n > 0 and s / n or (POUCH_GUESS[tier] or 0) end
local function C(c) c = math.floor(c + 0.5); local neg = c < 0; c = math.abs(c)
  return (neg and "-" or "") .. (c >= 10000 and (math.floor(c / 10000) .. "g ") or "") .. (math.floor(c / 100) % 100) .. "s " .. (c % 100) .. "c" end
-- customers already handed in today can't take another writ (WritPathLearned / quest flags aren't in the saved
-- file, so this only knows what the money log says was handed in since the last daily reset ~ 24h)
local cutoff = os.time() - 20 * 3600
local usedToday = {}
for _, e in ipairs(WritPathMoney and WritPathMoney.log or {}) do
  if e.turnedIn and (e.t or 0) > cutoff then for id, w in pairs(WritPath_Writs) do if w.q == e.q then usedToday[w.c or ("#" .. id)] = true end end end
end
local rows = {}
for id, w in pairs(WritPath_Writs) do
  local wc, ic = Cost(id, 1), w.req and Cost(w.req, w.n or 1)
  local cust = w.c or ("#" .. id)
  if wc and ic and not usedToday[cust] then
    local net = wc + ic - Pouch(w.tier)
    rows[#rows + 1] = { name = w.name, tier = w.tier, cust = cust, rep = REP[w.tier], gross = wc + ic, net = net, per = net / REP[w.tier] }
  end
end
table.sort(rows, function(a, b) return a.per < b.per end)
local used, rep, gross, net, picks = {}, 0, 0, 0, {}
for _, r in ipairs(rows) do
  if rep >= TARGET then break end
  if not used[r.cust] then used[r.cust] = true; picks[#picks + 1] = r; rep, gross, net = rep + r.rep, gross + r.gross, net + r.net end
end
print(("Scan %s. Target %d rep. Cheapest by cost per rep, one writ per customer, travel ignored:"):format(os.date("%m-%d %H:%M", WritPathPrices.t), TARGET))
for i, r in ipairs(picks) do
  print(("%2d. %-30s %-10s %-26s buy %-11s net %-11s (%s/rep)"):format(i, r.name, r.tier, r.cust, C(r.gross), C(r.net), C(r.per)))
end
print(("=> %d writs, %d rep, buy %s, pouches back ~%s, net %s"):format(#picks, rep, C(gross), C(gross - net), C(net)))
`,'cheapest');
