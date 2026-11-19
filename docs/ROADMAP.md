# Roadmap

## Now (0.1) - local skeleton

- [x] Title, character select, stage select, options, results
- [x] Local versus, arcade ladder, training
- [x] Four fighters, three stages, specials, meter, blocking, KO flow
- [x] Persisted settings, stats, and last picks
- [x] Fixed 60 Hz simulation with an input seam
- [x] Headless smoke test and screenshot harness
- [x] Placeholder pixel art and chiptune SFX

## Next (0.2) - make it feel good

- [ ] Playtest with friends; tune damage, pushback, and round length
- [ ] Hit-confirm audio layer (light/heavy/block already distinct; add reverb tail)
- [ ] Whiff/block animations and a proper knockdown + wakeup
- [ ] Throw and tech window (currently there is no throw)
- [ ] Round-start "READY / FIGHT" timing polish and a real KO camera hold
- [ ] Pause menu controller navigation audit (focus order, back buttons)
- [ ] Replace generator font/placeholders with a licensed pixel font
- [ ] Accessibility: remappable keys, colorblind-safe meter, shake slider

## Then (0.3) - content

- [ ] Two more fighters (suggested: a substitute teacher and a delivery driver)
- [ ] One more stage (suggested: the office stairwell)
- [ ] Per-character intro/win quotes and a small arcade ending card
- [ ] Costume palette swaps
- [ ] Daily/weekly stat summary on the title screen

## Later (1.0) - online

The simulation is already deterministic-friendly: all gameplay runs in fixed
ticks, input is a small dictionary, and fighters never read the keyboard.

- [ ] Input delay + delay-based netcode first (simplest path)
- [ ] Rollback (GGPO-style) once the tick rate and state snapshot are stable
- [ ] Deterministic RNG for AI and effects (or keep RNG cosmetic-only)
- [ ] Lobby, rematch, character/stage select over the wire
- [ ] Server-authoritative stats, or client-side stats with consent

## Explicit non-goals

- Gore or realistic violence. The joke is that nobody is actually hurt.
- A story mode with cutscenes. Arcade endings are one card, not a campaign.
- Live-service progression, battle passes, or monetization.
