-- Mock ReturnOfModding surface: rom.log, rom.config, rom.mods, rom.paths.
-- Records what the plugin did so the suite can assert on it.
local M = { logs = {}, saves = 0 }

-- ------------------------------------------------------------ rom.config ----
-- Mirrors the primitives Chalk is built on: config_file:new(path, true),
-- :bind(section, key, default, description) -> entry, entry:get()/:set(),
-- and config_file:save().
local function makeConfig(initial, opts)
  opts = opts or {}
  local store = {}
  for k, v in pairs(initial or {}) do store[k] = v end
  M.store = store

  local file
  file = {
    bind = function(_, section, key, default, description)
      M.bound = M.bound or {}
      M.bound[key] = { section = section, default = default, description = description }
      if store[key] == nil then store[key] = default end
      return {
        get = function() return store[key] end,
        set = function(_, v) store[key] = v end,
      }
    end,
    save = function() M.saves = M.saves + 1 end,
  }

  return {
    config_file = {
      new = function(_, path, save)
        if opts.throw then error("simulated config_file failure") end
        M.configPath = path
        return file
      end,
    },
  }
end

-- ---------------------------------------------------------------- ImGui ----
-- Records every label drawn, and tracks Begin/End nesting depth so the suite can
-- prove the pairing contract holds. `script` drives interaction: which combo
-- opens, which item is clicked, which checkbox toggles, whether the body raises.
function M.makeImGui(script)
  script = script or {}
  local depth = { window = 0, combo = 0, menu = 0 }
  M.depth = depth
  M.labels = {}
  local function rec(l) M.labels[#M.labels + 1] = l end

  return {
    Begin = function(l)
      rec("Begin:" .. tostring(l)); depth.window = depth.window + 1
      return script.collapsed ~= true
    end,
    End = function() depth.window = depth.window - 1 end,
    BeginCombo = function(l)
      rec(l)
      if script.openCombo then depth.combo = depth.combo + 1 end
      return script.openCombo == true
    end,
    EndCombo = function() depth.combo = depth.combo - 1 end,
    Selectable = function(l)
      rec(l)
      return script.click ~= nil and tostring(l):find(script.click, 1, true) ~= nil
    end,
    Checkbox = function(l, v)
      rec(l)
      if script.toggle ~= nil and tostring(l):find(script.toggle, 1, true) then
        return not v, true
      end
      return v, false
    end,
    SliderFloat = function(l, v, lo, hi, fmt)
      rec(l)
      if script.slide ~= nil and tostring(l):find(script.slide, 1, true) then
        return script.slideTo, true
      end
      return v, false
    end,
    BeginMenu = function(l)
      rec(l)
      if script.openMenu then depth.menu = depth.menu + 1 end
      return script.openMenu == true
    end,
    EndMenu = function() depth.menu = depth.menu - 1 end,
    MenuItem = function(l)
      rec(l)
      return script.clickMenuItem ~= nil and tostring(l):find(script.clickMenuItem, 1, true) ~= nil
    end,
    Text = function(t)
      rec("Text:" .. tostring(t))
      -- Raises AFTER Begin has pushed a window, which is the case that actually
      -- risks a leaked window if End is skipped.
      if script.errorInBody then error("simulated ImGui failure inside the body") end
    end,
    TextDisabled = function(t) rec("TextDisabled:" .. tostring(t)) end,
    Separator = function() end,
    Spacing = function() end,
    SameLine = function() end,
    SetNextWindowSize = function() end,
  }
end

function M.install(game, configOpts, configInitial, sjsonOpts, modutilOpts, guiScript)
  M.logs = {}
  M.saves = 0
  M.bound = nil
  M.store = nil
  M.configPath = nil
  M.hookedFile = nil
  M.animations = nil
  M.hookedFiles = nil
  M.lastOrder = nil
  M.pendingGameLoad = nil
  M.onReady = nil
  M.onReload = nil
  M.guiCallbacks = {}
  M.labels = {}
  M.depth = nil

  rom = {
    game = game,
    log = {
      info = function(m) M.logs[#M.logs + 1] = m end,
      -- Faithful to the real binding: rom.log.error RAISES. Any use of it from
      -- the main chunk kills the module load. Encoded here so the mistake
      -- cannot come back unnoticed.
      error = function(m) error(m, 2) end,
      warning = function(m) M.logs[#M.logs + 1] = "WARN " .. m end,
    },
    ImGuiCond = { FirstUseEver = 4 },
    ImGui = M.makeImGui(guiScript),
    gui = {
      add_imgui       = function(fn) M.guiCallbacks.window = fn end,
      add_to_menu_bar = function(fn) M.guiCallbacks.menuBar = fn end,
    },
    path = { combine = function(a, b) return a .. "\\" .. b end },
    paths = { config = function() return "C:\\fake\\config" end, Content = "C:\\fake\\Content" },
    mods = {
      ["SGG_Modding-ENVY"] = { auto = function() end },
      ["SGG_Modding-ModUtil"] = {
        once_loaded = { game = function(cb) M.pendingGameLoad = cb end },
      },
      -- ReLoad's auto_single().load(on_ready, on_reload) calls both on first
      -- load; a hot reload later calls on_reload again. Recorded so the suite
      -- can drive a reload without a game.
      ["SGG_Modding-ReLoad"] = {
        auto_single = function()
          return {
            load = function(on_ready, on_reload)
              M.onReady, M.onReload = on_ready, on_reload
              on_ready()
              on_reload()
            end,
          }
        end,
      },
    },
  }

  if modutilOpts and modutilOpts.noGui then
    rom.gui = nil
  end

  if modutilOpts and modutilOpts.noReload then
    rom.mods["SGG_Modding-ReLoad"] = nil
  end

  if modutilOpts and modutilOpts.absent then
    rom.mods["SGG_Modding-ModUtil"] = { once_loaded = { game = function(cb) M.pendingGameLoad = cb end } }
  end

  -- A real branch, not an `a and b and nil or c` chain: that always yields c in
  -- Lua and would silently install a working backend for the "absent" scenario.
  if not (configOpts and configOpts.absent) then
    rom.config = makeConfig(configInitial, configOpts)
  end

  if not (sjsonOpts and sjsonOpts.absent) then
    rom.mods["SGG_Modding-SJSON"] = {
      -- The real to_object serializes ONLY the fields named in `order`.
      -- Reproduced faithfully: a field the plugin sets but forgets to list must
      -- disappear here too, or the suite would pass on art the game drops.
      to_object = function(tbl, order)
        M.lastOrder = order
        local out = {}
        for _, key in ipairs(order or {}) do
          if tbl[key] ~= nil then out[key] = tbl[key] end
        end
        return out
      end,
      hook = function(path, fn)
        if sjsonOpts and sjsonOpts.throw then error("simulated sjson.hook failure") end
        M.hookedFiles = M.hookedFiles or {}
        M.hookedFiles[#M.hookedFiles + 1] = path
        M.hookedFile = path
        -- Seeded with the real vanilla entries from Enemy_Erebus_VFX.sjson:2950
        -- and :2958. The plugin edits an EXISTING entry now rather than adding
        -- one, so an empty list would make the test vacuous.
        M.animations = M.animations or { Animations = {
          { Name = "HecateGroundGlow", FilePath = [[Dev\blank_invisible]],
            Light = "HecateGroundLight", DieWithOwner = true, GroupName = "FX_Terrain" },
          { Name = "HecateGroundLight", FilePath = [[Lights\DiffuseSpotlight]],
            StartRed = 0.0, StartGreen = 1, StartBlue = 0.7,
            EndRed = 1, EndGreen = 0, EndBlue = 1,
            PingPongColor = true, Loop = true, Duration = 1,
            StartScale = 1.33, EndScale = 1,
            Material = "Unlit", DieWithOwner = true, GroupName = "FX_Terrain" },
        } }
        fn(M.animations)
      end,
    }
  end

  _PLUGIN = { guid = "Adicon-RealHecate" }
end

return M
