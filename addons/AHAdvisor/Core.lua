-- AHAdvisor - core: saved data, helpers, background worker, and the small collectors
-- (bags/bank, vendor prices, profession recipes) that the analysis needs.
local ADDON, ns = ...

ns.VERSION = "1.0.0"
ns.AH_CUT = 0.05          -- the auction house keeps 5% of a sale (faction auction house)
ns.WEEKDAYS = { "Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat" }

local DEFAULTS = {
  minProfit = 2000,       -- 20s: smaller suggestions are hidden
  minConf = 0.3,          -- 0..1: suggestions the history can't back up are hidden
  useBudget = true,       -- limit buy suggestions to the gold on this character
  autoOpen = true,        -- show the window when the auction house opens
}

---------------------------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------------------------
function ns.Print(fmt, ...)
  DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99AHAdvisor|r: " .. string.format(fmt, ...))
end

function ns.Money(c)
  c = math.floor((c or 0) + 0.5)
  local neg = c < 0
  if neg then c = -c end
  local g, s, cp = math.floor(c / 10000), math.floor(c / 100) % 100, c % 100
  local t
  if g > 0 then
    t = string.format("%d|cffffd700g|r %02d|cffc7c7cfs|r", g, s)
  elseif s > 0 then
    t = string.format("%d|cffc7c7cfs|r %02d|cffeda55fc|r", s, cp)
  else
    t = string.format("%d|cffeda55fc|r", cp)
  end
  return neg and ("-" .. t) or t
end

-- "1g50s", "75s", "30c" or a bare number of gold -> copper
function ns.ParseMoney(s)
  s = (s or ""):lower():gsub("%s", "")
  if s:match("^%d+%.?%d*$") then return math.floor(tonumber(s) * 10000) end
  local total, found = 0, false
  for n, u in s:gmatch("(%d+)([gsc])") do
    found = true
    total = total + tonumber(n) * ((u == "g" and 10000) or (u == "s" and 100) or 1)
  end
  return found and total or nil
end

-- Items are keyed by item id, plus the random suffix ("of the Bear") when there is one,
-- because "Bandit Cloak of the Bear" and "... of the Eagle" are different markets.
function ns.KeyFromLink(link)
  if type(link) ~= "string" then return nil end
  local id, rest = link:match("item:(%d+):?([%-%d:]*)")
  if not id then return nil end
  local parts = { strsplit(":", rest or "") }
  local suffix = tonumber(parts[6]) -- enchant, gem1..gem4, suffix
  if suffix and suffix ~= 0 then return id .. ":" .. suffix end
  return id
end

function ns.IdFromKey(key)
  return tonumber(tostring(key):match("^(%d+)"))
end

function ns.Median(t)
  local n = #t
  if n == 0 then return nil end
  local c = {}
  for i = 1, n do c[i] = t[i] end
  table.sort(c)
  if n % 2 == 1 then return c[(n + 1) / 2] end
  return (c[n / 2] + c[n / 2 + 1]) / 2
end

function ns.RealmKey()
  return (GetRealmName() or "?") .. "-" .. (UnitFactionGroup("player") or "?")
end

function ns.R()
  local db = AHAdvisorDB
  local rk = ns.RealmKey()
  local r = db.realms[rk]
  if not r then
    r = { items = {}, sig = {}, recipes = {}, lastScan = 0, scans = 0 }
    db.realms[rk] = r
  end
  r.recipes = r.recipes or {}
  return r
end

function ns.Inv()
  local db = AHAdvisorDB
  local rk = ns.RealmKey()
  db.inv[rk] = db.inv[rk] or {}
  return db.inv[rk]
end

-- Every character of ours on this realm/faction: their auctions are not "deals" for us.
function ns.MyChars()
  local set = {}
  local realm = GetRealmName() or ""
  for name in pairs(ns.Inv()) do
    set[name] = true
    set[name .. "-" .. realm] = true
    set[name .. "-" .. realm:gsub("%s", "")] = true
  end
  local me = UnitName("player")
  if me then set[me] = true end
  return set
end

-- Units of an item key held in bags/bank by all our characters on this realm/faction.
function ns.OwnedCounts()
  local owned = {}
  for _, c in pairs(ns.Inv()) do
    for _, where in ipairs({ "bags", "bank" }) do
      for key, n in pairs(c[where] or {}) do owned[key] = (owned[key] or 0) + n end
    end
  end
  return owned
end

---------------------------------------------------------------------------------------------
-- Background worker: long jobs run as coroutines, a few milliseconds per frame, so a scan of
-- tens of thousands of auctions does not freeze the game.
---------------------------------------------------------------------------------------------
local jobs = {}
local worker = CreateFrame("Frame")
worker:Hide()
ns.deadline = 0
worker:SetScript("OnUpdate", function(self)
  local deadline = debugprofilestop() + 12
  while jobs[1] do
    ns.deadline = deadline
    local co = jobs[1]
    local ok, err = coroutine.resume(co)
    if not ok then
      table.remove(jobs, 1)
      geterrorhandler()(err)
    elseif coroutine.status(co) == "dead" then
      table.remove(jobs, 1)
    end
    if debugprofilestop() >= deadline then return end
  end
  self:Hide()
end)

function ns.RunJob(fn)
  jobs[#jobs + 1] = coroutine.create(fn)
  worker:Show()
end

function ns.Yield()
  if coroutine.running() and debugprofilestop() >= ns.deadline then coroutine.yield() end
end

---------------------------------------------------------------------------------------------
-- Bags and bank
---------------------------------------------------------------------------------------------
local function NumSlots(bag)
  if C_Container and C_Container.GetContainerNumSlots then return C_Container.GetContainerNumSlots(bag) or 0 end
  return GetContainerNumSlots and GetContainerNumSlots(bag) or 0
end

local function SlotItem(bag, slot)
  if C_Container and C_Container.GetContainerItemInfo then
    local info = C_Container.GetContainerItemInfo(bag, slot)
    if info then return info.hyperlink, info.stackCount, info.isBound end
    return nil
  end
  local _, count, _, _, _, _, link = GetContainerItemInfo(bag, slot)
  return link, count
end

local function ReadBags(list)
  local t = {}
  for _, bag in ipairs(list) do
    for slot = 1, NumSlots(bag) do
      local link, count, bound = SlotItem(bag, slot)
      local key = not bound and ns.KeyFromLink(link)
      if key then t[key] = (t[key] or 0) + (count or 1) end
    end
  end
  return t
end

local function Me()
  local inv = ns.Inv()
  local name = UnitName("player")
  inv[name] = inv[name] or {}
  return inv[name]
end

function ns.UpdateBags()
  local bags = {}
  for b = 0, (NUM_BAG_SLOTS or 4) do bags[#bags + 1] = b end
  Me().bags = ReadBags(bags)
end

function ns.UpdateBank()
  local bags = { BANK_CONTAINER or -1 }
  local first = (NUM_BAG_SLOTS or 4) + 1
  for b = first, first + (NUM_BANKBAGSLOTS or 6) - 1 do bags[#bags + 1] = b end
  Me().bank = ReadBags(bags)
end

---------------------------------------------------------------------------------------------
-- Vendor prices: learned whenever a merchant window is open (thread, vials, flux...),
-- so crafting costs can use them.
---------------------------------------------------------------------------------------------
local function LearnVendor()
  if not GetMerchantNumItems then return end
  for i = 1, GetMerchantNumItems() do
    local _, _, price, quantity, numAvailable = GetMerchantItemInfo(i)
    local link = GetMerchantItemLink(i)
    local id = link and tonumber(link:match("item:(%d+)"))
    if id and price and price > 0 and numAvailable == -1 then
      AHAdvisorDB.vendor[id] = price / math.max(1, quantity or 1)
    end
  end
end

---------------------------------------------------------------------------------------------
-- Recipes: learned whenever a profession window is open.
---------------------------------------------------------------------------------------------
local function LearnRecipes()
  if not GetNumTradeSkills then return end
  local R = ns.R()
  local me = UnitName("player")
  for i = 1, GetNumTradeSkills() do
    local name, kind = GetTradeSkillInfo(i)
    if kind and kind ~= "header" then
      local link = GetTradeSkillItemLink(i)
      local id = link and tonumber(link:match("item:(%d+)"))
      if id then
        local lo, hi = GetTradeSkillNumMade(i)
        lo = lo or 1
        local rec = { made = (lo + (hi or lo)) / 2, r = {}, name = name, who = {} }
        local ok = true
        for r = 1, GetTradeSkillNumReagents(i) do
          local _, _, count = GetTradeSkillReagentInfo(i, r)
          local rl = GetTradeSkillReagentItemLink(i, r)
          local rid = rl and tonumber(rl:match("item:(%d+)"))
          if not rid or not count then ok = false break end
          rec.r[#rec.r + 1] = rid
          rec.r[#rec.r + 1] = count
        end
        if ok and #rec.r > 0 then
          local old = R.recipes[id]
          if old and old.who then rec.who = old.who end
          rec.who[me] = true
          R.recipes[id] = rec
        end
      end
    end
  end
end

---------------------------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------------------------
local pending = {}
local function Later(name, fn, delay)
  if pending[name] then return end
  pending[name] = true
  C_Timer.After(delay or 0.5, function() pending[name] = nil; fn() end)
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("ADDON_LOADED")
ev:RegisterEvent("PLAYER_LOGIN")
ev:RegisterEvent("BAG_UPDATE")
ev:RegisterEvent("BANKFRAME_OPENED")
ev:RegisterEvent("BANKFRAME_CLOSED")
ev:RegisterEvent("PLAYERBANKSLOTS_CHANGED")
ev:RegisterEvent("MERCHANT_SHOW")
ev:RegisterEvent("MERCHANT_UPDATE")
ev:RegisterEvent("TRADE_SKILL_SHOW")
ev:RegisterEvent("TRADE_SKILL_UPDATE")
ev:RegisterEvent("AUCTION_HOUSE_SHOW")
ev:RegisterEvent("AUCTION_HOUSE_CLOSED")
ev:RegisterEvent("AUCTION_ITEM_LIST_UPDATE")

local bankOpen = false
ev:SetScript("OnEvent", function(_, event, arg1)
  if event == "ADDON_LOADED" and arg1 == ADDON then
    AHAdvisorDB = AHAdvisorDB or {}
    local db = AHAdvisorDB
    db.realms = db.realms or {}
    db.inv = db.inv or {}
    db.vendor = db.vendor or {}
    db.settings = db.settings or {}
    for k, v in pairs(DEFAULTS) do
      if db.settings[k] == nil then db.settings[k] = v end
    end
    ns.settings = db.settings
  elseif event == "PLAYER_LOGIN" then
    ns.UpdateBags()
    if ns.Tooltip then ns.Tooltip.Init() end
  elseif event == "BAG_UPDATE" then
    Later("bags", function()
      ns.UpdateBags()
      if bankOpen then ns.UpdateBank() end
    end, 1)
  elseif event == "BANKFRAME_OPENED" then
    bankOpen = true
    ns.UpdateBank()
  elseif event == "PLAYERBANKSLOTS_CHANGED" then
    Later("bank", ns.UpdateBank, 1)
  elseif event == "BANKFRAME_CLOSED" then
    bankOpen = false
  elseif event == "MERCHANT_SHOW" or event == "MERCHANT_UPDATE" then
    Later("vendor", LearnVendor, 0.5)
  elseif event == "TRADE_SKILL_SHOW" or event == "TRADE_SKILL_UPDATE" then
    Later("recipes", LearnRecipes, 0.5)
  elseif event == "AUCTION_HOUSE_SHOW" then
    ns.ahOpen = true
    ns.Scan.OnOpen()
    if ns.UI then ns.UI.OnAuctionHouse(true) end
  elseif event == "AUCTION_HOUSE_CLOSED" then
    ns.ahOpen = false
    ns.Scan.Abort("the auction house was closed")
    if ns.UI then ns.UI.OnAuctionHouse(false) end
  elseif event == "AUCTION_ITEM_LIST_UPDATE" then
    ns.Scan.OnListUpdate()
  end
end)

---------------------------------------------------------------------------------------------
-- Slash commands
---------------------------------------------------------------------------------------------
SLASH_AHADVISOR1 = "/aha"
SLASH_AHADVISOR2 = "/ahadvisor"
SlashCmdList.AHADVISOR = function(msg)
  local cmd, rest = (msg or ""):match("^%s*(%S*)%s*(.-)%s*$")
  cmd = (cmd or ""):lower()
  local s = ns.settings
  if cmd == "" then
    ns.UI.Toggle()
  elseif cmd == "scan" then
    ns.Scan.Start()
  elseif cmd == "minprofit" then
    local v = ns.ParseMoney(rest)
    if v then s.minProfit = v; ns.Print("Hiding suggestions below %s.", ns.Money(v)); ns.Analysis.Run()
    else ns.Print("Usage: /aha minprofit 50s   (or 1g, 1g50s)") end
  elseif cmd == "minconf" then
    local v = tonumber(rest)
    if v and v >= 0 and v <= 100 then s.minConf = v / 100; ns.Print("Minimum confidence %d%%.", v); ns.Analysis.Run()
    else ns.Print("Usage: /aha minconf 30   (0-100)") end
  elseif cmd == "budget" then
    s.useBudget = not s.useBudget
    ns.Print("Limit buys to the gold on this character: %s.", s.useBudget and "on" or "off")
    ns.Analysis.Run()
  elseif cmd == "autoopen" then
    s.autoOpen = not s.autoOpen
    ns.Print("Open with the auction house: %s.", s.autoOpen and "on" or "off")
  elseif cmd == "status" then
    local R = ns.R()
    local n = 0
    for _ in pairs(R.items) do n = n + 1 end
    local recipes = 0
    for _ in pairs(R.recipes) do recipes = recipes + 1 end
    ns.Print("%d scans, %d items tracked, %d recipes known. Last scan: %s.", R.scans or 0, n, recipes,
      (R.lastScan or 0) > 0 and date("%a %H:%M", R.lastScan) or "never")
  elseif cmd == "reset" and rest == "confirm" then
    AHAdvisorDB.realms[ns.RealmKey()] = nil
    ns.Print("Price history for %s deleted.", ns.RealmKey())
    ns.Analysis.Run()
  else
    ns.Print("/aha - open the advisor")
    ns.Print("/aha scan - scan the auction house (it must be open)")
    ns.Print("/aha minprofit 50s - hide smaller suggestions (now %s)", ns.Money(s.minProfit))
    ns.Print("/aha minconf 30 - hide suggestions below this confidence %% (now %d)", s.minConf * 100)
    ns.Print("/aha budget - toggle limiting buys to your gold (now %s)", s.useBudget and "on" or "off")
    ns.Print("/aha autoopen - toggle opening with the auction house (now %s)", s.autoOpen and "on" or "off")
    ns.Print("/aha status - what has been collected")
    ns.Print("/aha reset confirm - delete this realm's price history")
  end
end
