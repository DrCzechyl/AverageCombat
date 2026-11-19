# Average Combat - Design Notes

## Pitch

Mortal Kombat, but the fighters are people you have met. A mid-level manager, an
HOA president, a landlord, and an unpaid intern resolve their differences in the
break room, the parking lot, and somebody's backyard. The comedy is deadpan: no
gore, no mysticism, just fluorescent lighting and unresolved workplace tension.

## Pillars

1. **Recognizable.** Every character, stage, and attack is something from
   ordinary life. A clipboard is a projectile. A severance box is a lunge.
2. **Readable.** Big pixel silhouettes, clear startup poses, and loud hit
   feedback. A new player should understand a hit in one round.
3. **Local first.** Two people on one couch, one keyboard, or two pads. Every
   menu must work with one hand and no mouse.
4. **Simple to tune.** Frame data is data, not code. One table per fighter.

## Match rules

- Local versus is best of three (first to two). Arcade is one round per opponent. Training is a single endless round: a KO resets both fighters and does not end the session.
- 99-second rounds. On time over, the higher remaining-health percentage wins;
  an exact tie is a draw and both players get a round win.
- 900-1160 health depending on the fighter. Damage per hit is roughly 45-165.
- Specials cost 50 of a 100-point meter. Meter is built by dealing damage,
  taking damage, and (slowly) by whiffing attacks.
- Blocking: hold back or the block key. High attacks miss crouch block; lows miss
  standing block; mids hit either. Blocked hits do 12-15% chip damage.
- Knockdown: sweeps launch. A KO launches the loser for the round-end beat.

## Frame data model

Timings are in 60 Hz ticks, split into `startup`, `active`, `recovery`.
Hitboxes are `Rect2`s relative to the fighter's feet, with negative Y pointing
up. The arena mirrors the box horizontally based on facing. Hurtboxes are shared
per stance (standing, crouch, air); normals tweak damage and startup per fighter.

- Jab: 5 startup, 3 active, 9 recovery, 45 damage, high.
- Heavy: 11 startup, 4 active, 20 recovery, 95 damage, mid.
- Low poke: 6/3/13, 45 damage, low.
- Sweep: 12/4/22, 85 damage, low, launches.
- Air attack: 5/8/6, 75 damage, high.
- Specials: 9-20 startup, 4-6 active, 15-26 recovery. See `SPECIALS` in
  `scripts/data/character_db.gd`.

Combo scaling reduces each successive hit by 9%, floored at 35%. Hitstop freezes
both fighters for 7-9 ticks on contact (4 on block).

## Roster

### Dave - Mid-Level Management
Baseline stats. **Severance Package**: a lunging box swing with big reach and
140 damage. The honest all-rounder; the character you give a friend who has never
played.

### Karen - HOA President
Slower, slightly fragile, hits hard. **Cease and Desist** throws a clipboard that
travels most of the screen for 95 damage. Her game is keeping you out; her weakness
is that the clipboard takes a beat to come out.

### Tony - The Landlord
1160 health, slow, heavy damage. **Eviction Notice** is a slow, armored swing that
eats one hit and keeps coming. He wins by walking you into the corner and making
you respect the plunger.

### Chad - Unpaid Intern
Fastest walk speed, lowest health. **Reply All** is a fast dash punch with long
reach. He wins by never letting you breathe; one correct read ends his day.

## Stages

All stages are 1280x720 with the floor line at y=600 and symmetric spawn points.
Walkable bounds are roughly x=200..1080 (backyard is 220..1060).

- **The Break Room** - vending machine, fridge, motivational poster. 4:59 PM.
- **The Parking Lot** - dusk, Average Mart, a car that is definitely not parked
  legally.
- **The Backyard** - somebody's BBQ, a fence that is one inch too tall.

## Flow

```
Main Menu
  ├─ Local Versus → Character Select (both players) → Stage Select → Fight
  ├─ Arcade       → Character Select (P1) → Stage Select → Fight → Results
  │                                                        └─ Next opponent…
  ├─ Training     → Character Select (P1) → Stage Select → Endless Fight
  └─ Options      → volume, difficulty, shake, hitstop, hitboxes, fullscreen
```

Results adapt to the mode: rematch/change fighters for versus and training;
next opponent/quit for arcade; try again after an arcade loss. There is no
separate game-over scene.

## Presentation

- 1280x720 canvas, integer-ish pixel scaling, nearest-neighbour filtering.
- Sprites are 64x96 cells at 3x scale. Fighters are drawn with feet at y=600.
- UI is built from code with a shared theme so every screen stays consistent.
- HUD is custom-drawn: health with a lagging damage trail, meter with a
  "special ready" pulse, timer, round pips, combo counter, and callouts.
- Screen shake and hitstop are toggleable, for accessibility and for people who
  find them distracting.

## Save data

`user://average_combat.cfg` stores settings, lifetime stats (matches, wins, best
combo, arcade clears, total damage), and the last character/stage picks. It is a
plain `ConfigFile`, so it can be hand-edited or reset by deleting the file.
Headless suites and other `res://tests` scenes write a temp file instead, so a
test run does not load or replace that save.
