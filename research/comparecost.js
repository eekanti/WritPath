// Writs vs Forged Delivery Receipts: cost per reputation from the player's own AH scan (WritPathPrices).
const {lua,lauxlib,lualib,to_luastring}=require('fengari'); const fs=require('fs');
const [sv, addon] = process.argv.slice(2);
const L=lauxlib.luaL_newstate(); lualib.luaL_openlibs(L);
const run=(c,n)=>{ if(lauxlib.luaL_loadbuffer(L,to_luastring(c),null,to_luastring(n))||lua.lua_pcall(L,0,0,0)){ console.log('ERR',n,lua.lua_tojsstring(L,-1)); process.exit(1);} };
run(fs.readFileSync(sv,'utf8'),'sv');
run(fs.readFileSync(addon+'/WritDB.lua','utf8'),'db');
const fav = fs.readFileSync(addon+'/Favor.lua','utf8');
const m = fav.match(/local S = \{[^\n]*\n(WritPath_Crates = \{[\s\S]*?\n\})/);
run(fav.match(/local S = \{[^\n]*/)[0] + '\n' + m[1], 'crates');
const pouchSrc = fs.readFileSync(addon+'/Planner.lua','utf8').match(/local POUCH_GUESS = \{[^\n]*/);
run((pouchSrc ? pouchSrc[0] : 'local POUCH_GUESS = {}') + `
local P = WritPathPrices.items
local function Low(id) local e = P[id]; if not e or not e.l then return nil end; local lo
  for _, x in ipairs(e.l) do if not lo or x[1] < lo then lo = x[1] end end; return lo end
local REP = { Journeyman = 75, Expert = 125, Artisan = 200 }
local function Pouch(tier) local s, n = 0, 0
  for _, e in ipairs(WritPathMoney and WritPathMoney.log or {}) do if e.tier == tier and e.paid then s, n = s + e.paid, n + 1 end end
  return n > 0 and s / n or (POUCH_GUESS[tier] or 0), n end
local function C(c) c = math.floor(c + 0.5); local neg = c < 0; c = math.abs(c)
  return (neg and "-" or "") .. (c >= 10000 and (math.floor(c / 10000) .. "g ") or "") .. (math.floor(c / 100) % 100) .. "s " .. (c % 100) .. "c" end
print(("Scan: %s (%s, %d items)"):format(os.date("%Y-%m-%d %H:%M", WritPathPrices.t), WritPathPrices.kind or "?", WritPathPrices.count or 0))
for _, t in ipairs({ "Journeyman", "Expert", "Artisan" }) do local p, n = Pouch(t); print(("pouch %s: %s (%d seen)"):format(t, C(p), n)) end
-- writs: writ + its items, minus the pouch, per rep
local rows = {}
for id, w in pairs(WritPath_Writs) do
  local wp, ip = Low(id), w.req and Low(w.req)
  if wp and ip then
    local gross = wp + ip * (w.n or 1)
    local net = gross - Pouch(w.tier)
    rows[#rows + 1] = { name = w.name, tier = w.tier, gross = gross, net = net, per = net / REP[w.tier], rep = REP[w.tier] }
  end
end
table.sort(rows, function(a, b) return a.per < b.per end)
print(("\\nWRITS priced (writ and item both listed): %d"):format(#rows))
local function Band(lo, hi) local n = 0; for _, r in ipairs(rows) do if r.per >= lo and r.per < hi then n = n + 1 end end; return n end
for i = 1, math.min(15, #rows) do local r = rows[i]
  print(("  %-32s %-10s cost %-12s net %-12s per rep %s"):format(r.name, r.tier, C(r.gross), C(r.net), C(r.per))) end
print("  ...")
local med = rows[math.floor(#rows / 2) + 1]
print(("  median writ: %s per rep (%s)"):format(C(med.per), med.name))
-- Favor: the cheapest crate + filling, per Favor (one crate's worth, today's lowest listing)
local best
for _, c in ipairs(WritPath_Crates) do
  local cp = Low(c[1])
  if cp then for _, f in ipairs(c[6]) do local fp = Low(f[1]); if fp then
    local per = (cp + fp * f[2] - c[5]) / c[4]
    if not best or per < best.per then best = { per = per, name = c[2], crate = cp, fill = fp * f[2], favor = c[4] } end
  end end end
end
local cheapCrate, cheapName
for _, c in ipairs(WritPath_Crates) do local cp = Low(c[1]); if cp and (not cheapCrate or cp < cheapCrate) then cheapCrate, cheapName = cp, c[2] end end
print(("\\nFAVOR: cheapest to earn = %s per Favor (%s crate %s + filling %s, %d Favor)"):format(C(best.per), best.name, C(best.crate), C(best.fill), best.favor))
print(("cheapest empty crate on the AH: %s (%s)"):format(C(cheapCrate), cheapName))
local earned = (cheapCrate + 15 * best.per - 100) / 50
local onHand = (cheapCrate - 100) / 50
print(("\\nRECEIPT (50 rep): crate %s + 15 Favor - 1s back"):format(C(cheapCrate)))
print(("  Favor earned for it : %s per receipt = %s per rep"):format(C(cheapCrate + 15 * best.per - 100), C(earned)))
print(("  Favor already owned : %s per receipt = %s per rep (the Favor's own cost not counted)"):format(C(cheapCrate - 100), C(onHand)))
print(("\\nWrits cheaper than a receipt (earned Favor): %d of %d"):format(Band(-1e12, earned), #rows))
print(("Writs cheaper than a receipt (owned Favor):  %d of %d"):format(Band(-1e12, onHand), #rows))
`,'compare');
