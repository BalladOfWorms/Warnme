<img width="556" height="153" alt="Screenshot 2026-07-31 173510" src="https://github.com/user-attachments/assets/a4a3cb7d-f809-4b15-801c-9a9004e0ec43" />

# WarnMe
A Windower 4 addon for Final Fantasy XI

WarnMe was built to prominently print a targeted enemies actions to the players screen.  
Any ability, tp-move or spell is rendered to the center of the window for a few seconds, showing the name of the action, who the actor was and who the action was used on — and, when known, **what the ability does**: its targeting shape (Self / AOE / Fan / Conal) and the status effects it inflicts.

This is for you if you want to:
- see when Pain Sync goes off without having to stare at your log
- know *instantly* whether that TP move is conal (sidestep!) or AOE (run!), and what it's about to stick on you
- react faster to certain monster actions
- learn about a monsters skill set
- focus less on customizing your chat log and having to depend on it
- ignore your chat log altogether

Actions are printed autonomously and do not rely in any way on your chat log or how you have your chat log filtered. This addon does not intend to replace existing addons that might include similar functionality. Instead it is meant to be a very simple and effective solution to the old issue of not reacting to a certain skill or spell because of it flying through the log with the speed of light. Completely built from scratch.

Original addon by **Deridjian** (v1.2). This fork by **BalladOfWorms** adds the ability-details database, the unified body box, the watch-all scope, the on-demand test display, and assorted fixes described below. Licensing is covered at the bottom of this page.
<br>

## What the display shows

Two elements, both draggable and independently sizable:

1. **Headline** — the ability/spell name, large and **warning-red** by default (with a black stroke so it reads over any scene).
2. **Body box** — up to three lines in a single element, each centered against the longest line:
   - `Actor > Target` (who used it, on whom)
   - the **targeting line** — any of `Self | AOE | Fan | Conal` that apply
   - the **effects line** — the status effects the ability inflicts (e.g. `Paralysis, Silence`)

The targeting and effects lines come from the ability database below; abilities not in the database simply show without them. Centering always follows your **live game resolution** — a saved screen width from an old resolution no longer pushes the display off-center.

## The ability database

`ability_info.xml` ships alongside `warnme.lua` in the addon folder: **2,100+ monster abilities** with per-ability targeting flags and status effects, generated from [LandSandBoat](https://github.com/LandSandBoat/server) server data (mob_skills AOE flags + mobskill script effects, cross-referenced to Windower's monster_abilities IDs). Entries are matched by ability **id** first, then by **name** (case-insensitive), so renames and localized lookups both work.

Each entry looks like:

    <ability>
        <n>10,000 Needles</n>
        <id>1120</id>
        <self_target>false</self_target>
        <aoe>true</aoe>
        <fan>false</fan>
        <cone>false</cone>
        <effects></effects>
    </ability>

**Hand-curated corrections go in `ability_info_custom.xml`** (same folder, same format). It loads *after* the generated file and wins on any name/id collision — so your manual fixes survive regenerating `ability_info.xml` from newer server data. `//wm reload` re-reads both files in-game.

## Commands

    //wm toggle [actor/target/spells/info] : Toggles display of the passed argument
                                             (info = the targeting + effects lines)
    //wm watch : Warn for ALL alliance-claimed mobs, not only your current target
    //wm mode : Also warn for unclaimed mobs / mobs claimed by others
    //wm timeout [seconds] : Sets the duration for which warnings stay up
    //wm size [ability/details/info] [size] : Changes the font size of any element
    //wm tune [0.5-1.5] : Tune alignment; lower to push right, raise to push left
    //wm test [ability name] : Render the display right now — generic preview, or
                               a real ability complete with its info lines
    //wm sticky : Toggles a persistent test display for manual positioning
    //wm reload : Reload the ability info files

`//wm` with no arguments prints this list with each setting's current state.

## Warning scope

By default WarnMe warns only when **your current target** acts. Two toggles widen that:

- `//wm watch` — warn for **any alliance-claimed mob**, even while you target something else (great for multi-mob pulls and backline jobs that rarely keep the enemy targeted).
- `//wm mode` — additionally accept mobs that are unclaimed or claimed by others.

## Positioning and testing

`//wm test` renders the real display on demand — no waiting for a mob to act — and auto-hides after your configured timeout. Give it an ability name (`//wm test Mortal Ray`) and it shows that ability's actual info lines from the database, which doubles as a quick way to check whether an entry exists and what it says. `//wm sticky` keeps a test display up persistently while you drag the elements into place; toggle it off when done.

## License

The addon code (`warnme.lua`) is **BSD 3-Clause**: original work copyright
(c) 2022 Marian Arlt (published as Deridjian's WarnMe); this fork's
modifications are distributed under the same license — see
[LICENSE](LICENSE). Per the license's terms, neither the original author's
name nor the contributors' may be used to endorse or promote this fork.

`ability_info.xml` is a **generated data file**: its targeting flags and
status effects are extracted from
[LandSandBoat](https://github.com/LandSandBoat/server) server data
(mob_skills AOE flags and mobskill script effects), and LandSandBoat is
licensed **GPL-3.0**. The file credits its provenance in its header. If the
GPL status of data derived from that project matters for your use, treat
`ability_info.xml` as GPL-3.0-derived rather than BSD; it is shipped here
as a convenience and can be regenerated or replaced independently of the
addon code. `ability_info_custom.xml` (your hand-written overrides) is
yours entirely.
