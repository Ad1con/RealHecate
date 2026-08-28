# RealHecate

When Hecate splits into three, this puts a coloured light on the ground under the
real one. The other two are clones.

The light appears when she splits and goes away when the clones do, so the rest
of the fight is untouched.

**This removes an ambiguity the fight is built around.** It exists as a practice
and accessibility tool. If you want the fight as designed, don't install it — or
turn `Enabled` off, which leaves the encounter completely vanilla.

## It works in both fights

Hecate splits in the ordinary fight as well as in Extreme Measures / Rivals. The
ordinary fight uses her `HecateSplit1/2/3` weapons in all three phases; Extreme
Measures adds a scripted split at the start and forces one more on each phase
change. Both are marked by default, and each can be switched off on its own.

## What it does

Two markers, both on by default, both confirmed working:

- **An orange outline** around the real Hecate's silhouette.
- **A dark pool** on the ground under her, where the clones have none.

## Why not a coloured light on the floor

Because it cannot work in that arena, and it took a long time to establish why.

`F_Boss02.map_text` — the Hecate arena's map, plain JSON on disk — declares
`AmbientLightColor` at a near-white `(0.911, 0.954, 1.000)` and contains **no
coloured light objects at all**. The intense cyan is painted into the arena's
textures.

Additive light can only add. On a floor that is already a bright cyan image,
adding orange gives cyan + orange, which clips toward white. More stacking makes
it whiter, not oranger. No colour, brightness or scale value beats a painted
floor.

So the mod stopped adding light:

- **Invert** swaps the light to `DiffuseSpotlightInverse` (same 360×180 ellipse,
  centre 42 instead of 213), which *darkens*. Nothing in the scene can add its
  way over a subtraction.
- **The outline** never touches the floor at all.

Orange is used because it is the **complement of the arena's cyan** — the
maximum-contrast choice against that specific background.

## Settings## How it tells them apart

Not by health, behaviour, or position — the game already knows. Every split in
the fight goes through one function, `UnitSplit`, which is called on the real
Hecate's own enemy table and records the clones it creates as
`enemy.SplitIds[newObjectId] = true`. So the real one is whatever `UnitSplit` was
called on, and the clones are exactly the keys of that table.

Her `ObjectId` never changes for the entire fight — not through phase
transitions, not through repeat splits, not through Polymorph or Dark Side, and
the phase-interlude clone wipes are type-scoped so they can never take her. That
is why this mod has no re-detection logic: mark her once, and it is still the
right unit three splits later.

Full citations, file and line, are in the header comment of `main.lua`.

## Why a ground light

The game already puts a light on the ground under Hecate — `HecateGroundGlow`,
an invisible sprite whose only job is to carry a `DiffuseSpotlight`. This mod
registers its own copy of that pair in a distinct colour and attaches it to the
real one. Same mechanism, same role, so it follows her through every teleport and
cleans itself up on her death.

v1.0.0 shipped that alone and it was too subtle to play off — not because it was
dim, but because **all three of them have one**. Vanilla gives that same ground
glow to the real Hecate and to every clone, so a fourth light was one glow among
four rather than a signal.

v1.1.0 addressed that inside the light rather than replacing it: stack the light
for real brightness, and take the glow off the clones so hers is the only lit
floor. Both keep the natural look. The outline is there as a fallback, off by
default.

## The bug that made v1.0.0 and v1.1.0 invisible

Both shipped, both logged complete success at every step, and both drew nothing
at all. Worth recording, because nothing in the logs could have told you:

```lua
CreateAnimation({ Name = ..., DestinationId = ..., Group = "FX_Terrain" })
```

`FX_Terrain` was copied out of the animation definition's `GroupName` field. As a
`CreateAnimation` argument, `Group` is a *render group* — a different namespace —
and `FX_Terrain` is never passed as one anywhere in the game. It appears as a
`Group` only on `SpawnObstacle` calls. The light was being filed into a group
that doesn't draw.

The game's own call for exactly these animations passes nothing else at all
(`RoomLogic.lua:3384`):

```lua
CreateAnimation({ Name = animName, DestinationId = unit.ObjectId })
```

Two lessons, both now guarded by tests: a field name appearing in the data is not
automatically a valid argument to the function consuming that data, and success
logging proves a call was made, never that the engine honoured it.

## Tests

```bash
cd test && lua run_tests.lua
```

193 tests. Run on both `lua` (5.4) and `luajit` (2.1) — the game ships LuaJIT.

```bash
winget install DEVCOM.Lua
winget install LuaJIT.LuaJIT
```
