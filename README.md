# Themed Buildings

A UCP3 module for Stronghold Crusader: chapels, churches and cathedrals take the look of their
owner's lord - European lords build Christian buildings, Arabian lords build mosques. See
[module/locale/description-en.md](module/locale/description-en.md).

## In the game

Each building has two pictures: the one in the game files and a themed one this module brings.
Theme packs can set `themed-buildings.chapel`, `themed-buildings.church` and
`themed-buildings.cathedral` to `european` or `arabian` to match their installed artwork.
The defaults are European for the chapel and cathedral and Arabian for the church.
Every player of the other side gets the themed picture. A ruined cathedral becomes a ruined grand mosque if the game's
tile_churches.gm1 has the ruin (vanilla does, Reconquista's does not).

The lord's side is the game's own: the AI lords keep theirs (custom AIs from aiSwapper too), and
you get the side of the lord you play. Nothing is saved in maps or saves. Needs
gmResourceModifier.

## Vanilla and Recommended

Every switch of the module is off by default, so the module alone installs nothing. Two plugins
in this repository form the Themed Buildings family in the launcher:
`themed-buildings-recommended` (offered first) switches on the themed buildings and their
placement preview, `themed-buildings-vanilla` keeps everything off. Plugins that build on the
module set the options they need themselves.

## What is in here

| Path | What |
| --- | --- |
| `module/` | the module (`init.lua`, options, locale, `resources/tile_churches_themed.gm1`) |
| `tools/build_gm1.py` | slices the themed PNGs into `tile_churches_themed.gm1` |
| `tools/publish.py` | copies `module/` into the game's `ucp/modules/themed-buildings-<version>` |

## Working on it

1. Edit the PNGs (Reconquista's `resources/themed buildings`): grand_mosque 414, church 286,
   small_mosque 190 px wide, the footprint's front corner on the bottom row.
2. `python tools/build_gm1.py --check` - rebuilds the sheet and draws it back into `check/`.
3. `python tools/publish.py --bump`, then F5 in the UCP3 GUI.

## How it works

* At game start the church sheet (gm 49) is copied into a free gm slot and gmResourceModifier
  loads the themed sheet into it.
* renderMap reads each map tile's picture twice (ground diamonds, building strips); both reads
  are hooked and a church-sheet picture is moved to the themed slot when the owner's lord
  side differs from the side the game files show.
* The side comes from the game's lord type function, asked once per player per tick.
