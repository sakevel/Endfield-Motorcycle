param([string]$LupaPath='', [string]$ServicesFixture='', [string]$KeybindsLua='')
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$opts=@()
if($KeybindsLua){$opts+="-DZML_KEYBINDS_LUA=$KeybindsLua"}
& cmake -S $root -B (Join-Path $root 'build') -G 'Visual Studio 17 2022' -A x64 "-DZML_LUPA_PATH=$LupaPath" "-DZML_SERVICES_TEST_EXE=$ServicesFixture" @opts
if($LASTEXITCODE){throw 'Configure failed'}
& cmake --build (Join-Path $root 'build') --config Release --parallel 6
if($LASTEXITCODE){throw 'Build failed'}
& ctest --test-dir (Join-Path $root 'build') -C Release --output-on-failure
if($LASTEXITCODE){throw 'Tests failed'}
