# Design notes — RealHecate

Not shipped — see `thunderstore.toml`'s `[[build.copy]]` list, which names only
`CHANGELOG.md`, `LICENSE` and `src`. This expands on the header of
[`src/main.lua`](src/main.lua), which keeps only the load-bearing citations and
points here for the rest.

## How the real one is identified

Every split in the fight goes through one function, `UnitSplit`
(`EnemyAILogic.lua:5139`). It is called on the real Hecate's own enemy table
and spawns N new units:

    enemy.SplitIds = {}                                  -- :5152
    newEnemy.ObjectId = SpawnUnit({ ... })               -- :5168
    enemy.SplitIds[newEnemy.ObjectId] = true             -- :5169

So after any split the real Hecate is the `enemy` the function was called on,
her `ObjectId` is unchanged, and the clones' `ObjectId`s are exactly the keys
of `enemy.SplitIds`. Nothing has to be inferred from health, behavior or
position.

Crucially, **the real one never changes** for the whole fight. Checked
against every mechanic that could plausibly reassign her:

- `UnitSplit` only ever assigns new `ObjectId`s to newly spawned units. The
  table it is called on is never re-identified. It does reset `SplitIds` each
  time (`:5152`), so repeat splits start clean rather than accumulating.
- Both stage transitions `Teleport` her by her existing `ObjectId`
  (`EnemyAILogic.lua:6306` and `:6328`), so phase changes move her, not swap
  her.
- `HecatePolymorph` applies to the Hero, not to Hecate (`EffectLogic.lua:277-280`).
- `HecateDarkSide` only swaps her weapon list (`EffectLogic.lua:1191-1199`).
- The clone wipes at the phase interludes are type-scoped —
  `WipeEnemyTypes = { "HecateCopy", "HecateCopyEM" }` (`EnemyData_Hecate.lua:327`
  and `:374`) — so they can never take the real one.

That is why this plugin has no re-detection logic and no per-split
bookkeeping beyond a generation counter. Mark the unit `UnitSplit` was called
on, and it is still the right unit three splits later.

## Which splits exist

She splits in the ordinary fight as well as in Extreme Measures. All of these
funnel into `UnitSplit`, which is why one wrap covers them:

- Ordinary fight — `HecateSplit1/2/3` (`WeaponData_Hecate.lua:1154, 1245, 1259`),
  `FireFunctionName = "UnitSplit"`, `SpawnedUnit = "HecateCopy"`. Equipped in
  phase 1 (`EnemyData_Hecate.lua:268`), phase 2 (`:362`) and phase 3 (`:410`).
- Extreme Measures — `SpawnHecateClones` (`PresentationBiomeF.lua:63`) as a
  room function gated to encounter `BossHecate02` (`RoomDataF.lua:2447`), then
  `HecateEMSplit` (`WeaponData_Hecate.lua:1278`) forced on entering phase 2
  (`EnemyData_Hecate.lua:344`) and phase 3 (`:391`). `SpawnedUnit = "HecateCopyEM"`.

`HecateComboBreakerSplit` is **not** a split despite the name. It never calls
`UnitSplit`; it teleports clones that already exist (`EnemyAILogic.lua:5196-5211`).
Nothing here needs to handle it.

The two scope settings are keyed off `aiData.SpawnedUnit` rather than off a
difficulty check. That is the one fact the wrap can read directly and be sure
of, instead of inferring the fight variant from equipped weapon lists.

## Why a ground light rather than an outline

The game already puts a light on the ground under Hecate. Both the real one
(`EnemyData_Hecate.lua:21`) and the clones (`:5564`) carry
`CreateAnimations = { "HecateGroundGlow" }`, and that animation
(`Enemy_Erebus_VFX.sjson:2950`) is nothing but an invisible sprite whose job
is to hold a light (`Light = "HecateGroundLight"`, a `Lights\DiffuseSpotlight`,
`DieWithOwner = true`). This plugin registers its own copy of that pair in a
distinct color and attaches it to the real Hecate, the same mechanism the
game uses in the same role, so it follows her through every teleport and
cleans itself up on her death without any code here.

An outline is offered as a fallback (`Outline`, on by default as of v3.4.0).
It is the game's own mechanism for marking a unit special — what elites get
(`CombatPresentation.lua:1223`, `EnemyAILogic.lua:5183`) — and it traces her
silhouette rather than the floor, so it does not compete with the arena's
lighting at all. The elite BADGE system was considered and does not fit: it
attaches to a floating health bar (`CombatPresentation.lua:115-130`), and
Hecate is a boss with a top-of-screen bar while the clones carry
`HideHealthBar`, so there is no anchor for it.

`AddOutline` takes 0-255 channels (`PresentationBiomeF.lua:36` uses
`230/23/0`), where the light's sjson takes 0-1 — `colorTo255` exists so that
conversion is written exactly once. One known interaction: in a Dream run
vanilla outlines the real Hecate red (`PresentationBiomeF.lua:33-36`); ours
replaces it while the marker is up, and `restoreVanillaOutline` puts it back
on removal rather than leaving her bare. The teal outline vanilla gives EM
copies (`EnemyData_Hecate.lua:5738-5748`) is on the clones and is left
untouched, since a marker only the real one lacks would be a signal too.

## Why nothing rendered until v1.2.0

v1.0.0 and v1.1.0 both logged complete success and both drew nothing. Two
playtests, no errors, the right unit identified every time. The cause was one
argument:

    CreateAnimation({ Name = ..., DestinationId = ..., Group = "FX_Terrain" })

`"FX_Terrain"` was copied out of the animation definition's `GroupName`
field. As a `CreateAnimation` argument, `Group` is a *render group* — a
different namespace — and `FX_Terrain` is never passed as one anywhere in the
game. It appears as a `Group` only on `SpawnObstacle` calls
(`HubPresentation.lua:179`, `RoomLogic.lua:4879`). The light was being filed
into a group that does not draw.

The game's own call for exactly these animations passes neither a `Group` nor
anything else (`RoomLogic.lua:3381-3387`):

    CreateAnimation({ Name = animName, DestinationId = unit.ObjectId })

The general lesson this project keeps charging for: a field name that
appears in the data is not automatically a valid argument to the function
that consumes the data, and adding a plausible extra argument is a change,
not a clarification. Every log line said the plugin was working, because the
plugin genuinely did everything it meant to — success logging proves a call
was made, never that the engine honored it.

## No custom art registration — and why that is the point

Versions 1.0.0 through 2.7.0 registered custom animations through sjson and
attached those. It never worked, and the failure was narrow and stubborn: the
custom light rendered but never took its color, under every condition tried
— Red, Ember and Amber; brightness 0.5 and 1.0; vanilla's own exact channel
values baked into it; standalone definitions and `InheritFrom` definitions.
All of them produced the same untinted gray-white pool.

Two playtests bounded it exactly: a diagnostic that attached *vanilla's*
`HecateGroundGlow` by name rendered, stacked, and cycled teal to magenta
correctly; a diagnostic that put vanilla's exact numbers into *this mod's own*
registered animation still came out gray-white. Same numbers, different
result — so the values were never the problem, and no further color tuning
could have found it.

The rewrite therefore uses no custom art at all. Both mechanisms it does use
were confirmed working in a real fight: removing `HecateGroundGlow` from the
clone types in data (verified — the clones went dark), and attaching
vanilla's own `HecateGroundGlow` to her and stacking it (verified — eight
copies were visibly brighter, in color). The cost is that the color is
vanilla's teal-to-magenta cycle rather than a free choice — color is
recovered separately, by tinting a ground *sprite* instead (see below), since
that path is confirmed working where tinting a light was not.

### Ground sprites, not lights, for color

A light **adds** to the floor, and the arena floor here is a painted cyan
image (`F_Boss02.map_text` carries no colored lights at all; ambient is a
near-white `0.911/0.954/1.000`), so an additive light on it can only ever
wash toward white — every color tried read as blue-silver, and more stacking
only made it whiter. That is arithmetic, not a bug, and no color tuning beats
it. A sprite is drawn *on* the floor and carries its own art, so it reads on
its own terms instead. `ApolloGroundGlow` is defined as `Red = 1, Green = 0.6,
Blue = 0`, and vanilla passes `Color` to `CreateAnimation` for sprites in
seven places (`EventLogic.lua:1676`, `SpellPresentation.lua:465, 496, 507, 510`,
`RoomPresentation.lua:2410`, `UpgradeChoiceLogic.lua:999`) as `{R, G, B, A}`
in 0-255 — a documented runtime path for sprites, unlike the light tinting
that never worked.

`CastCircle` (a ring) was considered as a second art option because it reads
by *shape*, which survives a busy floor in a way no color does. `ApolloAoECircleA`
was tried for this and removed unused: reading its definition, it carries a
`PingPongColor` cycle of its own that would fight `GroundFxColor`, an
`StartAlpha` fade, and a `VisualFx` spawned every ~0.2s — an AoE telegraph,
not a marker. The `AxeNovaLight_<God>` family was offered as a color palette
in v3.7.0 and was also a mistake: those are one-shot nova bursts (`Duration =
1`, no `Loop`), so the marker flashed once and vanished. `ApolloGroundGlow` is
the one confirmed working, and the reason is in its own definition: `Loop =
true, NumFrames = 15, PlaySpeed = 30` — it runs forever.

## Making it read

The marker is not dim in isolation — the real difficulty is that all three
units have a ground glow, so an unmodified extra light is one glow among
four. Two levers keep the natural look while fixing that: stacking (the same
glow attached N times is additive, so N copies read as one light at N times
the brightness, live, with no restart) and taking the glow off the clones in
data at load (contrast by subtraction — nothing artificial is added, and it
arguably reads as the most honest form of this mod, since the game already
distinguishes units by ground light and this only makes that distinction
exclusive).

The outline was built in v1.1.0 and left off for ten rounds on the judgment
that it "reads as a mod" while a ground light looks natural. That judgment
cost real time: the painted-cyan floor described above means an additive
floor light can only ever wash toward white there, while the outline never
touches the floor at all — it worked on the first test, once it was finally
turned on in v3.4.0.

## Removed settings, and why

An earlier version (through roughly v3.0.0) exposed the ground light more
directly: `Invert` (a dark, inverted pool instead of a bright one — the arena
could not visually wash out a *darkened* patch of floor the way it washed out
every added color), `Recolor`/`SteadyColor`/`Color` (tint and hold a color on
vanilla's own light entry), `Scale`, and `LightStacking`. All of them were
removed once the ground *sprite* replaced the tinted-light approach entirely
— the sprite renders in whatever color is asked for, so a dark pool
underneath a colored sprite only muddied it, and a direct comparison in a
playtest preferred the sprite alone. `GroundFx`, `GroundFxColor` and
`GroundFxScale` are their replacements. If a future color reads poorly
against vanilla's own teal-to-magenta cycle, `HecateVanillaGroundFx` (leaving
her own base glow off) is the current lever for isolating the marker, rather
than reviving `Invert`.

`HecateVanillaGroundFx` defaulting on took a few rounds to land on: while the
mod was trying to *tint a light*, vanilla's teal-to-magenta cycle sat on top
of it and drowned the color, which cost several rounds of "the color is not
changing" reports when it was changing all along, invisibly. That stopped
applying once the marker became a sprite — the sprite renders on its own
terms and does not compete for the same channels — and a playtest with both
on preferred keeping her own glow, since it adds shadowing and keeps the
ground under her looking like the game's own art rather than a flat disc.

`GroundFxScale` shipped at 4.0 initially — `ApolloGroundGlow` carries `Scale
= 0.33` in its own definition, so it starts small, and a playtest at 1.0
called the ring "pretty small." A later playtest at 4.0 called the pool
slightly too large, landing on the current 3.0. The ceiling is 12 rather than
5 because it was never established whether `CreateAnimation`'s `Scale`
multiplies the baked value or replaces it; headroom cost nothing to add.

## Overlay panel

Added in v2.2.0 after a playtest went looking for RealHecate in the modding
overlay and did not find it. Settings were file-only, which is a gap in this
plugin rather than a limit of the platform: Chalk generates the `.cfg` and
draws no GUI at all; the overlay panel is separate `rom.gui`/ImGui code. Hot
reload and an overlay panel coexist fine — several other installed mods do
both — so this cost nothing that was already working.

Three rules this follows, all of them things this platform punishes: every
ImGui widget label carries a `##unique` suffix, since widgets are keyed by
label string and two sharing one label become one widget and move each
other; `End` is unconditional after `Begin`, and `EndCombo`/`EndMenu` only
when their `Begin` returned true, since mispairing leaks a window and
corrupts the overlay for every mod, not just this one (test 10c.7 caught
exactly that in the first draft of `renderWindow`); and the whole body is
wrapped in `pcall`, since a failure there must not take the overlay, or the
game, down with it.
