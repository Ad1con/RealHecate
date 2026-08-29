# RealHecate

**Tells you which Hecate is the real one when she splits into three.**

The real Hecate will have a red glow under her and a red outline. The two clones
will not. There are options to disable either the glow or the outline, and to
change their colours.

Works in the ordinary fight, in the Rivals fight, and in Dream Dives. Hecate and
her clones already have red outlines during Dream Dives, so the clones' outlines
are removed there and only the real Hecate keeps one.

The mod uses only in-game assets and changes no fight or gameplay behaviour — it
is purely cosmetic. It does make the fight easier, since telling the clones apart
is normally part of it.

---

## Settings

The config file is `Adicon-RealHecate.cfg`, in your profile's
`ReturnOfModding\config` folder. Every setting is also on the **RealHecate**
panel in the modding overlay.

Edit the file with the game **closed** — Hades II rewrites it from memory on
exit, so changes made while it is running are discarded.

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
| `CloneVanillaGroundFx` | `true` | Whether the **clones** keep vanilla's ground effects — their shadowing and the glowing symbols on the floor. Off darkens them, so only the real Hecate has ground effects. |
| `HecateVanillaGroundFx` | `true` | Whether **she** keeps vanilla's ground effects under the red glow. Off isolates the marker. |
| `StripCloneDreamOutline` | `true` | Dream Dive only. Takes vanilla's outline off the clones so the real Hecate is the only outlined one. No effect outside Dream runs. |

**Colours** for `GroundFxColor` and `OutlineColor`:
`Amber` `Ember` `Violet` `Gold` `Teal` `Cyan` `Green` `Magenta` `Red` `White`

Red is the default because it is roughly the complement of the arena's cyan
floor, which is the strongest contrast available there.

## How it knows which one is real

Not by health, behaviour, or position — the game already knows.

Every split in the fight goes through one function, `UnitSplit`. It is called on
the real Hecate's own enemy table and records the clones it creates as
`enemy.SplitIds[newObjectId] = true`. So the real one is whatever `UnitSplit` was
called on, and the clones are exactly the keys of that table.

Her `ObjectId` never changes for the entire fight — not through phase
transitions, not through repeat splits, not through Polymorph or Dark Side, and
the phase-interlude clone wipes are type-scoped so they can never take her.
Confirmed in game across three splits of one encounter, all reporting the same
id. That is why the mod has no re-detection logic: mark her once and it is still
the right unit three splits later.

Full citations, file and line, are in the header comment of `src/main.lua`.

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

`guard.sh` refuses edits while Hades II is running. The plugin folder in
r2modman is a junction to `src/`, so every save there is a live edit to the
running game, and hot-reloading mid-fight has crashed it.

## Credits

Hades II is by [Supergiant Games](https://www.supergiantgames.com/). This is an
unofficial fan mod, not endorsed by or affiliated with them. The icon is a
cropped in-game portrait.

Built on [ReturnOfModding / Hell2Modding](https://github.com/SGG-Modding), with
`SGG_Modding-ModUtil` and `SGG_Modding-ReLoad`.
