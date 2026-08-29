# RealHecate

**Tells you which Hecate is the real one when she splits into three.**

She gets a red glow on the ground and a red outline. The two clones don't. It
appears when she splits and goes away when the clones do, so the rest of the
fight is untouched.

Works in the ordinary fight, in Extreme Measures / Rivals, and in Dream Dive.

---

## Why you might want it

Hecate's Triple Divide is deliberately ambiguous — vanilla even lights the
torches on all three of her so you can't tell them apart. That's the mechanic
working as designed.

This removes that ambiguity on purpose, as a practice and accessibility tool. If
you want the fight as designed, don't install it — or set `Enabled = false`,
which leaves the encounter completely vanilla.

## It doesn't take anything away

By default the mod only **adds**. The clones keep their own ground glow, Hecate
keeps hers, and nothing about the fight changes except that she now carries a red
marker. Every removal is opt-in.

The one exception is Dream Dive, and it's a fix rather than a change: vanilla
gives the base fight's clones the *same red outline* it gives the real Hecate, so
the outline identifies nothing there. `StripCloneDreamOutline` takes it off the
clones so she's the only outlined one. It has no effect outside Dream runs.

## Settings

`Adicon-RealHecate.cfg`, in your profile's `ReturnOfModding\config` folder. Every
setting is also on the **RealHecate** panel in the modding overlay.

Edit the file with the game **closed** — Hades II rewrites it from memory on exit,
so changes made while it's running are discarded.

| Setting | Default | What it does |
|---|---|---|
| `Enabled` | `true` | Master switch. Off is fully vanilla. |
| `GroundFx` | `true` | Show the red glow on the ground. |
| `GroundFxColor` | `Red` | Colour of the ground glow. |
| `GroundFxScale` | `3` | Size of the ground glow. |
| `Outline` | `true` | Outline her silhouette. |
| `OutlineColor` | `Red` | Colour of the outline. |
| `OutlineThickness` | `6` | 1–10. The game's own elite outlines are `3`. |
| `OutlineOpacity` | `1.0` | 0–1. The game's own are `0.8`. |
| `CloneVanillaGroundFx` | `true` | Whether the **clones** keep vanilla's ground effects — their shadowing and floor symbols. Off darkens them, so only she has ground effects. |
| `HecateVanillaGroundFx` | `true` | Whether **she** keeps vanilla's ground effects under the red glow. Off isolates the marker. |
| `StripCloneDreamOutline` | `true` | Dream Dive only — see above. |

**Colours** for `GroundFxColor` and `OutlineColor`:
`Amber` `Ember` `Violet` `Gold` `Teal` `Cyan` `Green` `Magenta` `Red` `White`

Red is the default because it's roughly the complement of the arena's cyan floor,
which is the strongest contrast available there.

## How it knows which one is real

Not by health, behaviour, or position — the game already knows.

Every split in the fight goes through one function, `UnitSplit`. It's called on
the real Hecate's own enemy table and records the clones it creates as
`enemy.SplitIds[newObjectId] = true`. So the real one is whatever `UnitSplit` was
called on, and the clones are exactly the keys of that table.

Her `ObjectId` never changes for the entire fight — not through phase
transitions, not through repeat splits, not through Polymorph or Dark Side, and
the phase-interlude clone wipes are type-scoped so they can never take her.
Confirmed in game across three splits of one encounter, all reporting the same
id. That's why the mod has no re-detection logic: mark her once and it's still
the right unit three splits later.

Full citations, file and line, are in the header comment of `main.lua`.

## Compatibility

Modifies no game files. It edits `EnemyData` tables in memory, attaches art that
already ships with the game, and wraps exactly one function (`UnitSplit`).

Nothing is written to your save.

## Development

```bash
cd test && lua run_tests.lua
```

127 tests, run on both `lua` (5.4) and `luajit` (2.1) — the game ships LuaJIT.

```bash
winget install DEVCOM.Lua
winget install LuaJIT.LuaJIT
```

`guard.sh` refuses edits while Hades II is running. If the plugin folder is a
junction to your working copy, every save is a live edit to the running game, and
hot-reloading mid-fight has crashed it.

## Credits

Hades II is by [Supergiant Games](https://www.supergiantgames.com/). This is an
unofficial fan mod, not endorsed by or affiliated with them. The icon is a
cropped in-game portrait.

Built on [ReturnOfModding / Hell2Modding](https://github.com/SGG-Modding), with
`SGG_Modding-ModUtil` and `SGG_Modding-ReLoad`.
