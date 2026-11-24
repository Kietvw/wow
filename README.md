# WoW addons

Personal addons for World of Warcraft Classic (Era, Anniversary and TBC Anniversary).

| Addon | What it does | Command |
|---|---|---|
| [LayerSwap](#layerswap-custom) | Shows which layer you are on and asks hosts for a swap | `/ls` |
| [AHAdvisor](#ahadvisor) | Scans the auction house, learns prices and suggests what to buy, sell and craft | `/aha` |

## Install

Copy an addon's folder from `addons/` into your `Interface/AddOns` directory, so the result is for example `Interface/AddOns/AHAdvisor/AHAdvisor.toc`.

---

## LayerSwap (custom)

A personal build of the LayerSwap addon by Adam5288. It shows which layer you are on and asks LayerSwap hosts for a swap to another layer.

### Changes from upstream

- **Hosting is off by default and stays off.** It no longer turns on at login, after a reset, or by itself. It turns on only when you switch it on with the Host button, the options checkbox or `/ls host`, and it stays as you set it.
- The combat restriction is removed.
- The players who respond to an ask are shown in a list.

### Usage

Type `/ls` in game to open the panel.

---

## AHAdvisor

Scans the auction house, keeps a price history per item, and turns it into ranked suggestions with an estimated profit and a confidence.

### Usage

1. Open the auction house. The Advisor window opens next to it (or use the **Advisor** button or `/aha`).
2. Press **Scan**. It uses the full scan when the game allows it (once every 15 minutes) and otherwise scans page by page. Don't search the auction house during a page-by-page scan.
3. Scan a few times a day, preferably a few hours apart. Suggestions appear after a few scans and get much better after about a week.
4. Hover a suggestion to see why it was made. Click it to search the item, shift-click to link it.

Item tooltips show the current market price, the normal price, estimated sales per day and the week's trend.

### Suggestions

| Type | Meaning |
|---|---|
| Vendor | Listed below what a vendor pays. No risk. |
| Snipe | A few listings far below the normal price. Buy and relist at normal. |
| Dip | The whole market is below normal. Buy and hold until it recovers. |
| Rising | Steady price rise over the past week, and you can still buy at or below the trend. |
| Pattern | Reliably cheaper on one weekday than another (needs two weeks of data). |
| Sell | Something you own is priced unusually high, nobody else sells it, or its price is falling. |
| Craft | One of your recipes sells for clearly more than its reagents cost. |

Buy suggestions are limited to about a week of the item's sales and to the gold on your current character, and include the 5% auction house cut. "Owned" counts bags and bank across your characters on the same realm and faction.

For craft suggestions, open each crafter's profession window once so the recipes are learned, and open a trade goods vendor once so vendor prices (vials, thread, flux) are known. Enchanting is not covered.

### How it works

- **Market value** per scan: the average price of the cheapest 15–30% of listed units, with outliers trimmed.
- **Normal price**: the median daily market value of the last 14 days, plus how much the price usually swings.
- **Sales per day**: estimated from listings near the market price that disappear between scans up to 12 hours apart. A cancelled auction looks the same as a sold one, so this is an estimate.
- **Trend**: a least-squares line through the last 7 days.
- **Weekday pattern**: each weekday's average price compared with the item's median.

### Commands

| Command | Effect |
|---|---|
| `/aha` | Open or close the window |
| `/aha scan` | Scan the auction house (it must be open) |
| `/aha minprofit 50s` | Hide suggestions below this profit (default 20s) |
| `/aha minconf 30` | Hide suggestions below this confidence % (default 30) |
| `/aha budget` | Toggle limiting buys to the gold on this character |
| `/aha autoopen` | Toggle opening the window with the auction house |
| `/aha status` | Show how many scans, items and recipes are known |
| `/aha reset confirm` | Delete the price history for this realm and faction |
