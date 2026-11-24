-- AHAdvisor - price history and the statistics computed from it.
--
-- Per item (key = item id, or "id:suffix") the realm keeps:
--   cur  latest snapshot { t, mv, min, qty, lv = {price, units, price, units, ...} }
--        lv = cheapest price levels of other players' auctions (per unit), for buy suggestions
--   s    last MAX_SCANS scans, flat: t, mv, min, qty, t, mv, min, qty, ...
--   d    last MAX_DAYS days, flat: dayKey, weekday, mv, min, qty, scansThatDay, ...
--   su/st  estimated units sold / seconds observed (decaying), for a sales-per-day estimate
-- and R.sig[key] holds the previous scan's auctions ("count@buyout,...") to see which vanished.
local _, ns = ...
local D = {}
ns.Data = D

local MAX_SCANS, MAX_DAYS, MAX_LEVELS = 48, 28, 12
local HALF_LIFE = 7 * 86400   -- sales estimate forgets half of what it saw each week
local MAX_GAP = 12 * 3600     -- scans further apart than this can't tell sales from expiries

function D.DayInfo(t)
  local d = date("*t", t)
  return d.year * 1000 + d.yday, d.wday
end

-- Market value of one scan, in the spirit of the well-known AH addons: the average unit price
-- of the cheapest 15-30% of the units listed, cut short at a big price jump, then trimmed of
-- outliers. A single silly listing (too high or too low) therefore barely moves it.
-- `a` is sorted by unit price: { {unitPrice, count}, ... }
function D.MarketValue(a)
  local total = 0
  for i = 1, #a do total = total + a[i][2] end
  if total == 0 then return 0 end
  local lo, hi = total * 0.15, total * 0.30
  local units, sum, sumsq, last = 0, 0, 0, 0
  for i = 1, #a do
    local p, c = a[i][1], a[i][2]
    if units >= lo and (units >= hi or p > a[i - 1][1] * 1.2) then break end
    units, sum, sumsq, last = units + c, sum + p * c, sumsq + p * p * c, i
  end
  local mean = sum / units
  local sd = math.sqrt(math.max(0, sumsq / units - mean * mean))
  local s2, u2 = 0, 0
  for i = 1, last do
    local p, c = a[i][1], a[i][2]
    if math.abs(p - mean) <= 1.5 * sd + 0.5 then s2, u2 = s2 + p * c, u2 + c end
  end
  return u2 > 0 and (s2 / u2) or mean
end

local function round(x) return math.floor(x + 0.5) end

local function CountSold(prevSig, sig, ref)
  local have = {}
  for _, s in ipairs(sig) do have[s] = (have[s] or 0) + 1 end
  local sold = 0
  for s in prevSig:gmatch("[^,]+") do
    if (have[s] or 0) > 0 then
      have[s] = have[s] - 1
    else
      local c, b = s:match("^(%d+)@(%d+)$")
      c, b = tonumber(c), tonumber(b)
      -- a vanished auction priced near the market most likely sold; an overpriced one
      -- most likely expired or was cancelled
      if c and b and b / c <= ref * 1.3 then sold = sold + c end
    end
  end
  return sold
end

-- Adds one scan's auctions of one item. `list` is flat {count, buyout, isMine, ...} or nil
-- when the item was not on the auction house at all this scan.
function D.Ingest(R, key, it, list, now, dayKey, wd, prevScanT)
  local auctions, sig, qty = {}, {}, 0
  if list then
    for i = 1, #list, 3 do
      local count, buyout, mine = list[i], list[i + 1], list[i + 2]
      qty = qty + count
      if buyout > 0 then
        auctions[#auctions + 1] = { buyout / count, count, mine }
        sig[#sig + 1] = count .. "@" .. buyout
      end
    end
  end
  table.sort(auctions, function(a, b) return a[1] < b[1] end)
  local mv = round(D.MarketValue(auctions))
  local minP = auctions[1] and round(auctions[1][1]) or 0

  -- cheapest price levels, without our own auctions
  local lv = {}
  for _, a in ipairs(auctions) do
    if a[3] == 0 then
      local p, n = round(a[1]), #lv
      if n >= 2 and lv[n - 1] == p then
        lv[n] = lv[n] + a[2]
      elseif n < MAX_LEVELS * 2 then
        lv[n + 1], lv[n + 2] = p, a[2]
      else
        break
      end
    end
  end

  -- sales estimate from auctions that vanished since the previous scan
  local prevSig = R.sig[key]
  if prevSig and it.cur and it.cur.t == prevScanT then
    local dt = now - prevScanT
    local ref = D.Stats(it, now) or (it.cur.mv > 0 and it.cur.mv) or mv
    if dt > 0 and dt <= MAX_GAP and ref and ref > 0 then
      local f = 0.5 ^ (dt / HALF_LIFE)
      it.su = (it.su or 0) * f + CountSold(prevSig, sig, ref)
      it.st = (it.st or 0) * f + dt
    end
  end
  R.sig[key] = (#sig > 0) and table.concat(sig, ",") or nil

  it.cur = { t = now, mv = mv, min = minP, qty = qty, lv = lv }
  if qty > 0 then it.seen = now end

  local s = it.s
  s[#s + 1], s[#s + 2], s[#s + 3], s[#s + 4] = now, mv, minP, qty
  while #s > MAX_SCANS * 4 do
    for _ = 1, 4 do table.remove(s, 1) end
  end

  if mv > 0 then
    local d = it.d
    local n = #d
    if n >= 6 and d[n - 5] == dayKey then
      local c = d[n]
      d[n - 3] = round((d[n - 3] * c + mv) / (c + 1))
      d[n - 2] = math.min(d[n - 2], minP)
      d[n - 1] = round((d[n - 1] * c + qty) / (c + 1))
      d[n] = c + 1
    else
      d[n + 1], d[n + 2], d[n + 3], d[n + 4], d[n + 5], d[n + 6] = dayKey, wd, mv, minP, qty, 1
      while #d > MAX_DAYS * 6 do
        for _ = 1, 6 do table.remove(d, 1) end
      end
    end
  end
end

-- Runs inside a worker job: writes a finished scan into the history.
function D.Commit(st)
  local R = ns.R()
  local items = R.items
  local now = st.t
  local dayKey, wd = D.DayInfo(now)
  local prevScanT = R.lastScan or 0
  local n = 0
  for key, list in pairs(st.data) do
    local it = items[key]
    if not it then
      it = { s = {}, d = {} }
      items[key] = it
    end
    if st.names[key] then it.n, it.q = st.names[key], st.quality[key] end
    D.Ingest(R, key, it, list, now, dayKey, wd, prevScanT)
    n = n + 1
    if n % 25 == 0 then ns.Yield() end
  end
  for key, it in pairs(items) do
    if not st.data[key] then
      if now - (it.seen or 0) > 30 * 86400 then
        items[key], R.sig[key] = nil, nil
      elseif it.cur and it.cur.qty > 0 then
        D.Ingest(R, key, it, nil, now, dayKey, wd, prevScanT) -- sold out since the last scan
      end
    end
    n = n + 1
    if n % 50 == 0 then ns.Yield() end
  end
  R.lastScan = now
  R.scans = (R.scans or 0) + 1
end

---------------------------------------------------------------------------------------------
-- Statistics
---------------------------------------------------------------------------------------------

-- Normal price ("baseline") = median of the daily market values of the last 14 days,
-- leaving out today so today's price can be judged against it. Without three days of history
-- it falls back to the median of earlier scans, with a low confidence.
-- Returns base, volatility (median absolute deviation / base), confidence 0..1, days used.
function D.Stats(it, now)
  local today = D.DayInfo(now)
  local vals = {}
  local d = it.d
  for i = #d - 5, 1, -6 do
    if d[i] ~= today and d[i + 2] > 0 then
      vals[#vals + 1] = d[i + 2]
      if #vals >= 14 then break end
    end
  end
  local nDays = #vals
  local span = 0
  if nDays < 3 then
    vals = {}
    local s = it.s
    local oldest, newest
    for i = #s - 7, 1, -4 do -- skip the newest scan
      if s[i + 1] > 0 then
        vals[#vals + 1] = s[i + 1]
        newest = newest or s[i]
        oldest = s[i]
      end
    end
    if newest then span = newest - oldest end
  end
  if #vals < 3 then return nil end
  local base = ns.Median(vals)
  if not base or base <= 0 then return nil end
  local dev = {}
  for i, v in ipairs(vals) do dev[i] = math.abs(v - base) end
  local vol = ns.Median(dev) / base
  local conf
  if nDays >= 3 then
    conf = math.min(1, 0.4 + 0.6 * (nDays - 3) / 7)
  else
    conf = math.min(0.3, 0.1 + 0.2 * span / 86400)
  end
  conf = conf * (1 - math.min(0.5, vol))
  return base, vol, conf, nDays
end

-- Units sold per day, or nil when there is not yet enough overlap between scans to tell.
function D.Rate(it)
  if (it.st or 0) < 2 * 3600 then return nil end
  return (it.su or 0) / it.st * 86400
end

-- Least-squares trend over the last `days` daily market values.
-- Returns slope as a fraction of the average price per day, and r^2.
function D.Trend(it, days)
  local d = it.d
  local ys = {}
  for i = math.max(1, #d - days * 6 + 1), #d - 5, 6 do ys[#ys + 1] = d[i + 2] end
  local n = #ys
  if n < 4 then return nil end
  local sx, sy, sxx, sxy, syy = 0, 0, 0, 0, 0
  for x = 1, n do
    local y = ys[x]
    sx, sy, sxx, sxy, syy = sx + x, sy + y, sxx + x * x, sxy + x * y, syy + y * y
  end
  local den = n * sxx - sx * sx
  if den == 0 or sy == 0 then return nil end
  local slope = (n * sxy - sx * sy) / den
  local intercept = (sy - slope * sx) / n
  local vy = n * syy - sy * sy
  local r2 = vy > 0 and ((n * sxy - sx * sy) ^ 2) / (den * vy) or 0
  local mean = sy / n
  return slope / mean, r2, intercept + slope * (n + 1)
end

-- How each weekday's price compares to the item's usual price (needs two weeks of data).
-- Returns cheapest weekday, its factor, dearest weekday, its factor (e.g. 0.88 and 1.10).
function D.Weekdays(it)
  local d = it.d
  if #d < 14 * 6 then return nil end
  local vals = {}
  for i = 1, #d, 6 do vals[#vals + 1] = d[i + 2] end
  local med = ns.Median(vals)
  if not med or med <= 0 then return nil end
  local sum, cnt = {}, {}
  for i = 1, #d, 6 do
    local w = d[i + 1]
    sum[w] = (sum[w] or 0) + d[i + 2] / med
    cnt[w] = (cnt[w] or 0) + 1
  end
  local loW, loF, hiW, hiF
  for w = 1, 7 do
    if (cnt[w] or 0) >= 2 then
      local f = sum[w] / cnt[w]
      if not loF or f < loF then loW, loF = w, f end
      if not hiF or f > hiF then hiW, hiF = w, f end
    end
  end
  if not loW or loW == hiW then return nil end
  return loW, loF, hiW, hiF
end
