-- TrueHecate test suite. Run from this directory:
--     lua run_tests.lua
--     luajit run_tests.lua
--
-- Both interpreters, always. The game ships LuaJIT and the two differ in ways
-- that have bitten this codebase before.

local PLUGIN = "../main.lua"
local HARNESS = "./harness.lua"
local M = dofile("./mocks.lua")

local passed, failed = 0, 0
local failures = {}

-- Assertions must FAIL, not raise: a regression that makes a value nil must read
-- as one red line, not abort the run and hide every later section.
-- Detail is truncated. A failure that prints eighty variant names is unreadable,
-- which makes it as unhelpful as no detail at all.
local function check(name, condition, detail)
  if condition then
    passed = passed + 1
  else
    failed = failed + 1
    detail = detail and tostring(detail) or nil
    if detail and #detail > 140 then
      detail = detail:sub(1, 137) .. "..."
    end
    failures[#failures + 1] = name .. (detail and ("  -- " .. detail) or "")
  end
end

-- Guarded index, so asserting on a field of something that turned out nil is a
-- failure rather than a crash.
local function at(t, k)
  if type(t) ~= "table" then return nil end
  return t[k]
end

local function logsContain(needle)
  for _, line in ipairs(M.logs or {}) do
    if tostring(line):find(needle, 1, true) then return true end
  end
  return false
end

-- Resolves the variant the CURRENT settings select, so a test that changes
-- colour or brightness looks at the entry the plugin would actually attach
-- rather than at the shipped default's entry.
local function activeLight(plugin)
  local name = at(plugin, "CONFIG") and plugin.CONFIG.glowName() or nil
  if name == nil then return nil end
  return (name:gsub("^TrueHecateGlow_", "TrueHecateLight_"))
end

local function findAnim(name)
  local anims = at(M.animations, "Animations")
  if type(anims) ~= "table" then return nil end
  for _, a in ipairs(anims) do
    if at(a, "Name") == name then return a end
  end
  return nil
end

local function countKeys(t)
  local n = 0
  for _ in pairs(t or {}) do n = n + 1 end
  return n
end

-- Boots the plugin against fresh fakes.
--
-- With no arguments this is EXACTLY the shipping configuration: the mock config
-- store starts empty, so every key binds to the plugin's own default. Tests that
-- need a non-default value pass it in `initial` and thereby state what they
-- depend on, rather than inheriting it.
local function boot(initial, opts)
  opts = opts or {}
  local G = dofile(HARNESS)
  M.install(G, opts.configOpts, initial, opts.sjsonOpts,
            { noReload = opts.noReload, noGui = opts.noGui }, opts.gui)
  if opts.noModUtil then G.ModUtil = nil end
  local plugin = dofile(PLUGIN)
  if M.pendingGameLoad then M.pendingGameLoad() end
  return G, plugin
end

local EM = { SpawnCount = 2, SpawnedUnit = "HecateCopyEM" }
local BASE = { SpawnCount = 2, SpawnedUnit = "HecateCopy" }
-- The shipped variant. Colour and brightness are baked into the NAME now, which
-- is what makes both of them live -- the plugin picks a pre-registered variant
-- at attach time instead of rebuilding art it cannot rebuild.
-- The marker is vanilla's own animation now. No custom art is registered at
-- all -- see the header of main.lua for why.
local GLOW = "HecateGroundGlow"
local VANILLA = "HecateGroundGlow"
-- The ground sprite the shipped GroundFx setting resolves to. Named once so the
-- suite keeps testing what actually ships when the default palette entry moves.
-- Back to Apollo's art. The AxeNovaLight family was tried as a colour palette
-- and rejected: those are one-shot novas (Duration = 1, no Loop), so the marker
-- flashed once at the start of the fight and vanished. Colour now comes from the
-- Color argument instead of from picking different art.
local SHIPPED_FX = "ApolloGroundGlow"

-- The shipped stacking count. Pinned here so a test that measures something else
-- does not silently change meaning when the default moves.
local STACK = 3

-- =============================================================================
-- 1. What actually ships
-- =============================================================================
-- The single section that asserts defaults. Everything else pins what it needs.
do
  local G, plugin = boot()
  local v = at(at(plugin, "settings"), "values")

  check("1.1 ships enabled", at(v, "Enabled") == true, tostring(at(v, "Enabled")))
  check("1.2 ships marking the base fight", at(v, "MarkInBaseFight") == true)
  check("1.3 ships marking Extreme Measures", at(v, "MarkInExtremeMeasures") == true)
  check("1.4 ships removing the marker with the clones", at(v, "KeepAfterClonesGone") == false)
  -- OFF as of v4.0.0. The Apollo ground sprite replaced it, and a playtest
  -- compared them directly and preferred without the dark pool underneath.
  check("1.5 ships the vanilla dark pool OFF", at(v, "Light") == false,
        tostring(at(v, "Light")))
  check("1.5b ships the Apollo ground sprite as the ground marker",
        at(v, "GroundFx") == "ApolloGlow", tostring(at(v, "GroundFx")))
  check("1.5c tinted red", at(v, "GroundFxColor") == "Red", tostring(at(v, "GroundFxColor")))
  -- Ember, not Amber: Amber's middle channel clips at the shipped stacking and
  -- washes to pale yellow-white. That cost a playtest.
  check("1.6 ships a colour that survives the shipped stacking",
        at(v, "Color") == "Ember", tostring(at(v, "Color")))
  -- Measured, not guessed: the art is 360px wide at 1.0 and vanilla's own
  -- Hecate light runs 1.33, so 1.0 is a pool about her own footprint.
  check("1.7 ships scale 1.0 -- measured against the actual texture",
        at(v, "Scale") == 1.0, tostring(at(v, "Scale")))
  check("1.7b ships recolouring vanilla's light on", at(v, "Recolour") == true)
  check("1.7c ships a steady colour, not vanilla's rapid cycle",
        at(v, "SteadyColor") == true, tostring(at(v, "SteadyColor")))
  check("1.9 ships stacking " .. STACK, at(v, "LightStacking") == STACK,
        tostring(at(v, "LightStacking")))
  check("1.10 ships stripping the clones' vanilla glow", at(v, "RemoveCloneGlow") == true)
  check("1.10b ships replacing her own vanilla glow", at(v, "ReplaceVanillaGlow") == true)
  check("1.10c ships stripping the clones' Dream outline",
        at(v, "StripCloneDreamOutline") == true)
  -- The outline is the PRIMARY marker as of v3.4.0. It was off for ten rounds
  -- on taste grounds while the ground light was tuned against a painted-cyan
  -- floor it could never win against. It worked on its first test.
  check("1.11 ships the outline ON", at(v, "Outline") == true, tostring(at(v, "Outline")))
  -- Matched to the ground sprite so the two markers read as one scheme rather
  -- than as red-and-orange.
  check("1.11b in the same colour as the ground marker",
        at(v, "OutlineColor") == at(v, "GroundFxColor"),
        tostring(at(v, "OutlineColor")) .. " vs " .. tostring(at(v, "GroundFxColor")))
  check("1.11c ships invert on, so the floor pool darkens rather than washes",
        at(v, "Invert") == true, tostring(at(v, "Invert")))
  check("1.12 settings persist when rom.config is available",
        at(at(plugin, "settings"), "persistent") == true)
  check("1.13 the wrap went on UnitSplit and nothing else",
        at(G.wrapped, "UnitSplit") == 1 and next(G.wrapped) == "UnitSplit")
end

-- =============================================================================
-- =============================================================================
-- =============================================================================
-- 4. Identification -- the whole point of the mod
-- =============================================================================
do
  local G = boot()
  local hecate = G.spawnHecate()
  G.UnitSplit(hecate, EM)

  check("4.1 the split produced two clones", countKeys(hecate.SplitIds) == 2,
        tostring(countKeys(hecate.SplitIds)))
  check("4.2 the marker went on the real Hecate",
        G.anyMarkerCount(hecate.ObjectId) > 0,
        "attached=" .. tostring(G.anyMarkerCount(hecate.ObjectId)))

  -- The load-bearing assertion: our marker is on her and on nothing else.
  local onClone = false
  for id in pairs(hecate.SplitIds) do
    if G.markerCount(id) ~= 0 then onClone = true end
  end
  check("4.3 no clone was marked", onClone == false)
  local elsewhere = 0
  for _, a in ipairs(G.created) do
    if a.Scale ~= nil and a.DestinationId ~= hecate.ObjectId then elsewhere = elsewhere + 1 end
  end
  check("4.4 the marker exists nowhere but on her", elsewhere == 0, tostring(elsewhere))
end

do
  -- UnitSplit is a general function; other enemies use it. It must ignore them.
  local G = boot()
  local other = { ObjectId = G.nextId(), Name = "Charybdis" }
  G.ActiveEnemies[other.ObjectId] = other
  G.UnitSplit(other, { SpawnCount = 2, SpawnedUnit = "Charybdis" })
  G.tick(2)
  check("4.5 a split by another enemy is left unmarked",
        G.markerCount(other.ObjectId) == 0, tostring(G.markerCount(other.ObjectId)))
  -- The clone-glow edit mutates shared game data, so its blast radius matters:
  -- it must touch Hecate's two clone types and nothing else.
  local intact = 0
  for id in pairs(other.SplitIds) do
    intact = intact + G.attachedCount("CharybdisGroundGlow", id)
  end
  check("4.6 and another enemy's own animations are untouched", intact == 2, tostring(intact))
end

do
  -- A Hecate split into something that is not one of her two clone types means
  -- the game changed under us. Stand down rather than guess.
  local G = boot()
  local hecate = G.spawnHecate()
  G.UnitSplit(hecate, { SpawnCount = 2, SpawnedUnit = "SomeFutureHecateCopy" })
  check("4.7 an unrecognised clone type is not marked",
        G.markerCount(hecate.ObjectId) == 0, tostring(G.markerCount(hecate.ObjectId)))
end

-- =============================================================================
-- 5. Scope gating
-- =============================================================================
do
  local G = boot({ Enabled = false })
  local hecate = G.spawnHecate()
  G.UnitSplit(hecate, EM)
  G.tick(2)
  check("5.1 the master switch off marks nothing",
        G.markerCount(hecate.ObjectId) == 0, tostring(G.markerCount(hecate.ObjectId)))
  check("5.2 and starts no watcher", G.liveThreadCount() == 0)
  -- Off must mean vanilla, which includes leaving the clones' own glow alone.
  local intact = 0
  for id in pairs(hecate.SplitIds) do
    if G.attachedCount(VANILLA, id) == 1 then intact = intact + 1 end
  end
  check("5.3 and leaves the clones' vanilla glow intact", intact == 2, tostring(intact))
end

do
  local G = boot({ MarkInExtremeMeasures = false })
  local hecate = G.spawnHecate()
  G.UnitSplit(hecate, EM)
  check("5.4 EM off skips an EM split",
        G.markerCount(hecate.ObjectId) == 0, tostring(G.markerCount(hecate.ObjectId)))
  G.UnitSplit(hecate, BASE)
  check("5.5 EM off still marks a base-fight split",
        G.anyMarkerCount(hecate.ObjectId) > 0, tostring(G.anyMarkerCount(hecate.ObjectId)))
end

do
  local G = boot({ MarkInBaseFight = false })
  local hecate = G.spawnHecate()
  G.UnitSplit(hecate, BASE)
  check("5.6 base off skips a base split",
        G.markerCount(hecate.ObjectId) == 0, tostring(G.markerCount(hecate.ObjectId)))
  G.UnitSplit(hecate, EM)
  check("5.7 base off still marks an EM split",
        G.anyMarkerCount(hecate.ObjectId) > 0, tostring(G.anyMarkerCount(hecate.ObjectId)))
end

-- =============================================================================
-- 6. Repeat splits -- she splits at every phase change
-- =============================================================================
do
  local G = boot()
  local hecate = G.spawnHecate()

  G.UnitSplit(hecate, EM)
  local firstClones = {}
  for id in pairs(hecate.SplitIds) do firstClones[#firstClones + 1] = id end

  -- The phase interlude wipes the clones (EnemyAILogic.lua:5696-5699), then the
  -- next phase forces another split (EnemyData_Hecate.lua:344). No tick between
  -- them: the tightest version of the race.
  G.killClones(hecate)
  G.UnitSplit(hecate, EM)

  check("6.1 the second split produced new clone ids",
        at(hecate.SplitIds, firstClones[1]) == nil,
        "SplitIds was not reset between splits")

  -- 6.2/6.3 guard the re-split hazard: an earlier watcher clearing the light the
  -- later split just applied. Two things independently prevent it -- the live
  -- read of SplitIds and the generation guard -- so these only go red when BOTH
  -- are sabotaged, which is verified. 6.5 pins the generation guard on its own.
  -- See the note on watchClones.
  G.tick(3)
  check("6.2 the marker survives a re-split",
        G.anyMarkerCount(hecate.ObjectId) > 0,
        "attached=" .. tostring(G.anyMarkerCount(hecate.ObjectId)))
  check("6.3 the earlier watcher did not clear it on the dead ids",
        G.anyMarkerCount(hecate.ObjectId) > 0)
  check("6.4 no second marker was stacked on top of the first",
        G.anyMarkerCount(hecate.ObjectId) == 1, tostring(G.anyMarkerCount(hecate.ObjectId)))
  check("6.5 the superseded watcher retired, leaving exactly one",
        G.liveThreadCount() == 1, tostring(G.liveThreadCount()))

  -- Each split makes NEW clones carrying a fresh vanilla glow, so the stripping
  -- has to happen every split rather than only the first.
  local strippedNow = 0
  for id in pairs(hecate.SplitIds) do
    if G.attachedCount(VANILLA, id) == 0 then strippedNow = strippedNow + 1 end
  end
  check("6.6 the second split's clones were stripped too", strippedNow == 2,
        tostring(strippedNow))
end

do
  -- Three splits, which is what an Extreme Measures fight actually does: the
  -- scripted opener plus one forced on each of the two phase changes. This is
  -- the shape the real playtest logged.
  local G = boot()
  local hecate = G.spawnHecate()
  for _ = 1, 3 do
    G.UnitSplit(hecate, EM)
    G.tick(1)
    G.killClones(hecate)
  end
  G.tick(3)
  check("6.7 three splits leave no marker behind at the end",
        G.markerCount(hecate.ObjectId) == 0,
        "attached=" .. tostring(G.markerCount(hecate.ObjectId)))
  -- Total marker creations across the whole fight, not the live count -- the
  -- live count is zero here because the last detach cleared it.
  local total = 0
  for _, a in ipairs(G.created) do
    if a.DestinationId == hecate.ObjectId and a.Scale ~= nil then total = total + 1 end
  end
  check("6.8 and never attached more than one marker's worth",
        total == 1, tostring(total))
  check("6.9 every watcher retired", G.liveThreadCount() == 0, tostring(G.liveThreadCount()))
  check("6.10 no watcher raised", #G.threadErrors == 0, tostring(G.threadErrors[1]))
end

-- =============================================================================
-- 7. The marker goes away with the clones
-- =============================================================================
do
  local G = boot()
  local hecate = G.spawnHecate()
  G.UnitSplit(hecate, EM)

  G.tick(2)
  check("7.1 the marker stays while the clones live",
        G.anyMarkerCount(hecate.ObjectId) > 0)

  -- One clone down is not all of them.
  local ids = {}
  for id in pairs(hecate.SplitIds) do ids[#ids + 1] = id end
  G.ActiveEnemies[ids[1]] = nil
  G.tick(1)
  check("7.2 the marker stays while one clone is left",
        G.anyMarkerCount(hecate.ObjectId) > 0)

  G.ActiveEnemies[ids[2]] = nil
  G.tick(1)
  -- One StopAnimation is expected to clear every stacked copy. If the game turns
  -- out to stop only one instance per call, this is the test that says so.
  check("7.3 the marker goes when the last clone dies",
        G.markerCount(hecate.ObjectId) == 0,
        "attached=" .. tostring(G.markerCount(hecate.ObjectId)))
  local lastStop = nil
  for _, s in ipairs(G.stopped) do
    if s.Name == GLOW then lastStop = s end
  end
  check("7.4 it was stopped by name, on her", at(lastStop, "DestinationId") == hecate.ObjectId)
  check("7.5 and stopped the created instance, not a base animation",
        at(lastStop, "IncludeCreatedAnimations") == true)
  check("7.6 the watcher retired", G.liveThreadCount() == 0, tostring(G.liveThreadCount()))
end

do
  -- If Hecate dies first, DieWithOwner has already taken the light. The watcher
  -- must retire rather than spin, and must not call StopAnimation on a unit that
  -- no longer exists.
  local G = boot()
  local hecate = G.spawnHecate()
  G.UnitSplit(hecate, EM)
  G.tick(1)
  G.killUnit(hecate)
  G.tick(2)
  check("7.7 the watcher retires when Hecate dies", G.liveThreadCount() == 0)
  local stoppedOnHer = 0
  for _, s in ipairs(G.stopped) do
    if s.Name == GLOW and s.DestinationId == hecate.ObjectId then stoppedOnHer = stoppedOnHer + 1 end
  end
  check("7.8 and does not stop an animation on a dead unit", stoppedOnHer == 0,
        tostring(stoppedOnHer))
end

-- =============================================================================
-- 8. KeepAfterClonesGone
-- =============================================================================
do
  local G = boot({ KeepAfterClonesGone = true })
  local hecate = G.spawnHecate()
  G.UnitSplit(hecate, EM)
  check("8.1 it marks her", G.anyMarkerCount(hecate.ObjectId) > 0)

  G.killClones(hecate)
  G.tick(3)
  check("8.2 the marker stays after the clones die",
        G.anyMarkerCount(hecate.ObjectId) > 0,
        "attached=" .. tostring(G.anyMarkerCount(hecate.ObjectId)))
end

-- =============================================================================
-- 9. Brightness -- stacking, and stripping the clones' glow
-- =============================================================================
-- These two are the v1.1.0 answer to "the light does not stand out enough", and
-- they are the reason the fix stayed inside the ground light instead of becoming
-- a different mechanism.
do
  local G = boot({ Light = true, LightStacking = 1 })
  local hecate = G.spawnHecate()
  G.UnitSplit(hecate, EM)
  check("9.1 stacking 1 attaches one copy",
        G.markerCount(hecate.ObjectId) == 1,
        tostring(G.markerCount(hecate.ObjectId)))
end

do
  local G = boot({ Light = true, LightStacking = 6 })
  local hecate = G.spawnHecate()
  G.UnitSplit(hecate, EM)
  check("9.2 stacking 6 attaches six copies",
        G.markerCount(hecate.ObjectId) == 6,
        tostring(G.markerCount(hecate.ObjectId)))
  -- Brightness must be live: this is what buys tuning without a restart.
end

do
  local G = boot({ Light = true, LightStacking = 0 })
  local hecate = G.spawnHecate()
  G.UnitSplit(hecate, EM)
  check("9.4 stacking 0 is clamped up to at least one copy",
        G.markerCount(hecate.ObjectId) >= 1,
        tostring(G.markerCount(hecate.ObjectId)))
end

do
  local G = boot({ Light = true, LightStacking = 99 })
  local hecate = G.spawnHecate()
  G.UnitSplit(hecate, EM)
  check("9.5 stacking 99 is clamped down", G.markerCount(hecate.ObjectId) <= 8,
        tostring(G.markerCount(hecate.ObjectId)))
end

do
  -- The clone glow is removed in DATA at load, so a clone never has one to begin
  -- with. No thread, no wait, nothing to time.
  local G = boot()
  local hecate = G.spawnHecate()
  G.UnitSplit(hecate, EM)

  local lit = 0
  for id in pairs(hecate.SplitIds) do lit = lit + G.attachedCount(VANILLA, id) end
  check("9.6 clones spawn with no ground glow at all", lit == 0, tostring(lit))

  -- THE v2.5.0 CORRECTION. This assertion used to read "her own vanilla glow is
  -- left alone" and was treated as the desired behaviour. It was the bug.
  --
  -- Leaving it meant she carried TWO lights: vanilla's, at scale 1.33 and
  -- ping-ponging teal to magenta, and this mod's smaller one inside it. A
  -- playtest saw "blue white on the outside but a light orangish on the inside",
  -- and three earlier rounds of "the colour will not change" were the same
  -- thing -- vanilla's larger colour-cycling pool drowning a marker that was
  -- changing colour correctly all along.
  -- She spawns with NO glow of her own; every copy on her is the marker. Since
  -- the marker now uses vanilla's animation name, that is the only way the two
  -- stay distinguishable -- see G.markerCount.
  local spawned = 0
  for _, a in ipairs(G.created) do
    if a.Name == VANILLA and a.DestinationId == hecate.ObjectId and a.Scale == nil then
      spawned = spawned + 1
    end
  end
  check("9.7 she spawns with no glow of her own, so only the marker lights her",
        spawned == 0, tostring(spawned))

  -- Only the ground glow comes off. Taking the torches would make the clones
  -- obviously wrong rather than subtly distinguishable.
  local torches = 0
  for id in pairs(hecate.SplitIds) do
    torches = torches + G.attachedCount("HecateTorchFlameLeft", id)
                      + G.attachedCount("HecateTorchFlameRight", id)
  end
  check("9.8 the clones keep their torch flames", torches == 4, tostring(torches))
end

do
  -- Later splits get it for free, because the data no longer lists the glow.
  local G = boot()
  local hecate = G.spawnHecate()
  G.UnitSplit(hecate, EM)
  G.tick(2)
  G.killClones(hecate)
  G.UnitSplit(hecate, EM)
  G.tick(2)
  local lit = 0
  for id in pairs(hecate.SplitIds) do lit = lit + G.attachedCount(VANILLA, id) end
  check("9.9 a later split's clones have no glow either", lit == 0, tostring(lit))
end

do
  -- The setting that fixes it, and the state that caused it.
  local G = boot({ Light = true, ReplaceVanillaGlow = false })
  local hecate = G.spawnHecate()
  G.UnitSplit(hecate, EM)
  local spawned = 0
  for _, a in ipairs(G.created) do
    if a.Name == VANILLA and a.DestinationId == hecate.ObjectId and a.Scale == nil then
      spawned = spawned + 1
    end
  end
  check("9.9b off leaves her spawn glow on as well as the marker",
        spawned == 1 and G.markerCount(hecate.ObjectId) == STACK,
        "spawned=" .. tostring(spawned)
          .. " marker=" .. tostring(G.markerCount(hecate.ObjectId)))
end

do
  -- Independent of the clone strip: one can be on without the other.
  local G = boot({ Light = true, RemoveCloneGlow = false, ReplaceVanillaGlow = true })
  local hecate = G.spawnHecate()
  G.UnitSplit(hecate, EM)
  local lit = 0
  for id in pairs(hecate.SplitIds) do lit = lit + G.attachedCount(VANILLA, id) end
  local spawned = 0
  for _, a in ipairs(G.created) do
    if a.Name == VANILLA and a.DestinationId == hecate.ObjectId and a.Scale == nil then
      spawned = spawned + 1
    end
  end
  check("9.9c the two glow settings are independent",
        spawned == 0 and lit == 2,
        "herSpawn=" .. tostring(spawned) .. " clones=" .. tostring(lit))
end

do
  local G = boot({ RemoveCloneGlow = false })
  local hecate = G.spawnHecate()
  G.UnitSplit(hecate, EM)
  local lit = 0
  for id in pairs(hecate.SplitIds) do lit = lit + G.attachedCount(VANILLA, id) end
  check("9.10 the strip can be switched off", lit == 2, tostring(lit))
end

do
  -- Enabled off must mean vanilla, and clones missing their glow is not vanilla.
  local G = boot({ Enabled = false })
  local hecate = G.spawnHecate()
  G.UnitSplit(hecate, EM)
  local lit = 0
  for id in pairs(hecate.SplitIds) do lit = lit + G.attachedCount(VANILLA, id) end
  check("9.11 the master switch off leaves the clones lit", lit == 2, tostring(lit))
end

do
  local G = boot({ Light = false, Outline = true })
  local hecate = G.spawnHecate()
  G.UnitSplit(hecate, EM)
  check("9.12 the light can be switched off entirely",
        G.markerCount(hecate.ObjectId) == 0, tostring(G.markerCount(hecate.ObjectId)))
  check("9.13 leaving the outline as the only marker",
        at(G.outlines, hecate.ObjectId) ~= nil)
end

do
  -- THE v1.2.0 REGRESSION GUARD.
  --
  -- v1.0.0 and v1.1.0 passed Group = "FX_Terrain" here and rendered nothing at
  -- all through two playtests, while logging complete success at every step. The
  -- game's own call for these animations passes Name and DestinationId and
  -- nothing else (RoomLogic.lua:3384). Anything extra is a change, not a
  -- clarification, and this asserts the call stays exactly that shape.
  local G = boot({ Light = true })
  local hecate = G.spawnHecate()
  G.UnitSplit(hecate, EM)

  local ours = nil
  for _, a in ipairs(G.created) do
    if a.Name == GLOW then ours = a break end
  end
  check("9.14 the marker is actually created", ours ~= nil)
  check("9.15 it passes NO Group -- the bug that made two builds invisible",
        at(ours, "Group") == nil, "Group=" .. tostring(at(ours, "Group")))

  -- Name, DestinationId and Scale. Scale is allowed because the game's own
  -- scripts pass it on 113 CreateAnimation calls; anything BEYOND these three is
  -- the Group mistake again, so the assertion stays exhaustive.
  local extra = {}
  for k in pairs(ours or {}) do
    if k ~= "Name" and k ~= "DestinationId" and k ~= "Scale" then
      extra[#extra + 1] = k
    end
  end
  check("9.16 and passes nothing beyond Name/DestinationId/Scale",
        #extra == 0, table.concat(extra, ","))
  check("9.17 scale rides on the call, which is what makes it live",
        at(ours, "Scale") == 1.0, tostring(at(ours, "Scale")))
end

-- =============================================================================
-- 10. The outline fallback
-- =============================================================================
do
  local G = boot()
  local hecate = G.spawnHecate()
  G.UnitSplit(hecate, EM)
  check("10.1 the outline is applied by default", at(G.outlines, hecate.ObjectId) ~= nil)
end

do
  local G, plugin = boot({ Outline = true, OutlineColor = "Cyan",
                           OutlineThickness = 7, OutlineOpacity = 0.5 })
  local hecate = G.spawnHecate()
  G.UnitSplit(hecate, EM)
  local o = at(G.outlines, hecate.ObjectId)
  local cyan = at(at(at(plugin, "CONFIG"), "colors"), "Cyan")

  check("10.2 the outline lands on her", o ~= nil)
  -- The load-bearing one, mirroring 4.3 for the light: an outline on a CLONE
  -- would actively mislead, which is worse than no marker at all.
  local onClone = false
  for id in pairs(hecate.SplitIds) do
    if at(G.outlines, id) ~= nil then onClone = true end
  end
  check("10.2b and on no clone", onClone == false)
  -- AddOutline takes 0-255 where the light's sjson takes 0-1. Getting this
  -- backwards would produce a black outline that looks like nothing at all.
  check("10.3 its colour is converted to 0-255",
        at(o, "R") == math.floor(at(cyan, 1) * 255 + 0.5)
        and at(o, "G") == math.floor(at(cyan, 2) * 255 + 0.5),
        "R=" .. tostring(at(o, "R")))
  check("10.4 thickness carries through", at(o, "Thickness") == 7, tostring(at(o, "Thickness")))
  check("10.5 opacity carries through", at(o, "Opacity") == 0.5, tostring(at(o, "Opacity")))
  check("10.6 threshold matches every outline the game itself uses",
        at(o, "Threshold") == 0.6, tostring(at(o, "Threshold")))

  G.killClones(hecate)
  G.tick(2)
  check("10.7 the outline is removed with the clones",
        at(G.outlines, hecate.ObjectId) == nil)
end

do
  local G = boot({ Outline = true, OutlineThickness = 99, OutlineOpacity = 5 })
  local hecate = G.spawnHecate()
  G.UnitSplit(hecate, EM)
  local o = at(G.outlines, hecate.ObjectId)
  check("10.8 an absurd thickness is clamped",
        type(at(o, "Thickness")) == "number" and at(o, "Thickness") <= 10,
        tostring(at(o, "Thickness")))
  check("10.9 an out-of-range opacity is clamped",
        type(at(o, "Opacity")) == "number" and at(o, "Opacity") <= 1,
        tostring(at(o, "Opacity")))
end

do
  -- Dream runs outline her red themselves (PresentationBiomeF.lua:33-36). Ours
  -- replaces it; removing ours must not leave her the only bare unit in a mode
  -- where everything is outlined.
  local G = boot({ Outline = true })
  G.CurrentRun.IsDreamRun = true
  local hecate = G.spawnHecate()
  G.UnitSplit(hecate, EM)
  G.killClones(hecate)
  G.tick(2)
  local o = at(G.outlines, hecate.ObjectId)
  check("10.10 a dream run gets vanilla's red outline back", o ~= nil)
  check("10.11 and it is vanilla's exact red",
        at(o, "R") == 230 and at(o, "G") == 23 and at(o, "B") == 0,
        "R=" .. tostring(at(o, "R")))
end

do
  local G = boot({ Outline = true })
  G.CurrentRun.IsDreamRun = false
  local hecate = G.spawnHecate()
  G.UnitSplit(hecate, EM)
  G.killClones(hecate)
  G.tick(2)
  check("10.12 a normal run is left with no outline at all",
        at(G.outlines, hecate.ObjectId) == nil)
end

-- =============================================================================
-- =============================================================================
-- 10c. The overlay panel
-- =============================================================================
-- Settings were file-only until v2.2.0, and a playtest went looking for them in
-- the modding overlay. Chalk does not draw a panel -- that is separate rom.gui
-- code -- so this had to be written, and ImGui punishes three specific mistakes.
do
  local G = boot()
  check("10c.1 the panel registers", M.guiCallbacks.window ~= nil)
  check("10c.2 the menu bar entry registers", M.guiCallbacks.menuBar ~= nil)
  check("10c.3 and it is reported", logsContain("overlay panel registered"))
end

do
  -- Begin/End must balance. A leaked window corrupts the overlay for EVERY mod,
  -- not just this one.
  boot()
  M.guiCallbacks.window()
  check("10c.4 Begin and End balance on a normal frame", at(M.depth, "window") == 0,
        "depth=" .. tostring(at(M.depth, "window")))
end

do
  -- ImGui's contract: End is called even when Begin returns false (collapsed).
  boot(nil, { gui = { collapsed = true } })
  M.guiCallbacks.window()
  check("10c.5 they balance when the window is collapsed", at(M.depth, "window") == 0,
        "depth=" .. tostring(at(M.depth, "window")))
end

do
  -- The dangerous case: something raises after Begin pushed a window.
  boot(nil, { gui = { errorInBody = true } })
  local ok = pcall(M.guiCallbacks.window)
  check("10c.6 a failure in the body does not escape the panel", ok == true)
  check("10c.7 and the window is still closed", at(M.depth, "window") == 0,
        "depth=" .. tostring(at(M.depth, "window")))
  check("10c.8 and it is logged", logsContain("overlay panel failed"))
end

do
  -- EndCombo only when BeginCombo returned true.
  boot(nil, { gui = { openCombo = true } })
  M.guiCallbacks.window()
  check("10c.9 combos balance when open", at(M.depth, "combo") == 0,
        "depth=" .. tostring(at(M.depth, "combo")))
  boot(nil, { gui = { openCombo = false } })
  M.guiCallbacks.window()
  check("10c.10 and when closed", at(M.depth, "combo") == 0,
        "depth=" .. tostring(at(M.depth, "combo")))
end

do
  boot(nil, { gui = { openMenu = true } })
  M.guiCallbacks.menuBar()
  check("10c.11 menus balance when open", at(M.depth, "menu") == 0,
        "depth=" .. tostring(at(M.depth, "menu")))
end

do
  -- ImGui widgets are keyed by their label STRING. Two widgets sharing a label
  -- are one widget, and each will move the other. This is the reason every label
  -- in the panel carries a ##unique suffix, and the reason it is worth asserting
  -- rather than trusting.
  boot(nil, { gui = { openCombo = true } })
  M.guiCallbacks.window()
  local seen, dupes = {}, {}
  for _, l in ipairs(M.labels) do
    l = tostring(l)
    -- Only interactive widgets are keyed this way; Text/TextDisabled are not.
    if not l:find("^Text") and not l:find("^Begin:") then
      if seen[l] then dupes[#dupes + 1] = l end
      seen[l] = true
    end
  end
  check("10c.12 no two widgets share a label", #dupes == 0, table.concat(dupes, ", "))
end

do
  -- Toggling in the panel must write through to the config, not just to memory.
  local G, plugin = boot(nil, { gui = { toggle = "Enabled##TrueHecate_Enabled" } })
  check("10c.13 starts enabled", at(at(plugin, "settings"), "values").Enabled == true)
  M.guiCallbacks.window()
  check("10c.14 the checkbox flips the setting",
        at(at(plugin, "settings"), "values").Enabled == false)
  check("10c.15 and persists it to the config store", M.store.Enabled == false,
        tostring(M.store.Enabled))
end

do
  -- A combo selection has to reach the live variant picker, which is the whole
  -- point of tuning from the overlay.
  local G, plugin = boot(nil, { gui = { openCombo = true, click = "Ember##TrueHecate_Color_Ember" } })
  M.guiCallbacks.window()
  check("10c.16 picking a colour writes it through",
        M.store.Color == "Ember", tostring(M.store.Color))
  -- Colour is baked into vanilla's light entry at load, so a change from the
  -- panel lands on the NEXT launch, not the next split. The panel says so.
  check("10c.17 and it resolves to that preset",
        at(plugin.CONFIG.resolvedColor(), 1)
          == at(at(at(plugin, "CONFIG"), "colors").Ember, 1))
end

do
  local G, plugin = boot({ Light = true },
                         { gui = { slide = "Stacking##TrueHecate_LightStacking", slideTo = 7 } })
  M.guiCallbacks.window()
  check("10c.18 a slider writes through", M.store.LightStacking == 7,
        tostring(M.store.LightStacking))
  local hecate = G.spawnHecate()
  G.UnitSplit(hecate, EM)
  check("10c.19 and takes effect at the very next split, no restart",
        G.markerCount(hecate.ObjectId) == 7,
        "attached=" .. tostring(G.markerCount(hecate.ObjectId)))
end

do
  -- No overlay must cost the panel and nothing else.
  local G = boot({ Light = true }, { noGui = true })
  check("10c.20 a missing rom.gui is reported, not raised",
        logsContain("rom.gui unavailable"))
  check("10c.21 and the hook still installs", at(G.wrapped, "UnitSplit") == 1)
  local hecate = G.spawnHecate()
  G.UnitSplit(hecate, EM)
  check("10c.22 and the marker still works",
        G.markerCount(hecate.ObjectId) == STACK)
end

-- =============================================================================
-- =============================================================================
-- 10e. Recolouring vanilla's own light entry
-- =============================================================================
-- The last colour mechanism left untried. Every previous attempt registered a
-- NEW animation and attached it; those rendered but never took their colour.
-- Runtime SetColor on the returned animation id did nothing either. This edits
-- the entry the engine already honours, in place.
do
  local G, plugin = boot({ Color = "Ember", SteadyColor = true })
  local light = findAnim("HecateGroundLight")
  local ember = at(at(at(plugin, "CONFIG"), "colors"), "Ember")
  check("10e.1 vanilla's own light entry is recoloured in place", light ~= nil)
  check("10e.2 to the chosen colour",
        at(light, "StartRed") == at(ember, 1)
        and at(light, "StartGreen") == at(ember, 2)
        and at(light, "StartBlue") == at(ember, 3),
        tostring(at(light, "StartRed")))
  check("10e.3 with equal endpoints, so it holds instead of cycling",
        at(light, "EndRed") == at(light, "StartRed")
        and at(light, "EndGreen") == at(light, "StartGreen")
        and at(light, "EndBlue") == at(light, "StartBlue"))
  -- PingPongColor is vanilla's and must stay untouched: it is what makes the
  -- ramp run at all, and with equal ends there is nothing for it to move between.
  check("10e.4 leaving PingPongColor exactly as vanilla set it",
        at(light, "PingPongColor") == true, tostring(at(light, "PingPongColor")))
end

do
  local G, plugin = boot({ Color = "Cyan", SteadyColor = false })
  local light = findAnim("HecateGroundLight")
  check("10e.5 cycling mode keeps vanilla's magenta far end",
        at(light, "EndRed") == 1 and at(light, "EndGreen") == 0 and at(light, "EndBlue") == 1,
        tostring(at(light, "EndRed")))
  local cyan = at(at(at(plugin, "CONFIG"), "colors"), "Cyan")
  check("10e.6 while still starting from the chosen colour",
        at(light, "StartGreen") == at(cyan, 2))
end

do
  -- The clipping guard. Colour survives only while the SECOND channel stays
  -- under 1.0 after stacking; Amber at 3 copies does not, and shipped that way
  -- once.
  local _, plugin = boot()
  local v = at(at(plugin, "settings"), "values")
  local rgb = plugin.CONFIG.resolvedColor()
  local scaled = { rgb[1] * v.LightStacking, rgb[2] * v.LightStacking, rgb[3] * v.LightStacking }
  table.sort(scaled, function(x, y) return x > y end)
  check("10e.11 the shipped colour and stacking do not clip to white",
        scaled[2] < 1.0, string.format("second channel %.2f", scaled[2]))
  check("10e.12 while still driving the top channel past a single light",
        scaled[1] > 1.0, string.format("top %.2f", scaled[1]))
  check("10e.13 and the shipped combination is not warned about",
        not logsContain("washes out"))
end

do
  boot({ Color = "Amber", LightStacking = 3 })
  check("10e.14 a washing combination IS warned about", logsContain("washes out"))
end

do
  -- Invert: darken instead of brighten. The escape from additive clipping --
  -- the arena floor is already saturated, so adding light washes out but
  -- removing it cannot be washed out by anything.
  local G = boot({ Invert = true })
  local light = findAnim("HecateGroundLight")
  check("10e.15 invert swaps in the darkening texture",
        at(light, "FilePath") == [[Lights\DiffuseSpotlightInverse]],
        tostring(at(light, "FilePath")))
end

do
  local G = boot({ Invert = false })
  local light = findAnim("HecateGroundLight")
  check("10e.16 off leaves vanilla's own texture",
        at(light, "FilePath") == [[Lights\DiffuseSpotlight]],
        tostring(at(light, "FilePath")))
  check("10e.17 and invert ships ON",
        at(at(select(2, boot()), "settings"), "values").Invert == true)
end

do
  local G = boot({ Recolour = false })
  local light = findAnim("HecateGroundLight")
  check("10e.7 off leaves vanilla's entry completely alone",
        light == nil or (at(light, "StartGreen") == 1 and at(light, "StartBlue") == 0.7))
end

do
  -- Medea uses a separate entry with identical values. Editing Hecate's must not
  -- reach it -- that is the whole blast-radius claim.
  boot({ Color = "Ember" })
  check("10e.8 MedeaGroundLight is untouched", findAnim("MedeaGroundLight") == nil)
end

do
  local G = boot({ Light = true }, { sjsonOpts = { absent = true } })
  check("10e.9 no SJSON costs only the colour", logsContain("SJSON unavailable"))
  local hecate = G.spawnHecate()
  G.UnitSplit(hecate, EM)
  check("10e.10 and the marker still works",
        G.markerCount(hecate.ObjectId) == STACK)
end

-- =============================================================================
-- 10f. Ground sprites -- the answer to "can the ground be orange"
-- =============================================================================
-- Not by tinting a light: the floor is a painted cyan image and additive light
-- clips toward white on it. By attaching vanilla art that is already orange.
do
  local G = boot()
  local hecate = G.spawnHecate()
  G.UnitSplit(hecate, EM)
  local shipped
  for _, c in ipairs(G.created) do
    if c.Name == SHIPPED_FX then shipped = c end
  end
  check("10f.1b it ships big enough to see -- 1.0 was reported as too small",
        at(shipped, "Scale") == 3.0, tostring(at(shipped, "Scale")))
  check("10f.1 the shipped ground sprite attaches to her",
        G.attachedCount(SHIPPED_FX, hecate.ObjectId) == 1,
        tostring(G.attachedCount(SHIPPED_FX, hecate.ObjectId)))
  local onClone = false
  for id in pairs(hecate.SplitIds) do
    if G.attachedCount(SHIPPED_FX, id) ~= 0 then onClone = true end
  end
  check("10f.2 and to no clone", onClone == false)
end

do
  local G = boot({ GroundFx = "CastCircle" })
  local hecate = G.spawnHecate()
  G.UnitSplit(hecate, EM)
  check("10f.3 the ring option attaches the ring",
        G.attachedCount("ApolloAoECircleA", hecate.ObjectId) == 1)
  check("10f.4 and not the glow", G.attachedCount(SHIPPED_FX, hecate.ObjectId) == 0)
end

do
  local G = boot({ GroundFx = "None" })
  local hecate = G.spawnHecate()
  G.UnitSplit(hecate, EM)
  check("10f.5 None attaches no ground art at all",
        G.attachedCount(SHIPPED_FX, hecate.ObjectId) == 0
        and G.attachedCount("ApolloAoECircleA", hecate.ObjectId) == 0)
end

do
  -- The setting is live, so the sprite attached before a change must still be
  -- removed after it -- the same stranding hazard the colour variants had.
  local G = boot({ GroundFx = "ApolloGlow" })
  local hecate = G.spawnHecate()
  G.UnitSplit(hecate, EM)
  M.store.GroundFx = "CastCircle"
  M.onReload()
  G.killClones(hecate)
  G.tick(3)
  check("10f.6 a sprite attached before a reload is still removed",
        G.attachedCount(SHIPPED_FX, hecate.ObjectId) == 0,
        "stranded=" .. tostring(G.attachedCount(SHIPPED_FX, hecate.ObjectId)))
end

do
  local G = boot({ GroundFxScale = 99 })
  local hecate = G.spawnHecate()
  G.UnitSplit(hecate, EM)
  local a
  for _, c in ipairs(G.created) do
    if c.Name == SHIPPED_FX then a = c end
  end
  check("10f.7 an absurd ground scale is clamped",
        type(at(a, "Scale")) == "number" and at(a, "Scale") <= 12.0,
        tostring(at(a, "Scale")))
end

do
  -- Every palette entry must name art that exists and attach cleanly. A typo in
  -- this table would silently attach nothing, which is the exact shape of the
  -- v1.0.0 failure -- a call that looks right and draws nothing.
  local _, plugin = boot()
  local bad = {}
  for _, key in ipairs(plugin.GROUND_FX_ORDER) do
    local G2 = dofile(HARNESS)
    M.install(G2, nil, { GroundFx = key }, nil, {}, nil)
    dofile(PLUGIN)
    if M.pendingGameLoad then M.pendingGameLoad() end
    local h = G2.spawnHecate()
    G2.UnitSplit(h, EM)
    local attached = 0
    for _, c in ipairs(G2.created) do
      if c.Scale ~= nil and c.Name ~= VANILLA then attached = attached + 1 end
    end
    local expected = (key == "None") and 0 or 1
    if attached ~= expected then bad[#bad + 1] = key .. "=" .. attached end
  end
  check("10f.8 every ground palette entry attaches exactly one sprite",
        #bad == 0, table.concat(bad, ", "))
end

do
  -- Every ground sprite offered must LOOP, or it flashes once and is gone. That
  -- is not checkable from Lua, so it is pinned as an explicit allow-list here:
  -- both entries were read out of the animation data and carry Loop = true.
  local _, plugin = boot()
  local looping = { ApolloGroundGlow = true, ApolloAoECircleA = true }
  local bad = {}
  for key, name in pairs(plugin.GROUND_FX) do
    if name ~= nil and not looping[name] then bad[#bad + 1] = key .. "/" .. name end
  end
  check("10f.9 every offered ground sprite is a looping animation",
        #bad == 0, table.concat(bad, ", "))
end

do
  -- The sprite tint path: Color on CreateAnimation, 0-255, which is how vanilla
  -- tints sprites. Distinct from the light recolour, which needed sjson.
  local G, plugin = boot({ GroundFxColor = "Red" })
  local hecate = G.spawnHecate()
  G.UnitSplit(hecate, EM)
  local a
  for _, c in ipairs(G.created) do
    if c.Name == SHIPPED_FX then a = c end
  end
  local red = at(at(at(plugin, "CONFIG"), "colors"), "Red")
  local col = at(a, "Color")
  check("10f.10 the ground sprite carries a Color", col ~= nil)
  check("10f.11 in 0-255, not the 0-1 the animation data uses",
        at(col, 1) == math.floor(at(red, 1) * 255 + 0.5) and at(col, 4) == 255,
        table.concat({ tostring(at(col,1)), tostring(at(col,2)),
                       tostring(at(col,3)), tostring(at(col,4)) }, "/"))
end

do
  local G = boot({ GroundFxColor = "None" })
  local hecate = G.spawnHecate()
  G.UnitSplit(hecate, EM)
  local a
  for _, c in ipairs(G.created) do
    if c.Name == SHIPPED_FX then a = c end
  end
  check("10f.12 None leaves the art its own colour", at(a, "Color") == nil)
end

-- =============================================================================
-- 10g. The Dream Dive clone outline
-- =============================================================================
-- In a Dream run the base fight's clones carry the SAME red outline the real
-- Hecate does, so an outline identifies nothing there. All four outline events
-- are gated on IsDreamRun, so this edit cannot affect a normal fight.
local function outlineEventCount(G, unit)
  local n = 0
  for _, ev in ipairs(((G.EnemyData or {})[unit] or {}).SetupEvents or {}) do
    if at(ev, "Args") ~= nil and ev.Args.Outline ~= nil then n = n + 1 end
  end
  return n
end

do
  local G = boot()
  check("10g.1 the base clones lose their Dream outline",
        outlineEventCount(G, "HecateCopy") == 0,
        tostring(outlineEventCount(G, "HecateCopy")))
  check("10g.2 and the EM clones lose BOTH of theirs",
        outlineEventCount(G, "HecateCopyEM") == 0,
        tostring(outlineEventCount(G, "HecateCopyEM")))
  -- The load-bearing one. Hers is a separate event at EnemyData_Hecate.lua:175,
  -- and stripping it would remove the very thing that identifies her in Dream
  -- mode -- turning the fix into the bug it was meant to solve.
  check("10g.3 while HER own outline event survives untouched",
        outlineEventCount(G, "Hecate") == 1,
        tostring(outlineEventCount(G, "Hecate")))
end

do
  -- Surgical: those same events carry the clones' Dream texture. Removing the
  -- whole event would leave them wrongly textured in Dream mode.
  local G = boot()
  local kept = 0
  for _, unit in ipairs({ "HecateCopy", "HecateCopyEM" }) do
    for _, ev in ipairs(((G.EnemyData or {})[unit] or {}).SetupEvents or {}) do
      if at(ev, "Args") ~= nil and ev.Args.GrannyTexture ~= nil then kept = kept + 1 end
    end
  end
  check("10g.4 the clones keep their Dream texture", kept == 3, tostring(kept))
  local flags = 0
  for _, unit in ipairs({ "HecateCopy", "HecateCopyEM" }) do
    for _, ev in ipairs(((G.EnemyData or {})[unit] or {}).SetupEvents or {}) do
      if at(ev, "Args") ~= nil and ev.Args.AddOutlineImmediately ~= nil then flags = flags + 1 end
    end
  end
  check("10g.5 and the now-meaningless flag goes with the outline",
        flags == 0, tostring(flags))
end

do
  -- The question that killed the v1.1.0 runtime strip: does it hold for LATER
  -- splits? It must, because every clone is DeepCopyTable'd from the shared
  -- EnemyData table re-read inside the spawn loop -- but assert it rather than
  -- trust the reasoning.
  local G = boot()
  local hecate = G.spawnHecate()
  for round = 1, 3 do
    G.UnitSplit(hecate, EM)
    local outlined = 0
    for id in pairs(hecate.SplitIds) do
      if at(G.outlines, id) ~= nil then outlined = outlined + 1 end
    end
    check("10g.8 split " .. round .. ": no clone is outlined",
          outlined == 0, tostring(outlined))
    G.tick(1)
    G.killClones(hecate)
  end
end

do
  -- And with the strip off, the clones ARE outlined -- so the test above is
  -- measuring the strip rather than a harness that never outlines anything.
  local G = boot({ StripCloneDreamOutline = false })
  local hecate = G.spawnHecate()
  G.UnitSplit(hecate, EM)
  local outlined = 0
  for id in pairs(hecate.SplitIds) do
    if at(G.outlines, id) ~= nil then outlined = outlined + 1 end
  end
  check("10g.9 with the strip off the clones are outlined, as vanilla does",
        outlined == 2, tostring(outlined))
end

do
  local G = boot({ StripCloneDreamOutline = false })
  check("10g.6 it can be switched off",
        outlineEventCount(G, "HecateCopy") == 1
        and outlineEventCount(G, "HecateCopyEM") == 2)
end

do
  local G = boot({ Enabled = false })
  check("10g.7 the master switch off leaves every outline alone",
        outlineEventCount(G, "HecateCopy") == 1
        and outlineEventCount(G, "HecateCopyEM") == 2
        and outlineEventCount(G, "Hecate") == 1)
end

-- =============================================================================
-- 11. Nothing here may break the fight
-- =============================================================================
do
  local _, plugin = boot(nil, { configOpts = { absent = true } })
  check("11.5 no rom.config still runs, in memory",
        at(at(plugin, "settings"), "persistent") == false)
  check("11.6 and defaults are intact",
        at(at(at(plugin, "settings"), "values"), "Enabled") == true)
  check("11.7 and says so", logsContain("rom.config unavailable"))
end

do
  local _, plugin = boot(nil, { configOpts = { throw = true } })
  check("11.8 a config failure is caught", logsContain("config load failed"))
  check("11.9 and leaves usable defaults",
        at(at(at(plugin, "settings"), "values"), "Color") == "Ember")
end

do
  local G = boot(nil, { noModUtil = true })
  check("11.10 no ModUtil is reported, not raised", logsContain("ModUtil.Path.Wrap unavailable"))
  check("11.11 and UnitSplit is left vanilla", next(G.wrapped) == nil)
  local hecate = G.spawnHecate()
  G.UnitSplit(hecate, EM)
  check("11.12 and the split still happens", countKeys(hecate.SplitIds) == 2,
        tostring(countKeys(hecate.SplitIds)))
end

do
  -- The marker raising must cost the marker, not the boss fight. Scoped to OUR
  -- animation so the failure is in the plugin's own call, not in the split.
  local G = boot({ Light = true })
  local realCreate = G.CreateAnimation
  G.CreateAnimation = function(args)
    if args.Name == GLOW then error("simulated engine failure") end
    return realCreate(args)
  end
  local hecate = G.spawnHecate()
  local ok = pcall(G.UnitSplit, hecate, EM)
  check("11.13 a marker failure does not propagate out of UnitSplit", ok == true)
  check("11.14 and the clones still spawned", countKeys(hecate.SplitIds) == 2,
        tostring(countKeys(hecate.SplitIds)))
  check("11.15 and it is logged", logsContain("could not mark the real Hecate"))
end

do
  -- Likewise for the outline path.
  local G = boot({ Outline = true })
  G.AddOutline = function() error("simulated outline failure") end
  local hecate = G.spawnHecate()
  local ok = pcall(G.UnitSplit, hecate, EM)
  check("11.16 an outline failure does not propagate either", ok == true)
  check("11.17 and the clones still spawned", countKeys(hecate.SplitIds) == 2,
        tostring(countKeys(hecate.SplitIds)))
end

do
  -- The clone-glow edit reaches into game data at load. If EnemyData is not
  -- shaped the way this expects, that must cost the strip and nothing else.
  local G = dofile(HARNESS)
  M.install(G, nil, { Light = true }, nil)
  G.EnemyData = nil
  local plugin = dofile(PLUGIN)
  if M.pendingGameLoad then M.pendingGameLoad() end

  check("11.18 missing EnemyData is reported, not raised",
        logsContain("EnemyData unavailable"))
  check("11.19 and the hook still installs", at(G.wrapped, "UnitSplit") == 1)
  check("11.20 and the plugin still loaded", plugin ~= nil)

  local hecate = G.spawnHecate()
  local ok = pcall(G.UnitSplit, hecate, EM)
  check("11.21 and the split still works, marker and all",
        ok == true and G.markerCount(hecate.ObjectId) == STACK,
        "attached=" .. tostring(G.markerCount(hecate.ObjectId)))
end

-- =============================================================================

print(("TrueHecate: %d passed, %d failed"):format(passed, failed))
for _, f in ipairs(failures) do print("  FAIL  " .. f) end
if failed > 0 then os.exit(1) end
