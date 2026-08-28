-- Fake game globals for RealHecate. Only what the plugin actually touches, plus
-- a faithful-enough UnitSplit and a cooperative thread scheduler so the suite
-- can drive the clone watcher deterministically instead of sleeping.

local unpack = table.unpack or unpack

local G = {}

-- ---------------------------------------------------------------- state ----

G.ActiveEnemies = {}
G.CurrentRun = { IsDreamRun = false }

-- Only the CreateAnimations lists matter here. Copied from
-- EnemyData_Hecate.lua:21 (Hecate) and :5564-5568 (HecateCopy, which HecateCopyEM
-- inherits). The torch flames are present on the clones on purpose: the plugin
-- removes the ground glow and must leave those, or the clones stop looking like
-- Hecate at all.
G.EnemyData = {
  -- EnemyData_Hecate.lua:175. HERS, and it must survive untouched -- stripping it
  -- would remove the very outline that identifies her in Dream mode.
  Hecate = {
    CreateAnimations = { "HecateGroundGlow" },
    SetupEvents = {
      { FunctionName = "OverwriteSelf",
        Args = { AddOutlineImmediately = true,
                 Outline = { R = 25, G = 200, B = 160, Opacity = 0.8, Thickness = 3, Threshold = 0.6 } } },
    },
  },
  HecateCopy = {
    CreateAnimations = { "HecateGroundGlow", "HecateTorchFlameLeft", "HecateTorchFlameRight" },
    -- EnemyData_Hecate.lua:5632. RED -- the same colour the real Hecate gets in a
    -- Dream run, which is why the outline identifies nothing there unless the
    -- clones are stripped. GrannyTexture must survive the strip.
    SetupEvents = {
      { FunctionName = "OverwriteSelf",
        Args = { GrannyTexture = "GR2/HecateBattleDream_Color",
                 AddOutlineImmediately = true,
                 Outline = { R = 230, G = 23, B = 0, Opacity = 0.8, Thickness = 3, Threshold = 0.6 } } },
    },
  },
  HecateCopyEM = {
    CreateAnimations = { "HecateGroundGlow", "HecateTorchFlameLeft", "HecateTorchFlameRight" },
    -- Two of them: teal on the opening split (:5745), red on the phase splits
    -- (:5771). Both must go.
    SetupEvents = {
      { FunctionName = "OverwriteSelf",
        Args = { GrannyTexture = "GR2/HecateEMDream_Color",
                 AddOutlineImmediately = true,
                 Outline = { R = 25, G = 200, B = 160, Opacity = 0.8, Thickness = 3, Threshold = 0.6 } } },
      { FunctionName = "OverwriteSelf",
        Args = { GrannyTexture = "GR2/HecateEMDream_Color",
                 AddOutlineImmediately = true,
                 Outline = { R = 230, G = 23, B = 0, Opacity = 0.8, Thickness = 3, Threshold = 0.6 } } },
    },
  },
  -- An unrelated splitter, so the suite can prove the data edit is confined to
  -- Hecate's two clone types.
  Charybdis = { CreateAnimations = { "CharybdisGroundGlow" } },
}

-- Recorders the suite asserts on.
G.created = {}       -- every CreateAnimation call, in order
G.stopped = {}       -- every StopAnimation call, in order
G.events = {}        -- created and stopped interleaved, so order is recoverable
G.outlines = {}      -- current outline per ObjectId, nil when removed
G.outlineHistory = {}
G.threadErrors = {}  -- anything a game thread raised
G.wrapped = {}       -- which globals ModUtil.Path.Wrap replaced

local nextObjectId = 900000
function G.nextId()
  nextObjectId = nextObjectId + 1
  return nextObjectId
end

-- ------------------------------------------------------------- threading ----
-- The game runs these as coroutines and resumes them on its own clock. Here the
-- suite is the clock: thread() starts the body immediately (matching the game,
-- which runs a threaded function up to its first wait), and tick() advances it.

G.threads = {}

function G.thread(fn, ...)
  local args = { ... }
  local co = coroutine.create(function() fn(unpack(args)) end)
  G.threads[#G.threads + 1] = { co = co }
  local ok, err = coroutine.resume(co)
  if not ok then G.threadErrors[#G.threadErrors + 1] = tostring(err) end
  return co
end

function G.wait(seconds)
  coroutine.yield(seconds)
end

-- Resume every suspended thread once per tick. Returns how many were resumed,
-- so a test can assert a watcher has actually retired rather than assuming it.
function G.tick(count)
  local resumed = 0
  for _ = 1, (count or 1) do
    for _, t in ipairs(G.threads) do
      if coroutine.status(t.co) == "suspended" then
        resumed = resumed + 1
        local ok, err = coroutine.resume(t.co)
        if not ok then G.threadErrors[#G.threadErrors + 1] = tostring(err) end
      end
    end
  end
  return resumed
end

function G.liveThreadCount()
  local n = 0
  for _, t in ipairs(G.threads) do
    if coroutine.status(t.co) == "suspended" then n = n + 1 end
  end
  return n
end

-- ------------------------------------------------------------ animations ----

local nextAnimId = 700000
function G.CreateAnimation(args)
  G.created[#G.created + 1] = args
  nextAnimId = nextAnimId + 1
  G.events[#G.events + 1] = { kind = "create", Name = args.Name,
                             DestinationId = args.DestinationId, Scale = args.Scale }
  return nextAnimId
end

-- SetColor records the tint attempt so the suite can assert it was made, without
-- claiming to know whether the engine honours it on a light.
G.colored = {}
function G.SetColor(args)
  G.colored[#G.colored + 1] = args
end

-- StopAnimation names an animation on a destination, not one instance, so it is
-- modelled as clearing EVERY live copy of that name there. That is the same
-- assumption detachMarker makes about stacked lights; if the game turns out to
-- stop only one, this is the line that has to change and the suite will then say
-- so rather than the behaviour quietly differing from the tests.
function G.StopAnimation(args)
  G.stopped[#G.stopped + 1] = args
  G.events[#G.events + 1] = { kind = "stop", Name = args.Name, DestinationId = args.DestinationId }
end

-- How many copies of an animation are currently attached to a unit. Replays the
-- interleaved event stream rather than subtracting totals, because one stop
-- clears any number of creates and a subtraction would get stacking wrong.
function G.attachedCount(name, objectId)
  local n = 0
  for _, e in ipairs(G.events) do
    if e.Name == name and e.DestinationId == objectId then
      if e.kind == "create" then n = n + 1 else n = 0 end
    end
  end
  return n
end

-- Total creations of an animation, ignoring later stops. Distinguishes "never
-- attached" from "attached and then removed", which attachedCount cannot.
function G.createdCount(name, objectId)
  local n = 0
  for _, a in ipairs(G.created) do
    if a.Name == name and (objectId == nil or a.DestinationId == objectId) then n = n + 1 end
  end
  return n
end

-- The marker now uses vanilla's own animation NAME, so a plain name count
-- cannot separate "the glow she spawned with" from "the copies the mod
-- attached". The mod's attach passes Scale and SetupUnit's does not
-- (RoomLogic.lua:3384), so that is the honest discriminator.
function G.markerCount(objectId)
  local n = 0
  for _, e in ipairs(G.events) do
    if e.Name == "HecateGroundGlow" and e.DestinationId == objectId then
      if e.kind == "create" then
        if e.Scale ~= nil then n = n + 1 end
      else
        n = 0
      end
    end
  end
  return n
end

-- Any animation THIS MOD attached and has not stopped, whichever art it is. The
-- mod always passes Scale and SetupUnit's own spawn-time creation never does, so
-- that stays the discriminator. Used by the lifecycle tests, which care that a
-- marker exists rather than which one.
function G.anyMarkerCount(objectId)
  local live = {}
  for _, e in ipairs(G.events) do
    if e.DestinationId == objectId then
      if e.kind == "create" then
        if e.Scale ~= nil then live[e.Name] = (live[e.Name] or 0) + 1 end
      else
        live[e.Name] = 0
      end
    end
  end
  local n = 0
  for _, c in pairs(live) do n = n + c end
  return n
end

function G.AddOutline(args)
  G.outlines[args.Id] = args
  G.outlineHistory[#G.outlineHistory + 1] = { kind = "add", args = args }
end

function G.RemoveOutline(args)
  G.outlines[args.Id] = nil
  G.outlineHistory[#G.outlineHistory + 1] = { kind = "remove", Id = args.Id }
end

-- --------------------------------------------------------------- ModUtil ----

G.ModUtil = {
  Path = {
    Wrap = function(name, wrapper)
      local base = G[name]
      if base == nil then
        error("ModUtil.Path.Wrap called on a global the harness does not define: " .. tostring(name))
      end
      G.wrapped[name] = (G.wrapped[name] or 0) + 1
      G[name] = function(...) return wrapper(base, ...) end
    end,
  },
}

-- -------------------------------------------------------------- UnitSplit ----
-- Mirrors the parts of EnemyAILogic.lua:5139 the plugin depends on: SplitIds is
-- RESET each call (:5152), and each spawned unit's ObjectId is added as a key
-- (:5169). The real one does a great deal more; none of it is observable here.

function G.UnitSplit(enemy, aiData)
  enemy.SplitIds = {}
  for _ = 1, (aiData.SpawnCount or 2) do
    local id = G.nextId()
    enemy.SplitIds[id] = true
    -- Deep-copied from the SHARED EnemyData table, re-read per clone, exactly as
    -- EnemyAILogic.lua:5155-5156 does. That is what makes a load-time data edit
    -- reach every clone of every split rather than only the first.
    local data = (G.EnemyData or {})[aiData.SpawnedUnit] or {}
    local unit = { ObjectId = id, Name = aiData.SpawnedUnit, SetupEvents = {} }
    for _, ev in ipairs(data.SetupEvents or {}) do
      local args = {}
      for k, v in pairs(ev.Args or {}) do args[k] = v end
      unit.SetupEvents[#unit.SetupEvents + 1] = { FunctionName = ev.FunctionName, Args = args }
    end
    G.ActiveEnemies[id] = unit
    -- SetupUnit runs the copied events (RoomLogic.lua:3245-3247).
    for _, ev in ipairs(unit.SetupEvents) do
      if ev.Args ~= nil and ev.Args.Outline ~= nil then
        G.AddOutline({ Id = id,
                       R = ev.Args.Outline.R, G = ev.Args.Outline.G, B = ev.Args.Outline.B })
      end
    end
    G.runCreateAnimations(aiData.SpawnedUnit, id)
  end
end

-- SetupUnit's CreateAnimations loop, reproduced from RoomLogic.lua:3381-3387.
-- Reading the list out of G.EnemyData rather than hardcoding it is what makes a
-- data edit observable: strip the entry and the animation is simply never made.
function G.runCreateAnimations(unitName, objectId)
  -- Guarded: one scenario nils EnemyData entirely to check the plugin survives a
  -- game whose data is not shaped as expected, and the harness must model that
  -- as "no animations", not crash the suite.
  if type(G.EnemyData) ~= "table" then return end
  local data = G.EnemyData[unitName]
  if data == nil or data.CreateAnimations == nil then return end
  for _, animName in ipairs(data.CreateAnimations) do
    G.CreateAnimation({ Name = animName, DestinationId = objectId })
  end
end

-- ---------------------------------------------------------------- helpers ----

-- Spawns a real Hecate into ActiveEnemies and returns her table, the way
-- SetupUnit would (RoomLogic.lua:3241).
function G.spawnHecate()
  local id = G.nextId()
  local hecate = { ObjectId = id, Name = "Hecate" }
  G.ActiveEnemies[id] = hecate
  -- She carries vanilla's ground glow too (EnemyData_Hecate.lua:21). That is the
  -- whole reason a fourth light under her did not read -- and the reason the
  -- plugin must never strip HERS.
  G.runCreateAnimations("Hecate", id)
  return hecate
end

-- Kills every clone recorded on a unit's SplitIds, the way Kill does
-- (CombatLogic.lua:4061) -- which is also the path the phase interlude wipe
-- takes (EnemyAILogic.lua:5696-5699).
function G.killClones(hecate)
  for id in pairs(hecate.SplitIds or {}) do
    G.ActiveEnemies[id] = nil
  end
end

function G.killUnit(unit)
  G.ActiveEnemies[unit.ObjectId] = nil
end

return G
