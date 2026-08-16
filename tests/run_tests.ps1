[CmdletBinding()]
param(
  [string]$ModRoot = (Split-Path -Parent $PSScriptRoot),
  [string]$BattleArtRoot = (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'battle_art_kanto_private\mod'),
  [string]$FireRedRoot = (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'firered_battle_sprites'),
  [string]$DualScreenRoot = (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'dual_screen_scott_stack_private'),
  [string]$CrystalZip = (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'best_mod_stack_staging\crystal_animated_sprites_with_shiny_visuals_v2.0.zip'),
  [string]$ModernZip = (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'best_mod_stack_staging\gen1_modern_ui-0.9.1.zip'),
  [string[]]$EngineRoots = @(
    (Join-Path $env:TEMP 'codex_gen1recomp_source_v0.1.88'),
    (Join-Path $env:TEMP 'codex_gen1recomp_source_v0.1.96')
  )
)

$ErrorActionPreference = 'Stop'
$lua = (Get-Command luajit -ErrorAction Stop).Source
$modPath = [IO.Path]::GetFullPath($ModRoot)

& $lua (Join-Path $PSScriptRoot 'static_test.lua') $modPath
if ($LASTEXITCODE -ne 0) { throw "static test failed: $LASTEXITCODE" }
& $lua (Join-Path $PSScriptRoot 'controller_test.lua') $modPath
if ($LASTEXITCODE -ne 0) { throw "controller test failed: $LASTEXITCODE" }

$luaFiles = Get-ChildItem -LiteralPath $modPath -Recurse -File -Filter '*.lua'
$bytecode = Join-Path $env:TEMP 'scotts-sprite-hub-bytecode.tmp'
foreach ($file in $luaFiles) {
  & $lua -b $file.FullName $bytecode
  if ($LASTEXITCODE -ne 0) { throw "LuaJIT compile failed: $($file.FullName)" }
}
Write-Host "LuaJIT syntax OK: $($luaFiles.Count) files"

foreach ($required in @(
  (Join-Path $BattleArtRoot 'manifest.json'),
  (Join-Path $FireRedRoot 'manifest.json'),
  (Join-Path $DualScreenRoot 'manifest.json'),
  $CrystalZip, $ModernZip
)) {
  if (-not (Test-Path -LiteralPath $required)) { throw "Missing test input: $required" }
}

$installRoot = Join-Path $env:TEMP ('scotts-sprite-hub-loader-' +
  [guid]::NewGuid().ToString('N'))
$modsRoot = Join-Path $installRoot 'mods'
try {
  New-Item -ItemType Directory -Path $modsRoot -Force | Out-Null
  $sources = @{
    'BATTLE_ART_VOXEL_FORK' = $BattleArtRoot
    'firered_battle_sprites' = $FireRedRoot
    'gen1recomp_ds' = $DualScreenRoot
    'scotts_sprite_hub' = $modPath
  }
  foreach ($id in $sources.Keys) {
    $target = Join-Path $modsRoot $id
    New-Item -ItemType Directory -Path $target -Force | Out-Null
    Get-ChildItem -LiteralPath $sources[$id] -Force |
      Copy-Item -Destination $target -Recurse -Force
  }
  Expand-Archive -LiteralPath $CrystalZip -DestinationPath (
    Join-Path $modsRoot 'crystal_animated_sprites_with_shiny_visuals') -Force
  Expand-Archive -LiteralPath $ModernZip -DestinationPath (
    Join-Path $modsRoot 'gen1_modern_ui') -Force

  foreach ($engineRoot in $EngineRoots) {
    $enginePath = [IO.Path]::GetFullPath($engineRoot)
    if (-not (Test-Path -LiteralPath (Join-Path $enginePath 'src\mods\Loader.lua'))) {
      throw "Missing Gen1Recomp source tree: $enginePath"
    }
    foreach ($scenario in @(
      'crystal', 'firered', 'battle_art', 'hub_only', 'conflict'
    )) {
      & $lua (Join-Path $PSScriptRoot 'loader_matrix_test.lua') `
        $enginePath $installRoot $scenario
      if ($LASTEXITCODE -ne 0) {
        throw "Loader $scenario failed for $enginePath`: $LASTEXITCODE"
      }
    }
  }
}
finally {
  $tempPrefix = [IO.Path]::GetFullPath($env:TEMP).TrimEnd('\') + '\'
  $resolved = [IO.Path]::GetFullPath($installRoot)
  if ($resolved.StartsWith($tempPrefix,
      [StringComparison]::OrdinalIgnoreCase) -and
      (Test-Path -LiteralPath $resolved)) {
    Remove-Item -LiteralPath $resolved -Recurse -Force
  }
}

Write-Host "Scott's Sprite Menu focused and real-Loader matrices passed."
