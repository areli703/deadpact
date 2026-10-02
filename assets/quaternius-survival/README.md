# Quaternius "LowPoly Survival Pack" (Sept 2020)

53 low-poly survival props, sourced from the OpenGameArt mirror of Quaternius's
official release (Google Drive was quota-blocked — "too many users have
downloaded recently" — so we pulled the identical archive from OpenGameArt,
which is the same CC0 distribution).

- **License:** CC0 1.0 Universal (Public Domain Dedication) — see `LICENSE.txt`.
  Free for personal **and commercial** use, no attribution required.
- **Source:** https://opengameart.org/content/lowpoly-survival-pack
- **Author:** Quaternius — https://quaternius.com — https://www.patreon.com/quaternius
- **Formats included:** `.fbx` and `.obj`/`.mtl`.
  (The original `.blend` sources are omitted — 28 MB of Blender files that
  Roblox cannot import and that we do not need.)

## Why these formats

Roblox Studio's **3D Importer** (Asset Manager → Import) accepts `.fbx` and
`.obj`. **Roblox cannot load these files at runtime** — they must be imported
into Studio once, which publishes them as Roblox Mesh assets with their own
`rbxassetid://` IDs. A Roblox account with upload rights is required for that
step; it cannot be done from this repo.

## Model index → planned in-game use

**Heat sources / light (Feature: heat & cooling)**
| Model | Use |
| --- | --- |
| `Bonfire`, `Bonfire_Fire` | Placed campfire at safe zones; fuel-fed warmth radius |
| `WoodenTorch`, `WoodenTorch_Fire` | Tier-mounted torch; small warmth + light |
| `Match`, `Match_Fire`, `Match_Burnt` | Ignition consumable |

**Safe zones / shelter (Feature: checkpoints)**
| Model | Use |
| --- | --- |
| `Tent` | Safe-zone dressing at checkpoint pads |
| `Backpack` | Scavenging stake / stash prop |
| `FirstAidKit`, `Bandages` | Health-regen dressing + loot |
| `WoodLog` | Fuel for fires |

**Scavenging / tools (Feature: loot)**
| Model | Use |
| --- | --- |
| `Axe`, `Knife`, `Shovel` | Melee + resource tools |
| `Pan`, `Pan_Small`, `Pot`, `Pot_Small` | Cookware / loot |
| `Can_Closed`, `Can_Open`, `Can_Broken`, `Can_Red` | Food loot |
| `WaterBottle_1/2/3` | Water loot |
| `Compass_Closed`, `Compass_Open` | Navigation prop |
| `Radio`, `Phone`, `Battery_Big`, `Battery_Small`, `GasCan`, `PropaneTank` | Scrap / fuel |
| `FlareGun`, `Matchbox`, `BearTrap_Closed`, `BearTrap_Open` | Utility |

**Combat**
| Model | Use |
| --- | --- |
| `Pistol_1`, `Pistol_2`, `Revolver_1/2/3` | Sidearms |
| `Shotgun_1`, `Shotgun_2`, `Shotgun_SawedOff`, `Shotgun_ShortStock` | Shotguns |
| `Axe`, `Knife`, `Shovel` | Melee |

**World dressing**
| Model | Use |
| --- | --- |
| `Tent`, `Trashcan`, `Raft`, `Raft_Paddle`, `WoodLog` | District set-dressing |
