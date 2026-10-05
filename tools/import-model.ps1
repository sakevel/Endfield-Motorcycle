param([Parameter(Mandatory=$true)][string]$Fbx)
$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$commit='5955c5c0b042ac2dc6f32955ab206aaec0620cfc'
if((Get-FileHash -LiteralPath $Fbx -Algorithm SHA256).Hash.ToLowerInvariant() -ne '5d56eebae795a1da9daf6185bad436ef5a56aba36c4d39935f1fb45a43dcbd95'){throw 'Expected the selected original Sidra #2 FBX; node mapping is source-specific'}
$upstream=Join-Path $root 'artifacts/model-import/ufbx'
if(-not(Test-Path -LiteralPath $upstream)){
 $check=gh api "repos/ufbx/ufbx/commits/$commit" --jq .sha
 if($LASTEXITCODE -or $check -ne $commit){throw 'Authenticated upstream revision check failed'}
 gh repo clone ufbx/ufbx $upstream -- --depth 1
 if($LASTEXITCODE){throw 'Clone failed'}
 if((git -C $upstream rev-parse HEAD) -ne $commit){
  git -C $upstream fetch --depth 1 origin $commit
  if($LASTEXITCODE){throw 'Pinned fetch failed'}
  git -C $upstream checkout --detach $commit
  if($LASTEXITCODE){throw 'Pinned checkout failed'}
 }
}
if((git -C $upstream rev-parse HEAD) -ne $commit -or (git -C $upstream status --porcelain)){throw 'Existing upstream checkout must be clean and pinned; not overwritten'}
$build=Join-Path $root 'artifacts/model-import/converter-build'
cmake -S (Join-Path $PSScriptRoot 'model-converter') -B $build -G 'Visual Studio 17 2022' -A x64 "-DUFBX_DIR=$upstream"
if($LASTEXITCODE){throw 'Converter configure failed'}
cmake --build $build --config Release --parallel 4
if($LASTEXITCODE){throw 'Converter build failed'}
$mesh=Join-Path $root 'mod/assets/sidra-bike.zmlmesh'
& (Join-Path $build 'Release/BikeConverter.exe') (Resolve-Path -LiteralPath $Fbx).Path $mesh
if($LASTEXITCODE){throw 'Model conversion failed'}
python (Join-Path $PSScriptRoot 'repaint-model.py')
if($LASTEXITCODE){throw 'Endfield material/UV recolor failed'}
python (Join-Path $PSScriptRoot 'calibrate-bike.py')
if($LASTEXITCODE){throw 'Neutral frame/axle calibration failed'}
$texture=Join-Path $root 'mod/assets/Textures.png'
$mh=(Get-FileHash -LiteralPath $mesh -Algorithm SHA256).Hash.ToLowerInvariant()
$th=(Get-FileHash -LiteralPath $texture -Algorithm SHA256).Hash.ToLowerInvariant()
"#pragma once`nnamespace motorcycle {`ninline constexpr char meshHash[]=`"$mh`";`ninline constexpr char textureHash[]=`"$th`";`n}`n" | Set-Content -Encoding utf8 (Join-Path $root 'src/asset_hashes.hpp')
Move-Item -LiteralPath ($mesh+'.txt') -Destination (Join-Path $root 'docs/MODEL_EXPORT.txt') -Force
