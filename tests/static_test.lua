local argv = rawget(_G, "arg") or {}
local root = assert(argv[1], "mod root required"):gsub("\\", "/"):gsub("/$", "")

local function read(relative)
  local file = assert(io.open(root .. "/" .. relative, "rb"), relative)
  local body = file:read("*a")
  file:close()
  return body
end

for _, relative in ipairs({ "main.lua", "lib/OptionScreen.lua",
                             "lib/SpriteHub.lua" }) do
  local chunk, err = loadfile(root .. "/" .. relative)
  assert(chunk, relative .. ": " .. tostring(err))
end

local manifest = read("manifest.json")
assert(manifest:match('"id"%s*:%s*"scotts_sprite_hub"'), "stable id")
assert(manifest:match('"name"%s*:%s*"Scott\'s Sprite Menu"'), "name")
assert(manifest:match('"version"%s*:%s*"0%.2%.2"'), "version")
assert(manifest:match('"github"%s*:%s*"ScottExplores/gen1recomp%-scotts%-sprite%-hub"'),
  "public updater repository")
assert(manifest:match('"game_version"%s*:%s*">=0%.1%.88 <2%.0%.0"'),
  "engine range")
assert(manifest:match('"dependencies"%s*:%s*%[%s*%]'),
  "isolated validation has no hard sibling dependency")
local optionalAt = assert(manifest:find('"optional_dependencies"', 1, true))
local battleArtAt = assert(manifest:find('"BATTLE_ART_VOXEL_FORK"', 1, true))
assert(battleArtAt > optionalAt, "Battle Art is an optional companion dependency")
for _, id in ipairs({ "crystal_animated_sprites_with_shiny_visuals",
                       "firered_battle_sprites", "gen1_modern_ui",
                       "gen1recomp_ds" }) do
  assert(manifest:find('"' .. id .. '"', 1, true), "optional: " .. id)
end

local main = read("main.lua")
for _, id in ipairs({ "ScottsSpriteOptions", "ScottsSpriteAdvancedOptions",
  "ScottsSpriteBattleArtOptions", "ScottsSpriteCrystalOptions",
  "ScottsSpritePackOptions" }) do
  assert(main:find(id, 1, true), "Modern-compatible screen id: " .. id)
end
for _, label in ipairs({ 'label = "PACK"', 'label = "PLAYER POKEMON"',
                         'label = "MY POKEMON FLIP"',
                         'label = "TRAINER ART"', 'label = "ADVANCED"' }) do
  assert(main:find(label, 1, true), "compact main row: " .. label)
end
assert(main:find('key = "playerFrontFlip"', 1, true),
  "hub owns the player-front flip preference")
assert(main:find('type = "toggle"', 1, true), "flip is a toggle option")
assert(main:find('default = true', 1, true), "flip defaults ON")
assert(main:find('payload.mod == mod.id', 1, true)
    and main:find('payload.key == "playerFrontFlip"', 1, true),
  "hub Mod Manager changes apply live")
assert(main:find('mod.exports.version = "0.2.2"', 1, true),
  "exported version")
local startCount, offset, needle = 0, 1, 'id = "scotts_sprite_hub.open"'
while true do
  local found = main:find(needle, offset, true)
  if not found then break end
  startCount, offset = startCount + 1, found + #needle
end
assert(startCount == 1, "exactly one Start row descriptor")
assert(main:find('item.id == "scotts_sprite_hub.open"', 1, true),
  "Start row duplicate guard")
assert(main:find('label = "SPRITES"', 1, true), "single Start label")
assert(main:find('mod.ui.insertBefore(out, "MODS"', 1, true),
  "Start row anchored before MODS")
assert(main:find('mod.hooks:wrap("ui.options.rows"', 1, true),
  "known duplicate rows filtered")
assert(main:find("end, 1000)", 1, true),
  "filter wraps outside Crystal and Battle Art")
for _, key in ipairs({ "crystalSpriteOptions", "battleArt",
  "opponentTrainerSource", "playerTrainerSource", "trainerArtSet",
  "playerArtSet", "playerAnimatedSet", "frontAnimatedSet",
  "backAnimatedSet", "duplicateFix", "playerView", "frontFlip",
  "backPlacement" }) do
  assert(main:find(key, 1, true), "re-homed option id: " .. key)
end

local hub = read("lib/SpriteHub.lua")
for _, marker in ipairs({ 'pokemon = "modded", frontFlip = frontFlip',
                          'pokemon = "battle_art", frontFlip = frontFlip',
                          'self:applyOwnership({ frontFlip = value }, game)',
                          'options.modOptions = options.modOptions or {}',
                          'loader.modOptions = loader.modOptions or {}',
                          'pcall(game.writeOptions, game)',
                          'return false, "UPDATE BATTLE ART"',
                          'return false, "UPDATE CRYSTAL"',
                          'game.save.options[key] = value' }) do
  assert(hub:find(marker, 1, true), "ownership/persistence contract: " .. marker)
end
assert(not hub:find('pokemon = "modded", frontFlip = "default"', 1, true),
  "provider selection cannot override hub flip preference")

local forbiddenExtensions = {
  png = true, jpg = true, jpeg = true, gif = true, webp = true,
  bmp = true, tga = true, psd = true, ase = true, aseprite = true,
}
local command = 'dir /s /b "' .. root:gsub('/', '\\') .. '"'
local pipe = assert(io.popen(command))
for path in pipe:lines() do
  local extension = path:match("%.([^%.\\/]+)$")
  assert(not (extension and forbiddenExtensions[extension:lower()]),
    "adapter must not ship art/icon asset: " .. path)
end
pipe:close()

local readme = read("README.md")
for _, marker in ipairs({ "no Pokemon art",
  "no duplicate provider sprite-settings schema",
  "no sprite or icon assets", "no Pokemon art, trainer art, menu art",
  "user's own Pokemon Gold", "PackMenuGFX", "roadmap only" }) do
  assert(readme:lower():find(marker:lower(), 1, true),
    "README provenance boundary: " .. marker)
end
assert(readme:find("install", 1, true)
    and readme:find("0.2.0 did not", 1, true)
    and readme:find("SCOTTS_SPRITE_MENU-0.2.2.zip", 1, true)
    and readme:find("0.2.1", 1, true)
    and readme:find("internal ID", 1, true)
    and readme:find("future GitHub releases", 1, true),
  "README documents one-time updater bootstrap")

print("Scott's Sprite Menu static contracts passed")
