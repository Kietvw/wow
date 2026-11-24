-- AHAdvisor - turns the price history into ranked suggestions.
--
--   Vendor   listings cheaper than what a vendor pays for the item: risk-free
--   Snipe    a few listings far below the item's normal price: buy, relist at normal
--   Dip      the whole market is below normal: buy, hold until it recovers
--   Rising   price climbing steadily for a week and you can still buy at/below the trend line
--   Pattern  the item is reliably cheaper on one weekday and dearer on another
--   Sell     you own some and the price is unusually high, nobody else sells it, or it is falling
--   Craft    one of your recipes sells for clearly more than its reagents cost
--
-- Each suggestion gets an estimated profit and a confidence (history length, volatility,
-- whether the sale rate is known); the list is sorted by profit x confidence.
local _, ns = ...
local A = {}
ns.Analysis = A
A.list = {}

local Money = function(c) return ns.Money(c) end
local FRESH = 2 * 3600 -- buy suggestions need a scan at most this old

local function Num(x)
  if x < 10 then return string.format("%.1f", x) end
  return string.format("%d", math.floor(x + 0.5))
end

-- Walks the cheapest price levels: how many units can be bought at or below maxPrice, and for how much.
local function BuyUpTo(lv, maxPrice, maxUnits, budget)
  local units, cost = 0, 0
  for i = 1, #lv, 2 do
    local p, c = lv[i], lv[i + 1]
    if p > maxPrice or units >= maxUnits then break end
    if cost + p * c > budget then
      c = math.floor((budget - cost) / p)
      if c <= 0 then break end
    end
    units, cost = units + c, cost + p * c
  end
  return units, cost
end

function A.Item(key, it, now, own, budget, fresh, Add)
  local cur = it.cur
  local Data = ns.Data
  local cut = ns.AH_CUT
  local id = ns.IdFromKey(key)
  local lv = cur.lv or {}
  local base, vol, conf, nDays = Data.Stats(it, now)
  local rate = Data.Rate(it)
  local slope, r2, predicted = Data.Trend(it, 7)
  local function Sug(kind, t)
    t.key, t.kind, t.name, t.q = key, kind, it.n, it.q
    return t
  end
  local rateText = rate and ("Sells about " .. Num(rate) .. " a day (estimate).")
    or "Sale rate not known yet (needs scans a few hours apart)."
  local histText = base and (nDays >= 3 and (nDays .. " days") or "a few scans")

  -- Vendor flip
  if fresh and lv[1] then
    local vend = it.v
    if not vend and id then
      vend = select(11, GetItemInfo(id))
      if vend and vend > 0 then it.v = vend end
    end
    if vend and vend > 0 and lv[1] < vend then
      local units, cost = BuyUpTo(lv, vend - 1, math.huge, budget)
      if units > 0 then
        Add(Sug("Vendor", {
          action = string.format("Buy %d, sell them to a vendor", units),
          cost = cost, profit = units * vend - cost, conf = 1, units = units, maxPrice = vend - 1,
          reasons = {
            string.format("Listed from %s each, and any vendor pays %s.", Money(lv[1]), Money(vend)),
            "No risk: the profit is locked in when you buy.",
          },
        }))
      end
    end
  end

  if not base then return end
  local falling = slope and slope < -0.02 and r2 >= 0.5

  -- Snipe / Dip
  if fresh and lv[1] and vol <= 0.35 then
    local thr = math.floor(base * (1 - math.max(0.25, 2 * vol)))
    if lv[1] <= thr then
      local maxUnits = rate and math.max(1, rate * 7) or math.max(1, cur.qty * 0.25)
      local units, cost = BuyUpTo(lv, thr, maxUnits, budget)
      local resale = base * (1 - cut)
      local profit = units * resale - cost
      if units > 0 and profit > 0 then
        local dip = cur.mv > 0 and cur.mv < base * 0.85
        local r = {
          string.format("Normal price %s (median of %s). Cheapest now %s, %d%% below.",
            Money(base), histText, Money(lv[1]), (1 - lv[1] / base) * 100),
          dip and string.format("The whole market is low (%s vs %s normal): buy and hold until it recovers.",
            Money(cur.mv), Money(base))
            or "Only a few listings are this cheap: buy them and relist at the normal price.",
          rateText,
        }
        if rate then r[#r + 1] = string.format("%d units is about %s days of sales.", units, Num(units / math.max(rate, 0.01))) end
        if falling then r[#r + 1] = string.format("|cffff6060The price fell %.1f%% a day this week, so this is risky.|r", -slope * 100) end
        r[#r + 1] = string.format("Relist at about %s each; after the 5%% AH cut you get %s.", Money(base), Money(resale))
        Add(Sug(dip and "Dip" or "Snipe", {
          action = string.format("Buy %d up to %s each", units, Money(thr)),
          cost = cost, profit = profit, units = units, maxPrice = thr, reasons = r,
          conf = conf * (rate and 1 or 0.6) * (falling and 0.5 or 1),
          weight = rate and math.min(1, rate * 7 / units) or 0.5,
        }))
      end
    end
  end

  -- Rising
  if fresh and rate and lv[1] and slope and slope >= 0.02 and r2 >= 0.6 and predicted and lv[1] <= predicted then
    local units, cost = BuyUpTo(lv, predicted, math.max(1, math.floor(rate * 3)), budget)
    local target = predicted * (1 + slope * 3)
    local profit = units * target * (1 - cut) - cost
    if units > 0 and profit > 0 then
      Add(Sug("Rising", {
        action = string.format("Buy %d up to %s, sell in ~3 days", units, Money(predicted)),
        cost = cost, profit = profit, units = units, maxPrice = math.floor(predicted), conf = conf * r2 * 0.6,
        reasons = {
          string.format("The price rose %.1f%% a day over the last week (trend fit %d%%).", slope * 100, r2 * 100),
          string.format("You can still buy at %s, at or below the trend line (%s).", Money(lv[1]), Money(predicted)),
          rateText,
          "Trends end without warning, so the confidence is lowered.",
        },
      }))
    end
  end

  -- Weekly pattern
  if rate and conf >= 0.5 then
    local loW, loF, hiW, hiF = Data.Weekdays(it)
    if loW and hiF - loF >= 0.15 then
      local _, today = Data.DayInfo(now)
      local units = math.max(1, math.floor(rate * 7))
      local buyP, sellP = base * loF, base * hiF
      local profit = units * (sellP * (1 - cut) - buyP)
      if profit > 0 then
        local W = ns.WEEKDAYS
        local now_ = today == loW
        Add(Sug("Pattern", {
          action = now_ and string.format("Buy %d today, sell on %s", units, W[hiW])
            or string.format("Buy on %s, sell on %s", W[loW], W[hiW]),
          cost = units * buyP, profit = profit, units = units, maxPrice = math.floor(buyP), conf = conf,
          weight = now_ and 1 or 0.35,
          reasons = {
            string.format("Over the last %d days, %s is %d%% below normal and %s is %d%% above.",
              #it.d / 6, W[loW], (1 - loF) * 100, W[hiW], (hiF - 1) * 100),
            string.format("Buy around %s, sell around %s.", Money(buyP), Money(sellP)),
            rateText,
            now_ and "|cff40ff40Today is the cheap day.|r" or "Ranked lower because today isn't the cheap day.",
          },
        }))
      end
    end
  end

  -- Selling what we own
  if own > 0 and conf >= 0.2 then
    local ownText = string.format("You have %d in bags/bank across your characters here.", own)
    local units = rate and math.min(own, math.max(1, math.ceil(rate * 3))) or own
    local high = base * (1 + math.max(0.15, 2 * vol))
    if fresh and cur.min > 0 and cur.min >= high then
      Add(Sug("Sell", {
        action = string.format("Post %d at %s each", units, Money(math.max(1, cur.min - 1))),
        profit = units * (cur.min - base) * (1 - cut), conf = conf, units = units,
        reasons = {
          string.format("The cheapest listing (%s) is %d%% above the normal %s.", Money(cur.min), (cur.min / base - 1) * 100, Money(base)),
          ownText, rateText,
          "Profit = extra gold compared with selling at the normal price.",
        },
      }))
    elseif fresh and cur.qty == 0 then
      local price = base * 1.2
      Add(Sug("Sell", {
        action = string.format("Post %d at about %s - nobody else is selling", units, Money(price)),
        profit = units * (price - base) * (1 - cut), conf = conf * 0.8, units = units,
        reasons = {
          string.format("No listings right now; the normal price is %s, so you can ask more.", Money(base)),
          ownText, rateText,
        },
      }))
    elseif slope and slope <= -0.03 and r2 >= 0.6 then
      Add(Sug("Sell", {
        action = string.format("Sell your %d soon - the price is falling", own),
        profit = own * base * (-slope) * 3 * (1 - cut), conf = conf * r2, units = own,
        reasons = {
          string.format("The price fell %.1f%% a day over the last week (trend fit %d%%).", -slope * 100, r2 * 100),
          ownText,
          "Profit = what three more days of the decline would cost you.",
        },
      }))
    end
  end
end

function A.Crafts(R, now, Add)
  local vendor = AHAdvisorDB.vendor
  local cut = ns.AH_CUT
  local function Cost(id) -- cheapest known way to get one
    local v = vendor[id]
    local it = R.items[tostring(id)]
    local ah
    if it and it.cur then
      ah = (it.cur.mv > 0 and it.cur.mv) or ns.Data.Stats(it, now)
    end
    if v and (not ah or v <= ah) then return v, "vendor" end
    if ah then return ah, "AH" end
  end
  local n = 0
  for id, rec in pairs(R.recipes) do
    local key = tostring(id)
    local it = R.items[key]
    if it and it.cur then
      local base, _, conf = ns.Data.Stats(it, now)
      local sell = base
      if sell and it.cur.mv > 0 then sell = math.min(sell, it.cur.mv) end
      if sell then
        local cost, lines, missing = 0, {}, nil
        for i = 1, #rec.r, 2 do
          local rid, cnt = rec.r[i], rec.r[i + 1]
          local p, src = Cost(rid)
          local rit = R.items[tostring(rid)]
          local rname = GetItemInfo(rid) or (rit and rit.n) or ("item " .. rid)
          if not p then missing = rname break end
          cost = cost + p * cnt
          lines[#lines + 1] = string.format("   %dx %s: %s (%s)", cnt, rname, Money(p * cnt), src)
        end
        local per = sell * (1 - cut) * rec.made - cost
        if not missing and per > 0 and per >= cost * 0.1 then
          local rate = ns.Data.Rate(it)
          local crafts = rate and math.max(1, math.floor(rate * 3 / rec.made)) or 1
          local who = {}
          for name in pairs(rec.who or {}) do who[#who + 1] = name end
          local r = {
            string.format("Sells for about %s%s; after the AH cut %s.", Money(sell),
              rec.made ~= 1 and string.format(" (x%s per craft)", Num(rec.made)) or "", Money(sell * (1 - cut) * rec.made)),
            string.format("Reagents cost %s per craft:", Money(cost)),
          }
          for _, l in ipairs(lines) do r[#r + 1] = l end
          r[#r + 1] = string.format("Profit %s per craft (%d%% margin).", Money(per), per / math.max(cost, 1) * 100)
          r[#r + 1] = rate and ("Sells about " .. Num(rate) .. " a day (estimate).") or "Sale rate not known yet."
          if #who > 0 then r[#r + 1] = "Known by: " .. table.concat(who, ", ") end
          Add({
            key = key, kind = "Craft", name = it.n or rec.name, q = it.q,
            action = string.format("Craft %d (%s each to make)", crafts, Money(cost)),
            cost = crafts * cost, profit = crafts * per, units = crafts, conf = conf * (rate and 1 or 0.6),
            weight = 1, reasons = r,
          })
        end
      end
    end
    n = n + 1
    if n % 20 == 0 then ns.Yield() end
  end
end

function A.Compute()
  local R = ns.R()
  local s = ns.settings
  local now = time()
  local out = {}
  local owned = ns.OwnedCounts()
  local budget = s.useBudget and GetMoney() or math.huge
  local fresh = now - (R.lastScan or 0) <= FRESH
  local function Add(sug)
    if (sug.profit or 0) >= s.minProfit and (sug.conf or 0) >= s.minConf then
      sug.score = sug.profit * sug.conf * (sug.weight or 1)
      out[#out + 1] = sug
    end
  end
  local n = 0
  for key, it in pairs(R.items) do
    if it.cur then A.Item(key, it, now, owned[key] or 0, budget, fresh, Add) end
    n = n + 1
    if n % 25 == 0 then ns.Yield() end
  end
  A.Crafts(R, now, Add)
  table.sort(out, function(a, b) return a.score > b.score end)
  A.list, A.time, A.fresh = out, now, fresh
end

function A.Run()
  if A.running then A.again = true return end
  A.running = true
  ns.RunJob(function()
    repeat
      A.again = false
      A.Compute()
    until not A.again
    A.running = false
    if ns.UI then ns.UI.Refresh() end
  end)
end
