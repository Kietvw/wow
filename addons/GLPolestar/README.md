# Guidelime for Polestar

Plays [Guidelime](https://github.com/max-ri/Guidelime) guides in [Polestar](https://github.com/fitzforge/polestar), with Polestar's guide window, waypoint arrow and map markers.

The guides show in Polestar's guide menu under **Community guides > Guidelime guides**, one folder per guide group (for example "Sage"). You can switch them all off under Polestar's **Options > Community guides**.

## Where the guides come from

- **Guidelime guide addons** (Guidelime_Sage and the like). They need Guidelime itself installed and enabled, because their TOC depends on it. This addon catches each guide as the guide addon hands it to Guidelime. Guidelime keeps working as before.
- **Guidelime's custom guides**, the ones you wrote in Guidelime's editor.
- **Guides you paste in.** Type `/glp`, paste the guide's text (it starts with `[N ...]`), choose a folder name and press **Add guide**. Pasted guides are saved and come back at every login. Guidelime does not need to be installed for these.

## Install

Copy this `GLPolestar` folder into `Interface/AddOns`, next to `Polestar` and, if you use it, `Guidelime`. Keep the folder name. The game loads addons in alphabetical order, so `GLPolestar` loads before the `Guidelime_*` guide addons and can catch their guides. If it is renamed, it prints a message at login saying which guide addons it missed.

## Commands

| Command | What it does |
|---|---|
| `/glp` | Opens the paste window |
| `/glp list` | Lists every guide with its step count, or the reason it could not be converted |
| `/glp open <n>` | Opens guide number `n` from the list in Polestar |
| `/glp warnings <n>` | Shows what in guide `n` could not be converted |
| `/glp remove <n>` | Deletes a pasted guide. It leaves the guide menu after a `/reload` |

## How Guidelime codes are converted

Each line of a Guidelime guide becomes one Polestar step. The line's text becomes the step's note.

| Guidelime | Polestar |
|---|---|
| `[N 1-6 Title]`, `[D ...]`, `[GA ...]` | The guide's title, levels, description, faction, races and classes |
| `[NX 6-12 Title]` | The next guide. If there are several, Polestar offers the ones that fit the character |
| `[QA]`, `[QT]`, `[QC]` | Accept, turn in and complete goals. If `[QC id,n]` names an objective, the goal tracks only that objective |
| `[QW]` | An optional complete goal |
| `[G x,y Zone]` | A goto goal |
| `[L x,y Zone]` | The location of the line's quest goals |
| `[XP 10]`, `[XP 10.5]` | Reach level 10, or halfway through level 10 |
| `[H Place]`, `[S Place]`, `[F Place]`, `[P Place]` | Hearth, set hearth, fly and flight path goals. `[H]` without a place is a Hearthstone cast |
| `[T]`, `[V]`, `[R]` | Train at your class trainer, visit a vendor, repair |
| `[CI id,n]`, `[UI id]`, `[SP id]`, `[LE SP id]`, `[SK Skill n]` | Collect, use item (optional), cast, learn and skill goals |
| `[A Class,Race,Faction]` with `!` for "not" | Who the step is for |
| `[O]`, `[OC]` | Optional goal or step |
| A line with only text | A task you tick off by hand, as in Guidelime |

When Polestar's quest database is loaded, accept and turn-in goals also get their NPC and place, and objectives get their mob, item or object, so the arrow can lead there. Without it the arrow follows the guide's own `[G]` and `[L]` coordinates.

Not converted: reputation, item, spell and skill conditions in `[A]` and `[GA]`, `[OR]`, Guidelime's automatic coordinates and Lua event code in comments. Coordinates are read as Classic Era map coordinates, as Guidelime writes them.

## Credits

Guidelime is by Borick. This addon does not include any Guidelime code or guides. It reads the guides that the guide addons you install hand to Guidelime. Report a wrong step to the guide's author.
