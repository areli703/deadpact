# DEADPACT

> **Trust no one — or die alone.**

A third-person zombie survival game (PvPvE) for Roblox. Survivors scavenge a
night-time district, hunted by an escalating horde — and by each other. When two
players meet, the game stops and asks them a single question: **ally, fight, or
walk away?**

This repo is the **concept and art-direction package**: the design, and the two
screens that define the feel, rendered as actual pixels.

---

## See it

| Screen | Image |
|---|---|
| Main menu | `design/menu_main.png` |
| Pact encounter | `design/menu_pact.png` |

Both are rendered at 1280×720. The HTML/CSS that produced them is alongside:
`design/menu_main.html`, `design/menu_pact.html`.

To re-render either one (needs any headless Chromium):

```bash
chromium --headless=new --window-size=1280,720 \
  --screenshot=design/menu_main.png "file://$PWD/design/menu_main.html"
```

---

## The hook

Every other player is a **decision**, not just a target.

| Choice | You gain | You risk |
|---|---|---|
| **ALLY** | Shared loot, they can revive you, friendly fire off | They can break the pact later |
| **FIGHT** | Their whole kit | They might be better than you |
| **IGNORE** | Nothing bad now | Nothing good, ever |

A six-second window. A horde walking toward you the whole time. And a permanent
record of who kept their word and who didn't.

Full design in **[CONCEPT.md](CONCEPT.md)**.

---

## Art direction

Charcoal base. Amber `#ffb648` for the player and friendly intent. Blood
`#c8321f` for threat. Cold `#7fc4ff` from the city. Nothing else.

Silhouette-first: you must read a player as a *shape* in the dark before any
detail loads. Rim-light everything, warm ahead and cold behind, so figures
separate from the background.

---

## Status

- ✅ Concept, mechanics, UI art direction — done.
- ✅ Two screens rendered and art-directed.
- ❌ **No playable build.** This is a design package, not a game.

> **Honesty note:** both images are concept mockups, *not* screenshots of a
> running game — they were authored as HTML/CSS and rendered. Developed on
> Linux, where Roblox Studio cannot run, so nothing here has been play-tested.

---

MIT © 2026 areli703
