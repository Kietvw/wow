-- AHAdvisor - auction house scanner (Classic auction API).
-- Prefers the "get all" query (whole auction house in one reply, allowed once every 15 minutes);
-- otherwise it walks the pages, 50 auctions each.
local _, ns = ...
local S = {}
ns.Scan = S

local PER_PAGE = NUM_AUCTION_ITEMS_PER_PAGE or 50
local PAGE_TIMEOUT = 10

function S.Status(fmt, ...)
  local text = select("#", ...) > 0 and string.format(fmt, ...) or fmt
  S.statusText = text
  if ns.UI then ns.UI.SetStatus(text) end
end

function S.Busy() return S.state ~= nil end

function S.OnOpen()
  if not QueryAuctionItems then
    S.Status("This client's auction house API isn't supported.")
    return
  end
  local R = ns.R()
  local age = time() - (R.lastScan or 0)
  if (R.lastScan or 0) == 0 then
    S.Status("No scans yet - press Scan.")
  elseif age > 3600 then
    S.Status("Last scan %d h ago - press Scan for fresh suggestions.", math.floor(age / 3600))
  else
    S.Status("Last scan %d min ago.", math.floor(age / 60))
  end
end

local function RestoreBrowse(st)
  if st.unhooked and AuctionFrameBrowse then
    AuctionFrameBrowse:RegisterEvent("AUCTION_ITEM_LIST_UPDATE")
    st.unhooked = nil
  end
end

local function ReadAuction(st, i)
  local name, _, count, quality, _, _, _, _, _, buyout, _, _, _, owner, _, _, itemId = GetAuctionItemInfo("list", i)
  if not itemId or itemId == 0 then return end
  local key = ns.KeyFromLink(GetAuctionItemLink("list", i)) or tostring(itemId)
  local list = st.data[key]
  if not list then
    list = {}
    st.data[key] = list
  end
  local n = #list
  list[n + 1] = (count and count > 0) and count or 1
  list[n + 2] = buyout or 0
  list[n + 3] = (owner and st.mine[owner]) and 1 or 0
  if name and not st.names[key] then st.names[key], st.quality[key] = name, quality end
  st.count = st.count + 1
end

local function Finish(st)
  st.committing = true
  RestoreBrowse(st)
  S.Status("Saving %d auctions...", st.count)
  ns.RunJob(function()
    ns.Data.Commit(st)
    if S.state == st then S.state = nil end
    local items = 0
    for _ in pairs(st.data) do items = items + 1 end
    S.Status("Scanned %d auctions of %d items at %s.", st.count, items, date("%H:%M", st.t))
    ns.Analysis.Run()
  end)
end

function S.Start()
  if not ns.ahOpen then ns.Print("Open the auction house first.") return end
  if not QueryAuctionItems then ns.Print("This client's auction house API isn't supported.") return end
  if S.state then ns.Print("A scan is already running.") return end
  local _, canAll = CanSendAuctionQuery()
  local st = { t = time(), data = {}, names = {}, quality = {}, count = 0, mine = ns.MyChars() }
  S.state = st
  if canAll then
    st.mode = "all"
    if AuctionFrameBrowse then
      -- otherwise Blizzard's browse tab tries to draw every auction and the client stalls
      AuctionFrameBrowse:UnregisterEvent("AUCTION_ITEM_LIST_UPDATE")
      st.unhooked = true
    end
    st.waiting, st.sent = true, GetTime()
    QueryAuctionItems("", nil, nil, 0, false, nil, true, false, nil)
    S.Status("Full scan requested - the game may hang for a few seconds...")
    S.ticker:Show()
  else
    st.mode = "page"
    st.page, st.needQuery = 0, true
    S.Status("Full scan is on its 15 min cooldown - scanning page by page (don't search meanwhile).")
    S.ticker:Show()
  end
end

function S.Abort(why)
  local st = S.state
  if not st or st.committing then return end -- everything is read; let the save finish
  st.aborted = true
  RestoreBrowse(st)
  S.state = nil
  S.ticker:Hide()
  S.Status("Scan stopped: %s.", why)
end

function S.OnListUpdate()
  local st = S.state
  if not st or not st.waiting then return end
  st.waiting = false
  if st.mode == "all" then
    S.Status("Reading the auction house...")
    ns.RunJob(function()
      local n = GetNumAuctionItems("list")
      for i = 1, n do
        if st.aborted then return end
        ReadAuction(st, i)
        if i % 25 == 0 then
          if i % 2000 == 0 then S.Status("Reading auctions %d / %d...", i, n) end
          ns.Yield()
        end
      end
      if st.aborted then return end
      Finish(st)
    end)
  else
    local batch, total = GetNumAuctionItems("list")
    for i = 1, batch do ReadAuction(st, i) end
    st.page = st.page + 1
    local pages = math.max(1, math.ceil((total or 0) / PER_PAGE))
    if st.page >= pages then
      S.ticker:Hide()
      Finish(st)
    else
      st.needQuery = true
      S.Status("Scanning page %d / %d...", st.page + 1, pages)
    end
  end
end

-- page mode: send the next query as soon as the server allows one; full mode: give up on no reply
S.ticker = CreateFrame("Frame")
S.ticker:Hide()
S.ticker:SetScript("OnUpdate", function(self)
  local st = S.state
  if not st then self:Hide() return end
  if st.mode == "all" then
    if not st.waiting then self:Hide()
    elseif GetTime() - st.sent > 90 then S.Abort("no reply to the full scan - try again in 15 minutes") end
    return
  end
  if st.waiting and GetTime() - st.sent > PAGE_TIMEOUT then
    st.waiting, st.needQuery = false, true -- lost reply: ask again
  end
  if st.needQuery and CanSendAuctionQuery() then
    st.needQuery, st.waiting, st.sent = false, true, GetTime()
    QueryAuctionItems("", nil, nil, st.page, false, nil, false, false, nil)
  end
end)
