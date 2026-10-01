# DEADPACT — Concept

**Genre:** Third-person zombie survival · PvPvE
**Players:** 24 per server (18 survivors + escalation)
**Pitch:** *Trust no one — or die alone.*

---

## 1. The one-line hook

Every other player in the world is a **decision**, not just a target. When you
meet someone, the game stops for six seconds and asks: *ally, fight or walk?*

That pause is the whole game. It is the reason this is not just another
zombie shooter.

---

## 2. The core loop

```
DEPLOY  →  SCAVENGE  →  ENCOUNTER  →  EXTRACT
   ▲                                      │
   └──────────  or DIE  ←─────────────────┘
```

- **DEPLOY** — drop into a district at night with one weapon and no allies.
- **SCAVENGE** — loot buildings for ammo, meds and better guns. Noise attracts
  the horde; the horde does not stop coming.
- **ENCOUNTER** — meet another player. The **Pact Decision** fires.
- **EXTRACT** — reach a chopper on the far side. Only survivors who extract keep
  what they carried.

Death is not the end of the run's story — it is the end of its *inventory*.

---

## 3. The Pact Decision — the signature mechanic

Triggered when two un-pacted players come within ~10 m with weapons lowered.

| Choice | You gain | You risk |
|---|---|---|
| **ALLY** | Shared loot pool, they can revive you, friendly fire off | They can break the pact later — and there is nothing you can do about it |
| **FIGHT** | Their entire kit | They might be better than you, and now they know where you are |
| **IGNORE** | Nothing bad right now | Nothing good, ever. You reach extraction alone |

### Why it works

- **Six-second window.** Long enough to think, short enough to panic. The horde
  is always closing, so *not choosing* is itself a choice.
- **Broken pacts leave a scar.** The game remembers. Your next encounter screen
  shows their history with you: `PACT WITH YOU · 2 KEPT · 1 BROKEN`. Trust
  becomes a resource with a memory.
- **Allying is genuinely strong** — two players clear a building twice as fast.
  But the winner of the round takes the *whole* crown, and only one person can
  hold it. The betrayal is always mechanically real, never scripted.

---

## 4. The horde — the pressure that makes all of it urgent

The zombies are not the villain. They are the **clock**.

- Escalating waves: quiet at drop, relentless by extraction.
- **Noise is the core tension.** Gunfire, breaking glass, sprinting — each
  raises a local heat value. The loudest fight in the district is where the
  horde converges.
- This is what stops the pact screen from being a safe little menu: you are
  always choosing while something is walking toward you.
- Specials rotate per district: **Shrieker** (summons), **Bloater** (area
  denial), **Stalker** (hunts isolated players — punishes going solo).

---

## 5. The world

| District | Character | Signature |
|---|---|---|
| **Downtown** | Rain-slick streets, neon signage, grid blocks | Rooftop routes, loudest district |
| **The Yards** | Shipping containers, cranes, open sightlines | Best loot, worst cover |
| **Old Hospital** | Corridors, wards, flickering generators | Shrieker nests, tight encounters |
| **The Quarry** | Flooded pits, industrial ruins | Vertical, sightline-heavy PvP |

Each is a compact ~120 m playable area with three extraction points that open
and close on a timer. Every district is built from the same part-based toolkit,
so the whole world is procedurally re-themeable from one config — the same
approach used in the developer's earlier tower game.

---

## 6. Progression

- **No pay-to-win.** Gear is found in the world during a run, and lost on death.
- **Meta-progression is reputation, not power.** Completing pacts, keeping them,
  and extracting builds a standing. It unlocks *cosmetics* and *dialogue
  options* (e.g. a trusted player can propose a pact with more favourable terms).
- Cosmetics are the only thing that survives a wipe.

---

## 7. The UI — see the mockups

Two screens define the feel. Both are in this repo as rendered PNGs plus the
HTML/CSS that produced them (`menu_main.html`, `menu_pact.html`).

### Main menu — `design/menu_main.png`
- Left-anchored: the wordmark, the tagline, then four numbered entries —
  **DEPLOY**, **ARMORY**, **THE PACT**, **SETTINGS**.
- The selected entry gets an amber arrow and lift; unselected sit quiet.
- Right column: your pact slots and live server state (`SECTOR`, `SURVIVORS`,
  `HORDE ▲ ESCALATING`, `PING`).
- Atmosphere does the genre work: rain, a horizon horde, warm rim light on the
  player, cold blue from the city behind.

### Pact encounter — `design/menu_pact.png`
- **Deliberately symmetrical.** You on the left, them on the right, the choice
  in the middle. The standoff *is* the layout.
- Your status top-left (health, stamina, ammo — note "BLEEDING SLOWLY"), their
  intel top-right — deliberately incomplete: `?????`, `UNVERIFIED`, weapon
  lowered, voice off.
- Three options with real stakes written on them, colour-coded amber/red/grey.
- A **6.2 s decision window** with a draining bar, because it is a decision
  under pressure, not a dialogue box.
- Bottom banner: `HORDE APPROACHING 14 m · DO NOT STAND STILL`.

> These are **concept mockups, not screenshots** of a running game. They were
> rendered from hand-authored HTML/CSS to lock the art direction before any
> gameplay code is written.

---

## 8. Art direction rules

- **Palette:** charcoal base, amber `#ffb648` for the player and friendly
  intent, blood `#c8321f` for threat and violence, cold `#7fc4ff` from the
  city. Nothing else.
- **Silhouette-first.** Players must be readable as a *shape* at distance, in
  the dark, before any detail loads.
- **Rim light everything.** Two-source lighting (warm ahead, cold behind) so
  figures separate from the background.
- **The UI is diegetic where it can be.** Health "bleeding slowly" is language,
  not a bar alone. `UNVERIFIED` on another player is a *story*, not a label.
- **Grit, but not grime.** Film grain, rain, vignette — texture over mess.

---

## 9. What is real and what is not

**Real in this repo:** the concept, the mechanics design, and both UI screens
rendered as pixels.

**Not built yet:** the game itself. There is no playable build. This is the
design and art-direction package that would be handed to implementation — the
same way the developer's previous Roblox title started with a locked concept.

**Honest constraint:** developed on Linux. Roblox Studio has no native Linux
build, so nothing like this can be *played* here — only built, and then opened
on a Windows or Mac machine.

---

*DEADPACT · concept v0.1 · MIT*
