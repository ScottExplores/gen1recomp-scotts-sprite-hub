-- Scott's Sprite Menu: a UI/controller adapter only.  No provider art or
-- provider implementation is copied into this package.

return function(mod)
  -- Keep the preference on this adapter rather than on any art provider.
  -- The Mod Manager supplies the durable default and a fallback place to
  -- change it; the compact SPRITES screen below writes the same option.
  mod.options:define({
    {
      key = "playerFrontFlip",
      type = "toggle",
      label = "MY POKEMON FLIP",
      default = true,
      help = "Mirror only your staged FRONT Pokemon card so it faces the opponent. Back sprites, enemy Pokemon and trainer portraits are unchanged.",
    },
  })

  -- Load only this mod's own files through the API's path-scoped reader.
  -- This works for both folders and ZIP mounts and does not depend on a host
  -- package.path searcher knowing where a mod was installed.
  local function loadOwn(relative)
    local source = assert(mod:read(relative), relative .. " is missing")
    local chunk, err = (loadstring or load)(source,
      "@" .. tostring(mod.path) .. "/" .. relative)
    assert(chunk, err)
    if setfenv and getfenv then setfenv(chunk, getfenv(1)) end
    return chunk()
  end
  local OptionScreen = loadOwn("lib/OptionScreen.lua")
  local Hub = loadOwn("lib/SpriteHub.lua")
  local hub = Hub.new(mod)

  -- The Options suffix is the public shape Modern UI uses to recognize and
  -- present third-party OptionRows screens.  Dual Screen then routes that
  -- composed menu surface like any other UI state.
  local SCREEN_MAIN = "ScottsSpriteOptions"
  local SCREEN_ADVANCED = "ScottsSpriteAdvancedOptions"
  local SCREEN_BATTLE_ART = "ScottsSpriteBattleArtOptions"
  local SCREEN_CRYSTAL = "ScottsSpriteCrystalOptions"
  local SCREEN_PACK = "ScottsSpritePackOptions"

  local function push(game, id)
    mod.ui.push(game, id)
  end

  local function mainRows(game)
    return {
      {
        id = "scotts_sprite_hub.pack",
        label = "PACK",
        value = function() return hub:packLabel() end,
        activate = function(g) push(g, SCREEN_PACK) end,
      },
      {
        id = "scotts_sprite_hub.player_view",
        label = "PLAYER POKEMON",
        value = function() return hub:playerViewLabel() end,
        step = function(g, direction)
          return hub:cyclePlayerView(g, direction)
        end,
      },
      {
        id = "scotts_sprite_hub.player_front_flip",
        label = "MY POKEMON FLIP",
        value = function() return hub:playerFrontFlipLabel(game) end,
        step = function(g)
          return hub:setPlayerFrontFlip(g, not hub:playerFrontFlip(g))
        end,
      },
      {
        id = "scotts_sprite_hub.trainers",
        label = "TRAINER ART",
        value = function(g) return hub:trainerLabel(g) end,
        step = function(g, direction)
          return hub:cycleTrainerSource(g, direction)
        end,
      },
      {
        id = "scotts_sprite_hub.advanced",
        label = "ADVANCED",
        value = function() return "OPEN" end,
        activate = function(g) push(g, SCREEN_ADVANCED) end,
      },
    }
  end

  local function advancedRows()
    return {
      {
        label = "BATTLE ART",
        value = function() return "OPEN" end,
        activate = function(g) push(g, SCREEN_BATTLE_ART) end,
      },
      {
        label = "CRYSTAL",
        value = function()
          if not hub:crystalHandle() then return "NOT LOADED" end
          return hub:crystalReady() and "OPEN" or "UPDATE CRYSTAL"
        end,
        activate = function(g)
          if hub:crystalReady() then push(g, SCREEN_CRYSTAL) end
        end,
      },
      {
        label = "PACK INFO",
        value = function() return "OPEN" end,
        activate = function(g) push(g, SCREEN_PACK) end,
      },
    }
  end

  local function packRows()
    return {
      {
        label = "ACTIVE PACK",
        value = function() return hub:packLabel() end,
      },
      {
        label = "VERSION",
        value = function() return hub:packVersion() end,
      },
      {
        label = "CHANGE PACK",
        value = function() return "MODS + RESTART" end,
      },
      {
        label = "ART FILES",
        value = function() return "SEPARATE MOD" end,
      },
    }
  end

  local function screen(title, rows, onCancel)
    return {
      new = function(game)
        return OptionScreen.new(game, {
          title = title, rows = rows, onCancel = onCancel,
        })
      end,
    }
  end

  mod.content.screens:register(SCREEN_MAIN,
    screen("SPRITES", mainRows))
  mod.content.screens:register(SCREEN_ADVANCED,
    screen("SPRITE ADVANCED", advancedRows))
  mod.content.screens:register(SCREEN_BATTLE_ART,
    screen("BATTLE ART SPRITES", function() return hub:battleArtRows() end))
  mod.content.screens:register(SCREEN_CRYSTAL,
    screen("CRYSTAL SPRITES", function(game) return hub:crystalRows(game) end))
  mod.content.screens:register(SCREEN_PACK,
    screen("SPRITE PACK", packRows))

  mod.hooks:wrap("ui.start_menu.items", function(next, game, items)
    local out = next(game, items)
    if type(out) ~= "table" then return out end
    for _, item in ipairs(out) do
      if item.id == "scotts_sprite_hub.open" or item.label == "SPRITES" then
        return out
      end
    end
    return mod.ui.insertBefore(out, "MODS", {
      id = "scotts_sprite_hub.open",
      label = "SPRITES",
      onSelect = function()
        hub.game = game
        push(game, SCREEN_MAIN)
      end,
    })
  end)

  -- Keep the ordinary OPTIONS page short.  Only the known sprite rows that
  -- this hub re-homes are removed; Battle Art's voxel/camera/lighting rows,
  -- every unrelated mod row, and the engine rows pass through unchanged.
  -- Run outside Crystal (900) and Battle Art (default 0), then filter the
  -- complete downstream result.  A fresh result table also makes repeated
  -- calls and hot-reload-style composition idempotent.
  local hiddenOptionRows = {
    crystalSpriteOptions = true,
  }
  for _, key in ipairs({
    "battleArt", "opponentTrainerSource", "playerTrainerSource",
    "trainerArtSet", "playerArtSet", "playerAnimatedSet",
    "frontAnimatedSet", "backAnimatedSet", "duplicateFix", "playerView",
    "frontFlip", "backPlacement",
  }) do
    hiddenOptionRows["BATTLE_ART_VOXEL_FORK:" .. key] = true
  end
  mod.hooks:wrap("ui.options.rows", function(next, game, rows)
    local out = next(game, rows)
    if type(out) ~= "table" then return out end
    local filtered = {}
    for _, row in ipairs(out) do
      if not (type(row) == "table" and hiddenOptionRows[row.id]) then
        filtered[#filtered + 1] = row
      end
    end
    return filtered
  end, 1000)

  mod.events:on("game.ready", function(payload)
    local game = payload and payload.game
    if game then hub:enforce(game) end
  end)
  local function lifecycle()
    if hub.game then hub:enforce(hub.game) end
  end
  mod.events:on("save.created", lifecycle)
  mod.events:on("save.loaded", lifecycle)
  mod.events:on("mod.options_changed", function(payload)
    if payload and payload.mod == mod.id
        and payload.key == "playerFrontFlip" then
      -- ManagerState has already mirrored the new value into the Loader and
      -- save buckets before emitting. Re-read that authoritative hub option
      -- and apply only Battle Art's player-front presentation contract.
      hub:enforceSpecies(hub.game)
    elseif payload and payload.mod == hub.ids.crystal
        and payload.key == "crystalTrainers" and hub.game then
      -- Crystal v2's current screen writes its save option directly. This
      -- listener is the sanctioned live seam for provider/manager builds
      -- that also announce the change; always read Crystal's save-backed
      -- source of truth rather than trusting an unpersisted event value.
      hub:reconcileCrystalTrainerMode(
        hub.game, hub:crystalMode(hub.game))
    elseif payload and payload.mod == "BATTLE_ART_VOXEL_FORK"
        and (payload.key == "duplicateFix" or payload.key == "frontFlip"
             or payload.key == "playerView"
             or payload.key == "opponentTrainerSource"
             or payload.key == "playerTrainerSource") then
      hub:enforce(hub.game)
    end
  end)

  -- Sync the live Battle Art setting cache immediately. Persistence follows
  -- through game.ready, where the sanctioned Game object is available.
  hub:enforce(nil)

  mod.exports.version = "0.2.1"
  mod.exports.activePack = function() return hub:activePack() end
  mod.exports.packLabel = function() return hub:packLabel() end
  mod.exports.ownership = function() return hub:ownership() end
  mod.exports.trainerSource = function(game)
    return hub:trainerSource(game or hub.game)
  end
  mod.exports.setTrainerSource = function(game, source)
    return hub:setTrainerSource(game or hub.game, source)
  end
  mod.exports.playerFrontFlip = function(game)
    return hub:playerFrontFlip(game or hub.game)
  end
  mod.exports.setPlayerFrontFlip = function(game, enabled)
    return hub:setPlayerFrontFlip(game or hub.game, enabled)
  end
  mod.exports.optionKeys = { playerFrontFlip = "playerFrontFlip" }
  mod.exports.enforce = function(game) return hub:enforce(game) end
  mod.exports.screenIds = {
    main = SCREEN_MAIN,
    advanced = SCREEN_ADVANCED,
    battleArt = SCREEN_BATTLE_ART,
    crystal = SCREEN_CRYSTAL,
    pack = SCREEN_PACK,
  }
end
