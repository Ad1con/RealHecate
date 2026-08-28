-- =============================================================================
-- RealHecate (v5.0.0) -- marks the real Hecate during her Triple Divide.
-- =============================================================================
-- When Hecate splits into three, this puts a coloured light on the ground under
-- the real one. The two others are clones. The light appears when she splits and
-- goes away when the clones do, so the rest of the fight is untouched.
--
-- This deliberately removes an ambiguity the fight is built around. It exists as
-- a practice and accessibility tool. The mod's name says what it does, so it
-- ships on rather than behind a switch.
--
-- -----------------------------------------------------------------------------
-- HOW THE REAL ONE IS IDENTIFIED
-- -----------------------------------------------------------------------------
--
-- Every split in the fight goes through one function, UnitSplit
-- (EnemyAILogic.lua:5139). It is called on the real Hecate's own enemy table and
-- spawns N new units:
--
--     enemy.SplitIds = {}                                  -- :5152
--     newEnemy.ObjectId = SpawnUnit({ ... })               -- :5168
--     enemy.SplitIds[newEnemy.ObjectId] = true             -- :5169
--
-- So after any split the real Hecate is the `enemy` the function was called on,
-- her ObjectId is unchanged, and the clones' ObjectIds are exactly the keys of
-- enemy.SplitIds. Nothing has to be inferred from health, behaviour or position.
--
-- Crucially, THE REAL ONE NEVER CHANGES for the whole fight. Checked against
-- every mechanic that could plausibly reassign her:
--
--   * UnitSplit only ever assigns new ObjectIds to newly spawned units. The
--     table it is called on is never re-identified. It does reset SplitIds each
--     time (:5152), so repeat splits start clean rather than accumulating.
--   * Both stage transitions Teleport her by her existing ObjectId
--     (EnemyAILogic.lua:6306 and :6328), so phase changes move her, not swap her.
--   * HecatePolymorph applies to the Hero, not to Hecate (EffectLogic.lua:277-280).
--   * HecateDarkSide only swaps her weapon list (EffectLogic.lua:1191-1199).
--   * The clone wipes at the phase interludes are type-scoped --
--     WipeEnemyTypes = { "HecateCopy", "HecateCopyEM" } (EnemyData_Hecate.lua:327
--     and :374) -- so they can never take the real one.
--
-- That is why this plugin has no re-detection logic and no per-split bookkeeping
-- beyond a generation counter. Mark the unit UnitSplit was called on, and it is
-- still the right unit three splits later.
--
-- -----------------------------------------------------------------------------
-- WHICH SPLITS EXIST
-- -----------------------------------------------------------------------------
--
-- She splits in the ordinary fight as well as in Extreme Measures. All of these
-- funnel into UnitSplit, which is why one wrap covers them:
--
--   Ordinary fight -- HecateSplit1/2/3 (WeaponData_Hecate.lua:1154, 1245, 1259),
--     FireFunctionName = "UnitSplit", SpawnedUnit = "HecateCopy". Equipped in
--     phase 1 (EnemyData_Hecate.lua:268), phase 2 (:362) and phase 3 (:410).
--
--   Extreme Measures -- SpawnHecateClones (PresentationBiomeF.lua:63) as a room
--     function gated to encounter BossHecate02 (RoomDataF.lua:2447), then
--     HecateEMSplit (WeaponData_Hecate.lua:1278) forced on entering phase 2
--     (EnemyData_Hecate.lua:344) and phase 3 (:391). SpawnedUnit = "HecateCopyEM".
--
-- HecateComboBreakerSplit is NOT a split despite the name. It never calls
-- UnitSplit; it teleports clones that already exist (EnemyAILogic.lua:5196-5211).
-- Nothing here needs to handle it.
--
-- The two scope settings below are keyed off aiData.SpawnedUnit rather than off
-- a difficulty check. That is the one fact the wrap can read directly and be
-- sure of, instead of inferring the fight variant from equipped weapon lists.
--
-- -----------------------------------------------------------------------------
-- WHY A GROUND LIGHT RATHER THAN AN OUTLINE
-- -----------------------------------------------------------------------------
--
-- The game already puts a light on the ground under Hecate. Both the real one
-- (EnemyData_Hecate.lua:21) and the clones (:5564) carry
-- CreateAnimations = { "HecateGroundGlow" }, and that animation
-- (Enemy_Erebus_VFX.sjson:2950) is nothing but an invisible sprite whose job is
-- to hold a light:
--
--     Name = "HecateGroundGlow"
--     FilePath = "Dev\blank_invisible"
--     Light = "HecateGroundLight"          -- a Lights\DiffuseSpotlight
--     DieWithOwner = true
--     GroupName = "FX_Terrain"
--
-- This plugin registers its own copy of that pair in a distinct colour and
-- attaches it to the real Hecate. It is the same mechanism the game uses in the
-- same role, so it follows her through every teleport and cleans itself up on
-- her death without any code here.
--
-- The cost is that art is baked in at load: the light's colour and size settings
-- below are RESTART-ONLY.
--
-- -----------------------------------------------------------------------------
-- WHY NOTHING RENDERED UNTIL v1.2.0 -- read this before changing CreateAnimation
-- -----------------------------------------------------------------------------
--
-- v1.0.0 and v1.1.0 both logged complete success and both drew NOTHING. Two
-- playtests, no errors, the right unit identified every time. The cause was one
-- argument:
--
--     CreateAnimation({ Name = ..., DestinationId = ..., Group = "FX_Terrain" })
--
-- "FX_Terrain" was copied out of the animation definition's GroupName field. As a
-- CreateAnimation argument, Group is a RENDER GROUP -- a different namespace --
-- and FX_Terrain is never passed as one anywhere in the game. It appears as a
-- Group only on SpawnObstacle calls (HubPresentation.lua:179, RoomLogic.lua:4879).
-- The light was being filed into a group that does not draw.
--
-- The game's own call for exactly these animations passes NEITHER a Group nor
-- anything else (RoomLogic.lua:3381-3387):
--
--     CreateAnimation({ Name = animName, DestinationId = unit.ObjectId })
--
-- Match that exactly. The general lesson is the one this project keeps charging
-- for: a field name that appears in the data is not automatically a valid
-- argument to the function that consumes the data, and adding a plausible extra
-- argument is a change, not a clarification.
--
-- Note also what failed here: every log line said the plugin was working, because
-- the plugin genuinely did everything it meant to. Success logging proves a call
-- was made, never that the engine honoured it.
--
-- -----------------------------------------------------------------------------
-- MAKING IT READ
-- -----------------------------------------------------------------------------
--
-- Separately from the render bug, the light has to compete. It is not dim in
-- isolation -- it is that ALL THREE OF THEM HAVE ONE. Vanilla gives
-- HecateGroundGlow to the real Hecate (EnemyData_Hecate.lua:21) and to every
-- clone (:5564), so an unmodified extra light is one glow among four.
--
-- Two levers, both of which keep the natural look:
--
--   1. STACKING. Attaching the same glow N times is additive, so N copies read
--      as one light at N times the brightness with identical character. Because
--      that is N CreateAnimation calls rather than baked art, it also makes
--      brightness LIVE -- no restart, unlike Scale and Color.
--
--   2. TAKING THE GLOW OFF THE CLONES, in data at load -- see stripCloneGlowData
--      for why the v1.1.0 runtime version was the wrong shape. Hers becomes the
--      only lit floor on the field. This is contrast by subtraction: nothing
--      artificial is added, and it is arguably the most honest form of this mod,
--      since the game already distinguishes units by ground light and this only
--      makes that distinction exclusive.
--
-- An outline is still available (Outline, default OFF) as a fallback if the light
-- route is not enough. It is the game's own mechanism for marking a unit special
-- -- it is what elites get (CombatPresentation.lua:1223, EnemyAILogic.lua:5183) --
-- and it traces her silhouette rather than the floor, so it does not compete with
-- the arena's lighting at all. It is off by default because it plainly reads as a
-- mod in a way the ground light does not.
--
-- The elite BADGE system was considered and does not fit: it attaches to a
-- floating health bar (CombatPresentation.lua:115-130). Hecate is a boss with a
-- top-of-screen bar and the clones carry HideHealthBar, so there is no anchor.
--
-- Two notes on the outline for whoever tunes it:
--
--   * It needs no sjson, so colour, thickness and opacity are LIVE.
--   * AddOutline takes 0-255 channels, where the light's sjson takes 0-1. Easy
--     to get backwards; colorTo255 exists so it is only written once.
--
-- One known interaction: in a Dream run vanilla outlines the real Hecate red
-- (PresentationBiomeF.lua:33-36). Ours replaces it while the marker is up, and
-- restoreVanillaOutline puts it back on removal rather than leaving her bare.
-- The teal outline vanilla gives EM copies (EnemyData_Hecate.lua:5738-5748) is on
-- the clones and is untouched -- which is fine, since a marker only the real one
-- lacks would be a signal too.
-- =============================================================================

local mods = rom.mods
mods["SGG_Modding-ENVY"].auto()

---@diagnostic disable: lowercase-global
rom = rom
_PLUGIN = _PLUGIN

local modutil = mods["SGG_Modding-ModUtil"]
local reload = mods["SGG_Modding-ReLoad"]

local LOG_PREFIX = "[RealHecate] "

-- Prefix for every animation this plugin registers. StopAnimation names an
-- animation, so the attached marker is removed by whichever name attached it --
-- see detachMarker, which stops every variant rather than guessing which one is
-- live.
local MARKED_FIELD = "RealHecate_Marked"
local GENERATION_FIELD = "RealHecate_Generation"

-- The clone types the two scope settings gate on, straight out of the split
-- weapons' SpawnedUnit fields.
local CLONE_BASE = "HecateCopy"
local CLONE_EM = "HecateCopyEM"

-- How often the watcher rechecks whether any clone is still alive. Clones are
-- removed from ActiveEnemies by Kill (CombatLogic.lua:4061), and the phase
-- interlude wipe threads Kill over the clone types (EnemyAILogic.lua:5696-5699),
-- so this catches both ways they can end. A quarter second costs one walk over
-- at most two ids.
local POLL_INTERVAL = 0.25

-- =============================================================================
-- Logging
-- =============================================================================

-- Deliberately rom.log.info for warnings too. In this ReturnOfModding build
-- rom.log.error RAISES rather than logs, so reporting a handled failure through
-- it turns that failure fatal. Severity is carried in the text instead.
local function logAlways(message)
    if rom and rom.log and rom.log.info then
        rom.log.info(LOG_PREFIX .. tostring(message))
    end
end

local function logWarn(message)
    if rom and rom.log and rom.log.info then
        rom.log.info(LOG_PREFIX .. "WARNING: " .. tostring(message))
    end
end

-- =============================================================================
-- Settings
-- =============================================================================

local CONFIG = {}

-- Colour presets, as 0-1 channels. The comment on each is its perceived
-- brightness under 0.2R + 0.7G + 0.07B -- additive light is only as bright as
-- the channels it adds, so a saturated red reads dim on the ground however
-- strong the number looks.
-- The second number on each line is the CHANNEL GAP: top channel minus middle
-- channel. It predicts how well a colour survives being driven hard, which
-- matters more here than luminance does.
--
-- Additive light clips per channel at 1.0. Once the top TWO channels are both
-- clipped, the light is white no matter what colour was asked for. A colour
-- whose middle channel sits well below its top one therefore keeps its hue at
-- intensities where a balanced colour has already washed out.
--
-- That is exactly what a playtest found: Gold (1.00, 0.78) has a gap of only
-- 0.22, so at five stacked copies both red and green pinned to 1.0 and it read
-- as "mostly white". Amber has a gap of 0.55 and stays orange well past the
-- point where Gold gives up.
CONFIG.colors = {
    Amber   = { 1.00, 0.45, 0.08 }, -- gap 0.55 -- holds hue hottest; torch-like
    Ember   = { 1.00, 0.30, 0.05 }, -- gap 0.70 -- deepest, most orange
    Violet  = { 0.72, 0.22, 1.00 }, -- gap 0.28 (blue over red) -- thematic
    Gold    = { 1.00, 0.78, 0.25 }, -- gap 0.22 -- washes to white when driven
    Teal    = { 0.10, 0.90, 0.75 }, -- gap 0.15 -- washes early, but very bright
    Cyan    = { 0.20, 0.95, 1.00 }, -- gap 0.05 -- effectively white when driven
    Green   = { 0.30, 1.00, 0.35 }, -- gap 0.65
    Magenta = { 1.00, 0.20, 1.00 }, -- gap 0.00 top pair -- pink-white when driven
    Red     = { 1.00, 0.15, 0.10 }, -- gap 0.85 -- never washes, but dim
    White   = { 1.00, 1.00, 1.00 }, -- no hue to lose
}

CONFIG.colorOrder = { "Amber", "Ember", "Violet", "Gold", "Teal",
                      "Cyan", "Green", "Magenta", "Red", "White" }

local settings = {
    values = {
        Enabled = true,
        KeepAfterClonesGone = false,

        -- OFF as of v4.0.0. This is the vanilla HecateGroundLight pool -- the
        -- dark inverted one. It existed because for a long time nothing else
        -- rendered on that painted-cyan floor, and darkening was the only thing
        -- the arena could not wash out.
        --
        -- The Apollo ground sprite made it redundant: that renders in whatever
        -- colour is asked for, so a dark pool underneath a coloured one only
        -- muddies it. A playtest compared the two directly and preferred without.
        --
        -- Invert, Recolour, SteadyColor, Color, Scale and LightStacking all still
        -- apply to THIS light, so turning it back on restores exactly the look
        -- that was tested rather than some untested combination.
        -- Additive: N stacked copies read as one light at N times the brightness,
        -- with the same character. This is the brightness dial, and unlike Color
        -- and Scale it is live. Confirmed working in a playtest once the render
        -- bug was fixed, so raising it is a known-good lever rather than a guess.
        -- Down from 4. With a nearly-flat falloff, each extra copy widens the
        -- apparent pool as well as brightening it.
        -- Multiplies the colour channels before stacking. Together these two set
        -- the peak: LightStacking x Brightness x channel. Above about 2.0 on the
        -- top channel the light starts washing to white -- see CONFIG.colors.

        -- Take vanilla's own ground glow off the two clones, so hers is the only
        -- lit floor. The single biggest readability win available, and it adds
        -- nothing artificial -- see the header.
        -- ON: the clones keep vanilla's own ground glow, as they do unmodded.
        --
        -- This shipped as RemoveCloneGlow = true for most of development, when
        -- stripping the clones was the ONLY thing that made the real Hecate
        -- identifiable -- contrast by absence, because nothing else rendered on
        -- that floor. The red Apollo glow now marks her positively, so taking
        -- effects away from the clones is no longer paying for itself, and
        -- leaving the fight closer to vanilla is worth more.
        --
        -- Named for what it IS rather than what the mod does to it: "on" means
        -- the clones are lit, which is what a reader expects.
        CloneGroundGlow = true,
        -- Take vanilla's glow off the REAL Hecate too, so this mod's light is
        -- the only one under her.
        --
        -- Without this she carries both. Vanilla's runs at scale 1.33 against
        -- this mod's 1.0, so it spreads wider and rings the marker -- and it
        -- ping-pongs teal (0, 1, 0.7) to magenta (1, 0, 1) on a one second loop.
        -- A playtest described exactly that: "blue white on the outside but a
        -- light orangish on the inside". Three earlier rounds of "the colour is
        -- not changing" were the same thing: the colour WAS changing, in a core
        -- that vanilla's larger, colour-cycling pool was drowning.
        --
        -- Note this plugin previously had a test asserting her own glow was
        -- "left alone", treating that as correct. It was the bug.
        -- OFF: vanilla's glow comes off the real Hecate, so the only light under
        -- her is this mod's red one. With it on she carries both, and vanilla's
        -- teal-to-magenta cycle fights the marker's colour.
        HecateVanillaGlow = false,
        -- Dream Dive only. See stripCloneOutlineData: without this, the base
        -- fight's clones carry the SAME red outline the real Hecate does, so the
        -- outline identifies nothing there.
        StripCloneDreamOutline = true,
        -- Ember, not Amber: at the shipped 3 copies Amber reaches (3.00, 1.35,
        -- 0.24) and its middle channel clips, washing to pale yellow-white. Ember
        -- peaks at (3.00, 0.90, 0.15) and holds its colour.
        -- Recolour vanilla's OWN HecateGroundLight entry rather than register
        -- a new animation. See recolourVanillaLight for why that distinction is
        -- the whole story.
        -- Darken instead of brighten.
        --
        -- Additive light can only ADD. Her arena floor is already saturated with
        -- cyan, so an orange light on it produces cyan PLUS orange, which clips
        -- toward white. That is why every colour tried has read as blue-silver,
        -- and why more stacking made it whiter rather than more orange. It is
        -- arithmetic, not a bug, and no colour tuning can beat it.
        --
        -- Inverting sidesteps the fight entirely. DiffuseSpotlightInverse is the
        -- same 360x180 ellipse with its centre at 42 instead of 213 (measured by
        -- extracting Fx.pkg with deppth2), so it darkens the floor under her.
        -- Nothing in the scene can add its way over a subtraction.
        -- ON. Confirmed working in a playtest: a dark navy pool under exactly
        -- one of the three. Note this pairs with Light -- Light controls whether
        -- copies are attached at all, Invert controls whether those copies
        -- darken or brighten, and LightStacking is then how DARK the pool goes.
        -- None, ApolloGlow (vanilla's orange ground glow) or CastCircle (a ring,
        -- which reads by shape rather than colour). See GROUND_FX.
        GroundFx = "ApolloGlow",
        -- Tints the ground sprite. "None" leaves Apollo's own gold-orange.
        -- Everything else is one of the colour presets, passed as CreateAnimation's
        -- Color argument -- which is how vanilla tints sprites.
        GroundFxColor = "Red",
        -- 4.0, not 1.0. ApolloGroundGlow carries Scale = 0.33 in its own
        -- definition, so it starts small; a playtest at 1.0 called the ring
        -- "pretty small". The ceiling is 12 rather than 5 because it is not
        -- established whether CreateAnimation's Scale multiplies the baked value
        -- or replaces it -- if it multiplies, 0.33 x 5 was never going to be
        -- enough, and headroom costs nothing.
        -- 3.0. A playtest at 4.0 called the pool slightly too large. Note the
        -- AxeNovaLight family is baked at scale 3 where ApolloGroundGlow is 0.33,
        -- so the same number lands differently between them.
        GroundFxScale = 3.0,
        -- Hold one colour instead of cycling. Vanilla ping-pongs teal to magenta
        -- every second; a playtest called it "back and forth pretty rapidly".
        -- Both diagnostics that lived here are gone. What DiagnosticVanillaGlow
        -- switched on -- attaching vanilla's own animation -- is now simply how
        -- the mod works, and DiagnosticVanillaColors did its job: it proved the
        -- custom art was at fault rather than the colour values.

        -- 1.6, 2.5, 3.0, 1.8, and now 1.0. The texture is 360x180 px at Scale 1.0
        -- (measured by extracting Fx.pkg with deppth2) and vanilla's own Hecate
        -- light runs 1.33, so 1.0 is a pool about her own footprint. Every larger
        -- value read as area lighting rather than a marker on her.

        -- How far the size breath swings, as a fraction. 0.18 in v1.3.0 was
        -- reported as barely noticeable -- partly because a clipped white pool
        -- hides a size change, partly because 0.18 is simply small.


        -- ON, and the primary marker as of v3.4.0.
        --
        -- This was built in v1.1.0 and left off for ten rounds on the grounds
        -- that it "reads as a mod" while a ground light looks natural. That
        -- judgement cost a great deal: the arena floor is a painted cyan image
        -- (F_Boss02.map_text carries no coloured lights at all, and ambient is a
        -- near-white 0.911/0.954/1.000), so an additive floor light can only ever
        -- wash toward white there. The outline never touches the floor, so none
        -- of that applies to it -- and it worked on the first test.
        Outline = true,
        -- Ember is orange, which is the COMPLEMENT of the arena's cyan. That is
        -- the maximum-contrast choice against this particular floor, and it is
        -- why the outline reads as hard as it does.
        -- Matched to the ground sprite, so the two markers read as one scheme.
        OutlineColor = "Red",
        OutlineThickness = 6,
        OutlineOpacity = 1.0,
    },
    entries = {},
    file = nil,
    persistent = false,
}

local CONFIG_DESCRIPTIONS = {
    Enabled = "Master switch. Off leaves the fight completely vanilla.",
    KeepAfterClonesGone = "Leave the marker on for the rest of the fight instead of removing it when the clones die.",

    GroundFx = "Ground art under the real Hecate: None or ApolloGlow. Colour and size are set separately by GroundFxColor and GroundFxScale. RESTART REQUIRED (or change it from the overlay panel, which needs a mouse).",
    GroundFxColor = "Tint for the ground art. One of: Amber, Ember, Violet, Gold, Teal, Cyan, Green, Magenta, Red or White. Red gives the strongest contrast against this arena's cyan floor; None leaves Apollo's own gold-orange. RESTART REQUIRED (or change it from the overlay panel, which needs a mouse).",
    GroundFxScale = "Size of the ground art. RESTART REQUIRED.",
    StripCloneDreamOutline = "Dream Dive only: take vanilla's outline off the clones, so the real Hecate is the only outlined one. Without it the base fight's clones share her exact red outline. No effect outside Dream runs. RESTART REQUIRED.",
    CloneGroundGlow = "Whether the CLONES keep vanilla's own ground glow. On leaves the fight closer to vanilla; off darkens them so the real Hecate is the only lit one. RESTART REQUIRED (or change it from the overlay panel, which needs a mouse).",
    HecateVanillaGlow = "Whether the real Hecate keeps vanilla's own ground glow, on top of this mod's. Off is recommended: vanilla's cycles teal to magenta and fights the marker's colour. RESTART REQUIRED (or change it from the overlay panel, which needs a mouse).",

    Outline = "Fallback if the ground light still is not enough: draw a coloured outline around the real Hecate. Unmistakable, but it looks like a mod. RESTART REQUIRED (or change it from the overlay panel, which needs a mouse).",
    OutlineColor = "Colour of the outline. One of: Amber, Ember, Violet, Gold, Teal, Cyan, Green, Magenta, Red or White. Matching it to GroundFxColor keeps the two markers reading as one scheme. RESTART REQUIRED (or change it from the overlay panel, which needs a mouse).",
    OutlineThickness = "How heavy the outline is, 1 to 10. The game's own elite outlines are 3. RESTART REQUIRED (or change it from the overlay panel, which needs a mouse).",
    OutlineOpacity = "0 to 1. The game's own elite outlines are 0.8. RESTART REQUIRED (or change it from the overlay panel, which needs a mouse).",
}

local function sectionFor(key)
    -- Only the three that are baked into the animation data at load. `Light` is
    -- not among them: it gates whether the marker is ATTACHED, which is read at
    -- the next split like every other behaviour setting.
    if key == "Color" or key == "Scale" then
        return "Ground light appearance (restart required)"
    end
    if key == "Outline" or key == "OutlineColor"
        or key == "OutlineThickness" or key == "OutlineOpacity" then
        return "Outline (live)"
    end
    return "Behaviour"
end

-- These are the primitives Chalk itself is built on: bind a key with a default,
-- read it with :get(), write it with :set(), flush with :save(). Going straight
-- to them means no second file to import and no dependency on how the plugin
-- folder's name maps back to a path on disk.
local function loadSettings()
    local ok, err = pcall(function()
        if rom.config == nil or rom.config.config_file == nil then
            logWarn("rom.config unavailable; settings will not persist between sessions")
            return
        end
        local configDir = rom.paths and rom.paths.config and rom.paths.config() or nil
        if configDir == nil then
            logWarn("config directory unavailable; settings will not persist between sessions")
            return
        end

        local guid = (_PLUGIN and _PLUGIN.guid) or "Adicon-RealHecate"
        local path = rom.path.combine(configDir, guid .. ".cfg")
        local file = rom.config.config_file:new(path, true)

        for key, default in pairs(settings.values) do
            settings.entries[key] = file:bind(sectionFor(key), key, default, CONFIG_DESCRIPTIONS[key] or "")
        end

        -- Only adopt a stored value whose type matches the default, so a
        -- hand-edited .cfg cannot put a string where a boolean is expected.
        for key, entry in pairs(settings.entries) do
            local stored = entry:get()
            if type(stored) == type(settings.values[key]) then
                settings.values[key] = stored
            end
        end

        settings.file = file
        settings.persistent = true
    end)

    if not ok then
        logWarn("config load failed, using in-memory settings: " .. tostring(err))
    end
end

local function saveSetting(key, value)
    settings.values[key] = value

    local entry = settings.entries[key]
    if entry == nil then return end

    local ok, err = pcall(function()
        entry:set(value)
        if settings.file ~= nil and type(settings.file.save) == "function" then
            settings.file:save()
        end
    end)
    if not ok then
        logWarn("failed to persist " .. tostring(key) .. ": " .. tostring(err))
    end
end

-- A hand-edited .cfg can hold anything. Resolve to a known preset rather than
-- letting a typo produce a nil colour and an invisible marker.
local function resolveColor(chosen, label)
    local rgb = CONFIG.colors[chosen]
    if rgb == nil then
        logWarn("unknown " .. label .. " colour " .. tostring(chosen) .. "; falling back to Amber")
        rgb = CONFIG.colors.Amber
    end
    return rgb
end

-- AddOutline takes 0-255 channels (PresentationBiomeF.lua:36 uses 230/23/0),
-- where the light's sjson takes 0-1. The presets are stored in 0-1, so this is
-- the single place the conversion happens.
local function colorTo255(rgb)
    return math.floor(rgb[1] * 255 + 0.5),
           math.floor(rgb[2] * 255 + 0.5),
           math.floor(rgb[3] * 255 + 0.5)
end

local function clamp(value, low, high, fallback)
    local n = tonumber(value)
    if n == nil then return fallback end
    if n < low then return low end
    if n > high then return high end
    return n
end

-- Everything AddOutline needs, resolved from settings. Read fresh at each split
-- rather than cached, which is what makes the outline dials live.
function CONFIG.resolvedOutline(objectId)
    local r, g, b = colorTo255(resolveColor(settings.values.OutlineColor, "outline"))
    return {
        Id = objectId,
        R = r, G = g, B = b,
        Opacity = clamp(settings.values.OutlineOpacity, 0, 1, 1.0),
        Thickness = clamp(settings.values.OutlineThickness, 1, 10, 5),
        -- Left constant. Every outline in the game uses 0.6 and there is no
        -- vanilla precedent for any other value, so there is nothing to tune
        -- against -- exposing a dial here would be guessing in public.
        Threshold = 0.6,
    }
end

-- Clamped rather than trusted: a zero or negative scale registers a light with
-- no size at all, which looks exactly like the plugin failing to load.
-- True if this split is one the mod should mark.
--
-- The per-fight scope settings are gone. MarkInBaseFight and
-- MarkInExtremeMeasures let the marker be enabled in one fight variant and not
-- the other, which is a real scenario -- practising Extreme Measures unaided in
-- the easier base fight -- but nobody asked for it, and Enabled already covers
-- the case anyone actually has.
--
-- The clone-type check stays. It is not scope, it is a guard: UnitSplit is a
-- general function that other enemies use, and this must ignore a split that is
-- not one of Hecate's two clone types rather than mark whatever was passed.
function CONFIG.marksCloneType(spawnedUnit)
    if not settings.values.Enabled then return false end
    return spawnedUnit == CLONE_EM or spawnedUnit == CLONE_BASE
end

-- =============================================================================
-- No art registration -- and that is the point
-- =============================================================================
-- Versions 1.0.0 through 2.7.0 registered custom animations through sjson and
-- attached those. It never worked, and the failure was narrow and stubborn: the
-- custom light RENDERED but never took its colour, under every condition tried.
-- Red, Ember and Amber; brightness 0.5 and 1.0; vanilla's own exact channel
-- values baked into it; standalone definitions and InheritFrom definitions. All
-- of them produced the same untinted grey-white pool.
--
-- Two playtests bounded it exactly:
--
--   * DiagnosticVanillaGlow attached VANILLA's HecateGroundGlow by name. It
--     rendered, stacked, and cycled teal to magenta correctly.
--   * DiagnosticVanillaColors put vanilla's exact numbers into THIS MOD's own
--     registered animation. Grey-white.
--
-- Same numbers, different result. So the values were never the problem, and no
-- further colour tuning could have found it.
--
-- The rewrite therefore uses no custom art at all. Both mechanisms it does use
-- were confirmed working in a real fight:
--
--   1. Removing HecateGroundGlow from the CLONE types in data, so only the real
--      Hecate is lit. Verified -- the clones went dark.
--   2. Attaching vanilla's own HecateGroundGlow to her and stacking it.
--      Verified -- eight copies were visibly brighter, in colour.
--
-- That is the whole marker. The cost is that the colour is vanilla's teal-to-
-- magenta cycle rather than a free choice, which is the look originally
-- described as "natural, not clearly a mod". Colour is recovered separately, by
-- recolouring vanilla's own light entry rather than registering a new one.

-- =============================================================================
-- The marker
-- =============================================================================

-- Local rather than the game's TableLength (UtilityLogic.lua:5): this is only
-- ever used for a log line, and a log line is not worth a dependency on a game
-- global that the test harness would then have to fake.
local function countKeys(t)
    if t == nil then return 0 end
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    return n
end

-- True while at least one of the ids this split produced is still a live enemy.
-- ActiveEnemies is the right authority for both ways a clone can end: Kill nils
-- the entry (CombatLogic.lua:4061), and the phase interlude wipe threads Kill
-- over the clone types (EnemyAILogic.lua:5696-5699).
local function anyCloneAlive(game, hecate)
    local splitIds = hecate.SplitIds
    if splitIds == nil then return false end
    local active = game.ActiveEnemies
    if active == nil then return false end
    for id in pairs(splitIds) do
        if active[id] ~= nil then return true end
    end
    return false
end

-- Vanilla's own ground glow, given to the real Hecate (EnemyData_Hecate.lua:21)
-- and to every clone (:5564). Removing it from the clones is what makes hers the
-- only lit floor.
local VANILLA_GLOW = "HecateGroundGlow"

-- Ground SPRITES, as opposed to lights. This is the answer to "can the ground be
-- orange": not by tinting a light, but by attaching art that is already orange.
--
-- A light ADDS to the floor, and the floor here is a painted cyan image, so any
-- added colour clips toward white. A sprite is drawn ON the floor and carries its
-- own art, so it reads on its own terms. ApolloGroundGlow is literally defined as
-- Red = 1, Green = 0.6, Blue = 0.
--
-- CastCircle is the stronger option and the reason is worth stating: it is a
-- RING, so it reads by SHAPE. Shape survives a busy, saturated floor in a way no
-- colour does -- and this arena defeated colour for ten rounds.
-- Ground sprites, and only ones that LOOP.
--
-- v3.7.0 offered the AxeNovaLight_<God> family as a colour palette. That was a
-- mistake caught by a playtest: those are axe NOVA bursts -- Duration = 1 with no
-- Loop -- so the marker appeared for a second at the start of the fight and never
-- again. Colour was the wrong thing to select art by; persistence comes first.
--
-- ApolloGroundGlow is the one confirmed working, and the reason is right there in
-- its definition: Loop = true, NumFrames = 15, PlaySpeed = 30. It runs forever.
--
-- Colour therefore does NOT come from picking different art any more. It comes
-- from the Color argument on CreateAnimation, which vanilla passes for SPRITES in
-- seven places (EventLogic.lua:1676, SpellPresentation.lua:465, 496, 507, 510,
-- RoomPresentation.lua:2410, UpgradeChoiceLogic.lua:999) as {R, G, B, A} in
-- 0-255. That is a documented runtime path for sprites, unlike the light tinting
-- that failed -- lights and sprites are not the same thing here, and conflating
-- them cost several rounds.
local GROUND_FX = {
    None       = nil,
    -- Loop = true, 15 frames. The one confirmed working in a real fight.
    ApolloGlow = "ApolloGroundGlow",
}
-- Two entries, so this is effectively on/off. It stays a named list rather than a
-- boolean because the thing being chosen is WHICH ART, and a second shape may
-- earn its place later -- but only after being seen in a fight.
--
-- ApolloAoECircleA (a cast ring) was offered here and removed unused. It looked
-- like a shape-based alternative, but reading its definition it is not a clean
-- equivalent: PingPongColor = true gives it a colour cycle of its own that would
-- fight GroundFxColor, StartAlpha fades 0.6 to 0.3, and VisualFx spawns a further
-- effect every ~0.2s for as long as it lives. It is an AoE telegraph, not a
-- marker. Shipping it untested would have repeated the AxeNovaLight mistake --
-- art chosen by reading one property and ignoring the rest.
local GROUND_FX_ORDER = { "None", "ApolloGlow" }

-- unit.CreateAnimations is consumed engine-side at spawn -- no Lua reads it, so
-- there is no hook point and no way to stop the clones' glow from being made in
-- the first place. It has to be created and then stopped. SpawnUnit has returned
-- by the time this runs (EnemyAILogic.lua:5168), so the glow should already
-- exist; the small wait is insurance against the engine finishing setup a frame
-- later, since stopping an animation that does not exist yet is a silent no-op.
-- Take vanilla's ground glow off the clone types in DATA, once, at load.
--
-- v1.1.0 did this at runtime instead -- StopAnimation on each clone id a tenth of
-- a second after the split -- and it did not work. The data edit is strictly
-- better and it is worth being clear about why, because the runtime version
-- looked perfectly reasonable:
--
--   * SetupUnit creates these from unit.CreateAnimations (RoomLogic.lua:3381-3387)
--     and SetupUnit is THREADED for each clone (EnemyAILogic.lua:5171). A fixed
--     0.1s wait is a guess about when that thread gets far enough, and a guess is
--     exactly what this project keeps paying for.
--   * Removing the entry means the glow is never created at all, so there is no
--     ordering question left to get wrong.
--   * UnitSplit builds each clone with DeepCopyTable(EnemyData[aiData.SpawnedUnit])
--     (EnemyAILogic.lua:5155), so an edit here reaches every clone of every split
--     for the rest of the session.
--
-- The cost is that this setting becomes restart-required, which the config text
-- now says. Blast radius is small and checked: CreateAnimations on these two
-- types is read only by the loop above, and the only entry removed is the ground
-- glow -- the torch flames on HecateCopy (EnemyData_Hecate.lua:5565-5567) are
-- left alone, so the clones still look like Hecate.
-- Which unit types lose vanilla's ground glow in data.
--
-- Both settings are named for the STATE they describe rather than the action the
-- mod takes, so both are inverted here: a unit is stripped when its glow is
-- switched OFF. That reads better in the config than RemoveCloneGlow did, where
-- "true" meant the clones were dark.
local function glowStripTargets()
    local targets = {}
    if not settings.values.CloneGroundGlow then
        targets[#targets + 1] = CLONE_BASE
        targets[#targets + 1] = CLONE_EM
    end
    if not settings.values.HecateVanillaGlow then
        targets[#targets + 1] = "Hecate"
    end
    return targets
end

-- Take vanilla's Dream-run outline off the CLONES, so that in Dream Dive the
-- real Hecate is the only outlined unit.
--
-- This matters more than it looks. There are four outline SetupEvents in
-- EnemyData_Hecate.lua and they are not all the same colour:
--
--   :175  Hecate       teal  (25,200,160)   -- HERS. Never touched.
--   :5632 HecateCopy   RED   (230,23,0)     -- identical to her own red
--   :5745 HecateCopyEM teal  (25,200,160)   -- opening split only
--   :5771 HecateCopyEM RED   (230,23,0)     -- phase splits
--
-- In a Dream Dive base fight the clones carry the SAME red the real Hecate gets
-- from HecateBattleStart (PresentationBiomeF.lua:36), so all three look alike and
-- an outline tells you nothing at all.
--
-- Every one of the four is gated PathTrue = { CurrentRun, IsDreamRun }, so
-- outside a Dream run these events never fire and this edit is a no-op. It
-- cannot affect a normal fight.
--
-- Surgical on purpose: only Outline and AddOutlineImmediately are removed.
-- GrannyTexture stays, because those same events are what give the clones their
-- Dream appearance -- taking the whole event would leave them wrongly textured.
--
-- Once stripped, vanilla's own red outline on the real Hecate becomes a free
-- marker in Dream mode, with no colour choice needed: the signal is outlined
-- versus not outlined, exactly like the ground glow.
local function stripCloneOutlineData(game)
    local enemyData = game.EnemyData
    if type(enemyData) ~= "table" then return 0 end

    local removed = 0
    for _, unitName in ipairs({ CLONE_BASE, CLONE_EM }) do
        local data = enemyData[unitName]
        local events = data ~= nil and data.SetupEvents or nil
        if type(events) == "table" then
            for _, ev in ipairs(events) do
                if type(ev) == "table" and type(ev.Args) == "table"
                    and ev.Args.Outline ~= nil then
                    ev.Args.Outline = nil
                    ev.Args.AddOutlineImmediately = nil
                    removed = removed + 1
                end
            end
        end
    end
    return removed
end

local function stripCloneGlowData(game)
    local enemyData = game.EnemyData
    if type(enemyData) ~= "table" then
        logWarn("EnemyData unavailable; the clones keep their ground glow")
        return 0
    end

    local removed = 0
    for _, unitName in ipairs(glowStripTargets()) do
        local data = enemyData[unitName]
        local anims = data ~= nil and data.CreateAnimations or nil
        if type(anims) == "table" then
            -- Backwards, so removing does not shift an index still to be read.
            for i = #anims, 1, -1 do
                if anims[i] == VANILLA_GLOW then
                    table.remove(anims, i)
                    removed = removed + 1
                end
            end
        end
    end

    -- HecateCopyEM inherits from HecateCopy (EnemyData_Hecate.lua:5681), so the
    -- two may resolve to one shared table. Then the first pass empties it for
    -- both and the second finds nothing -- which is correct, not a failure. The
    -- count is logged rather than asserted on for exactly that reason.
    return removed
end

-- The ground sprite's tint as {R, G, B, A} in 0-255, or nil to leave the art its
-- own colour. Vanilla passes Color to CreateAnimation for sprites in
-- seven places, and never for a light.
function CONFIG.resolvedGroundColor()
    local name = settings.values.GroundFxColor
    if name == nil or name == "None" then return nil end
    local rgb = CONFIG.colors[name]
    if rgb == nil then
        logWarn("unknown ground colour " .. tostring(name) .. "; leaving the art untinted")
        return nil
    end
    local r, g, b = colorTo255(rgb)
    return { r, g, b, 255 }
end


local function attachMarker(game, hecate)
    local groundFx = GROUND_FX[settings.values.GroundFx]
    if groundFx ~= nil then
        -- A sprite, not a light. Vanilla passes Scale on 113 CreateAnimation
        -- calls, so that argument is precedented; nothing else is added.
        -- Color is {R, G, B, A} in 0-255 (ColorData.lua), NOT the 0-1 the
        -- animation data uses. Two different scales for the same idea, and
        -- getting it backwards yields a black tint that looks like nothing.
        local args = {
            Name = groundFx,
            DestinationId = hecate.ObjectId,
            Scale = clamp(settings.values.GroundFxScale, 0.1, 12.0, 3.0),
        }
        local tint = CONFIG.resolvedGroundColor()
        if tint ~= nil then args.Color = tint end
        game.CreateAnimation(args)
    end

    if settings.values.Outline then
        game.AddOutline(CONFIG.resolvedOutline(hecate.ObjectId))
    end

    hecate[MARKED_FIELD] = true
end

-- In a Dream run vanilla put a red outline on her (PresentationBiomeF.lua:33-36)
-- and ours replaced it. Put it back rather than leaving her the only unoutlined
-- unit in a mode where everything is outlined.
local function restoreVanillaOutline(game, hecate)
    local run = game.CurrentRun
    if run == nil or not run.IsDreamRun then return end
    game.AddOutline({
        Id = hecate.ObjectId,
        R = 230, G = 23, B = 0,
        Opacity = 0.8, Thickness = 3, Threshold = 0.6,
    })
end

-- IncludeCreatedAnimations, matching how vanilla stops an attached FX it created
-- the same way (EnemyAILogic.lua:6303). The light goes with the glow because the
-- light entry carries DieWithOwner.
--
-- One StopAnimation for however many copies were stacked: the call names an
-- animation on a destination rather than one instance, so it is expected to take
-- all of them. If a stacked marker ever half-disappears in game, this assumption
-- is the first place to look.
local function detachMarker(game, hecate)
    if not hecate[MARKED_FIELD] then return end

    -- One name, because there is only one animation now. This also takes her own
    -- base glow if HecateVanillaGlow is on, which is why that setting defaults
    -- on: with it on she has no base glow and the marker is unambiguous.
    game.StopAnimation({
        Name = VANILLA_GLOW,
        DestinationId = hecate.ObjectId,
        IncludeCreatedAnimations = true,
    })

    -- Every ground sprite this mod can attach, not just the one currently
    -- selected: the setting is live, so it can change between the split that
    -- attached one and the moment the clones die.
    for _, name in pairs(GROUND_FX) do
        game.StopAnimation({
            Name = name,
            DestinationId = hecate.ObjectId,
            IncludeCreatedAnimations = true,
        })
    end

    if settings.values.Outline then
        game.RemoveOutline({ Id = hecate.ObjectId })
        restoreVanillaOutline(game, hecate)
    end

    hecate[MARKED_FIELD] = false
end

-- Runs as a game thread. Ends when the clones are gone, when Hecate herself is
-- gone, or when a newer split has superseded this watcher.
--
-- There is one hazard here worth naming, because she splits again at every phase
-- change: a watcher from the PREVIOUS split is still running when the next one
-- starts, and if it were still judging by the previous split's clones -- all of
-- them dead by then -- it would clear the marker the new split had just applied.
--
-- Two independent things prevent that, and either alone is sufficient:
--
--   1. anyCloneAlive reads hecate.SplitIds LIVE, not a copy taken when this
--      watcher started. The marker belongs to Hecate, not to one split, so "are
--      any of her current clones alive" stays the right question across a
--      re-split. A watcher holding a snapshot would ask the wrong one.
--   2. The generation guard below retires a superseded watcher on its next tick.
--
-- Belt and braces, deliberately: the suite confirms that sabotaging BOTH breaks
-- the re-split (6.2, 6.3) while sabotaging either alone does not. 6.5 pins the
-- generation guard's own narrower benefit -- a three-phase fight ends with one
-- watcher rather than three redundant ones polling the same two ids.
local function watchClones(game, hecate, generation)
    while true do
        if hecate[GENERATION_FIELD] ~= generation then return end
        if game.ActiveEnemies == nil or game.ActiveEnemies[hecate.ObjectId] == nil then
            -- She is dead or the room is gone. DieWithOwner has already taken
            -- the light; there is nothing left to detach.
            hecate[MARKED_FIELD] = false
            return
        end
        if not anyCloneAlive(game, hecate) then
            detachMarker(game, hecate)
            return
        end
        game.wait(POLL_INTERVAL)
    end
end

-- Called after UnitSplit has returned, so SplitIds is fully populated. UnitSplit
-- contains no waits, so a post-wrap sees the finished state rather than a
-- half-filled table.
local function markRealHecate(game, hecate, aiData)
    if hecate == nil or hecate.ObjectId == nil then return end
    if hecate.Name ~= "Hecate" then return end

    local spawnedUnit = aiData ~= nil and aiData.SpawnedUnit or nil
    if not CONFIG.marksCloneType(spawnedUnit) then return end

    -- Bump first. Any watcher from a previous split sees the change on its next
    -- tick and retires without touching the marker this split is about to make.
    local generation = (hecate[GENERATION_FIELD] or 0) + 1
    hecate[GENERATION_FIELD] = generation

    -- Re-attaching over a live marker would stack two lights and make the real
    -- one brighter each phase. The first split's marker is still correct.
    if not hecate[MARKED_FIELD] then
        attachMarker(game, hecate)
    end

    -- No clone-glow work here any more. It is done once in data at load, so by
    -- the time a clone spawns it simply has no ground glow to remove.
    logAlways(("marked the real Hecate (id %s) against %d %s clone(s); ground %s/%s, outline %s")
        :format(tostring(hecate.ObjectId), countKeys(hecate.SplitIds), tostring(spawnedUnit),
                tostring(settings.values.GroundFx), tostring(settings.values.GroundFxColor),
                settings.values.Outline and "on" or "off"))

    if settings.values.KeepAfterClonesGone then return end
    game.thread(watchClones, game, hecate, generation)
end

-- =============================================================================
-- Overlay panel
-- =============================================================================
-- Added in v2.2.0 after a playtest went looking for RealHecate in the modding
-- overlay and did not find it. Settings were file-only, which is a gap in this
-- plugin rather than a limit of the platform: Chalk generates the .cfg and draws
-- no GUI at all, and the overlay panel is separate rom.gui/ImGui code.
--
-- Hot reload and an overlay panel coexist fine -- seven mods installed on this
-- machine do both (DamageMeter, ModpackLib, the adamantSpeedrun set) -- so this
-- costs nothing that was already working.
--
-- Everything here writes through saveSetting, so a change lands in the .cfg AND
-- in settings.values immediately. Colour, brightness, scale, texture and
-- stacking are read at attach time, so they take effect at the very next split
-- with no restart and no file editing.
--
-- Three rules this follows, all of them things this platform punishes:
--   * Every ImGui widget label carries a ##unique suffix. Widgets are keyed by
--     label string, so two sliders sharing a label are ONE widget and each will
--     move the other.
--   * End is unconditional after Begin; EndCombo and EndMenu only when their
--     Begin returned true. Mispairing leaks a window and corrupts the overlay
--     for every other mod, not just this one.
--   * The whole body is wrapped in pcall. A failure here must not take the
--     overlay, or the game, down with it.

-- Everything in the .cfg is restart-only in practice. The plugin reads settings
-- at load and on hot reload, and a hot reload fires on a plugin FILE change, not
-- a .cfg change -- and the game rewrites the .cfg from its own memory on exit, so
-- an edit made while it is running is discarded anyway. Only this panel writes
-- through immediately, and it needs a mouse, which rules it out on a controller.
local RESTART_ONLY = " (restart)"

local function comboSetting(imgui, key, options, label)
    local current = tostring(settings.values[key])
    if imgui.BeginCombo(label .. "##RealHecate_" .. key, current) then
        for _, name in ipairs(options) do
            if imgui.Selectable(name .. "##RealHecate_" .. key .. "_" .. name) then
                saveSetting(key, name)
            end
        end
        imgui.EndCombo()
    end
end

local function checkSetting(imgui, key, label)
    local value, changed = imgui.Checkbox(label .. "##RealHecate_" .. key,
                                          settings.values[key] == true)
    if changed then saveSetting(key, value) end
end

local function sliderSetting(imgui, key, label, low, high, fmt)
    local value, changed = imgui.SliderFloat(label .. "##RealHecate_" .. key,
                                            tonumber(settings.values[key]) or low,
                                            low, high, fmt or "%.2f")
    if changed then saveSetting(key, value) end
end

local function renderWindow()
    local imgui = rom.ImGui
    if imgui == nil then return end

    local cond = rom.ImGuiCond and rom.ImGuiCond.FirstUseEver or nil
    if cond ~= nil and type(imgui.SetNextWindowSize) == "function" then
        imgui.SetNextWindowSize(430, 500, cond)
    end

    -- Begin is OUTSIDE the pcall and End follows it unconditionally, with only
    -- the body guarded. The obvious arrangement -- wrapping the whole function
    -- in one pcall -- is wrong, and wrong in a way that is invisible until it
    -- fires: a raise anywhere in the body then skips End, ImGui is left with an
    -- unclosed window, and the overlay is corrupted for EVERY mod, not just this
    -- one. Test 10c.7 caught exactly that in the first draft of this function.
    local shouldDraw = imgui.Begin("RealHecate")

    local ok, err = pcall(function()
        if shouldDraw then
            imgui.Text("Marks the real Hecate when she splits into three.")
            imgui.TextDisabled("Applies at the next split, no restart,")
            imgui.TextDisabled("unless a line says otherwise.")
            imgui.Separator()

            checkSetting(imgui, "Enabled", "Enabled")
            checkSetting(imgui, "KeepAfterClonesGone", "Keep marker after clones die")
            imgui.Spacing()
            imgui.Separator()

            imgui.Text("Ground marker")
            comboSetting(imgui, "GroundFx", GROUND_FX_ORDER, "Ground art")
            comboSetting(imgui, "GroundFxColor", CONFIG.colorOrder, "Ground colour")
            sliderSetting(imgui, "GroundFxScale", "Ground size", 0.1, 12.0)

            imgui.Spacing()
            imgui.Separator()
            imgui.Text("Outline")
            checkSetting(imgui, "Outline", "Outline the real Hecate")
            comboSetting(imgui, "OutlineColor", CONFIG.colorOrder, "Outline colour")
            sliderSetting(imgui, "OutlineThickness", "Thickness", 1, 10, "%.0f")
            sliderSetting(imgui, "OutlineOpacity", "Opacity", 0.0, 1.0)

            imgui.Spacing()
            imgui.Separator()
            imgui.Text("Clones")
            checkSetting(imgui, "CloneGroundGlow", "Clones keep their glow" .. RESTART_ONLY)
            checkSetting(imgui, "HecateVanillaGlow", "She keeps her vanilla glow" .. RESTART_ONLY)
            checkSetting(imgui, "StripCloneDreamOutline", "Strip clone Dream outline" .. RESTART_ONLY)

            imgui.Spacing()
            imgui.Separator()

            if not settings.persistent then
                imgui.Spacing()
                imgui.TextDisabled("settings are NOT being saved to disk")
            end
        end
    end)

    -- Unconditional, and after the pcall, whatever happened above.
    imgui.End()

    if not ok then
        logWarn("overlay panel failed this frame: " .. tostring(err))
    end
end

local function renderMenuBar()
    pcall(function()
        local imgui = rom.ImGui
        if imgui == nil then return end
        -- EndMenu only when BeginMenu returned true.
        if imgui.BeginMenu("RealHecate") then
            if imgui.MenuItem("Marker enabled##RealHecate_menu_enabled") then
                saveSetting("Enabled", not settings.values.Enabled)
            end
            imgui.EndMenu()
        end
    end)
end

local function installGui()
    if rom.gui == nil then
        logWarn("rom.gui unavailable; no overlay panel (the .cfg still works)")
        return false
    end
    local ok, err = pcall(function()
        if type(rom.gui.add_imgui) == "function" then
            rom.gui.add_imgui(renderWindow)
        end
        if type(rom.gui.add_to_menu_bar) == "function" then
            rom.gui.add_to_menu_bar(renderMenuBar)
        end
    end)
    if not ok then
        logWarn("overlay panel registration failed: " .. tostring(err))
        return false
    end
    return true
end

-- =============================================================================
-- Install
-- =============================================================================

local function installHooks(game)
    local ModUtil = game.ModUtil
    if ModUtil == nil or ModUtil.Path == nil or ModUtil.Path.Wrap == nil then
        logWarn("ModUtil.Path.Wrap unavailable; hooks not installed")
        return false
    end

    -- One wrap covers every split in the fight, in both difficulties, because
    -- all of them route through this function -- see the header. UnitSplit
    -- returns nothing in vanilla and no caller reads a return value, so this
    -- returns nothing either.
    ModUtil.Path.Wrap("UnitSplit", function(base, enemy, aiData)
        base(enemy, aiData)

        -- A failure in the marker must not take a boss split down with it.
        -- Vanilla has already produced a working, playable split by this point;
        -- falling through leaves the fight intact and merely unmarked.
        local ok, err = pcall(markRealHecate, game, enemy, aiData)
        if not ok then
            logWarn("could not mark the real Hecate, leaving the split unmarked: " .. tostring(err))
        end
    end)

    return true
end

-- =============================================================================
-- Boot
-- =============================================================================

loadSettings()

-- Runs ONCE. Anything here that ran twice would double up: a second
-- ModUtil.Path.Wrap would nest another wrapper around UnitSplit, and a second
-- data strip would walk lists the first pass already emptied.
local function on_ready(game)
    local stripped = 0
    local outlinesStripped = 0
    if settings.values.Enabled and settings.values.StripCloneDreamOutline then
        local okO, resultO = pcall(stripCloneOutlineData, game)
        if okO then
            outlinesStripped = resultO
        else
            logWarn("could not strip the clones' Dream outline: " .. tostring(resultO))
        end
    end

    if settings.values.Enabled
        and (not settings.values.CloneGroundGlow or not settings.values.HecateVanillaGlow) then
        local ok, result = pcall(stripCloneGlowData, game)
        if ok then
            stripped = result
        else
            logWarn("could not strip the clones' ground glow in data: " .. tostring(result))
        end
    end

    local guiOk = installGui()

    if installHooks(game) then
        logAlways(("installed; overlay panel %s; marker is %s; "
                   .. "clone glow entries removed: %d, clone Dream outlines removed: %d%s")
            :format(guiOk and "registered" or "unavailable",
                    settings.values.Enabled and "on" or "off",
                    stripped,
                    outlinesStripped,
                    settings.persistent and "" or " (settings not persisted)"))
    end
end

-- Runs on load AND on every hot reload, so it must be safe to repeat. Only
-- re-reads settings and reports them; it installs nothing.
--
-- This is what makes tuning cheap. Colour, brightness, scale and stacking are
-- all resolved at attach time from these values, so editing the .cfg and saving
-- lands on the very next split with no restart. Pulse shape is the exception --
-- PingPongScale and Duration are baked into the art at load.
local function on_reload()
    loadSettings()
    logAlways(("settings reloaded; ground %s/%s at scale %.2f, clone glow %s, outline %s")
        :format(tostring(settings.values.GroundFx), tostring(settings.values.GroundFxColor),
                clamp(settings.values.GroundFxScale, 0.1, 12.0, 3.0),
                settings.values.CloneGroundGlow and "left" or "stripped",
                settings.values.Outline and "on" or "off"))
end

if reload ~= nil and type(reload.auto_single) == "function" then
    local loader = reload.auto_single()
    modutil.once_loaded.game(function()
        local ok, err = pcall(function()
            local game = rom.game
            if game == nil then
                logWarn("rom.game is nil; not installing")
                return
            end
            loader.load(function() on_ready(game) end, on_reload)
        end)
        if not ok then
            logWarn("install failed, plugin inactive: " .. tostring(err))
        end
    end)
else
    -- ReLoad is a declared dependency, but a profile can be missing it. Falling
    -- back costs hot reload and nothing else.
    logWarn("SGG_Modding-ReLoad unavailable; installing without hot reload")
    modutil.once_loaded.game(function()
        local ok, err = pcall(function()
            local game = rom.game
            if game == nil then
                logWarn("rom.game is nil; not installing")
                return
            end
            on_ready(game)
        end)
        if not ok then
            logWarn("install failed, plugin inactive: " .. tostring(err))
        end
    end)
end

-- Exposed for the test suite only. The game ignores the return value of a plugin
-- chunk, so this costs nothing at runtime.
return {
    CONFIG = CONFIG,
    settings = settings,
    saveSetting = saveSetting,
    POLL_INTERVAL = POLL_INTERVAL,
    GROUND_FX = GROUND_FX,
    GROUND_FX_ORDER = GROUND_FX_ORDER,
}
