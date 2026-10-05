$ErrorActionPreference='Stop'
$root=Split-Path $PSScriptRoot -Parent
$package=Join-Path $root 'build/package/Release/motorcycle'
$manifest=Get-Content -LiteralPath (Join-Path $package 'zml-package.json') -Raw | ConvertFrom-Json
$files=@($manifest.files)+@('zml-package.json')
if($manifest.id -ne 'motorcycle' -or $files.Count -ne 14){throw 'Whitelist changed'}
$paths=@($files | ForEach-Object {
 if($_ -notmatch '^[a-zA-Z0-9._/-]+$' -or $_ -match '(^|/)\.\.(/|$)' -or [IO.Path]::IsPathRooted($_)){throw 'Unsafe filename'}
 $path=Join-Path $package $_
 if(-not(Test-Path -LiteralPath $path -PathType Leaf)){throw "Missing runtime file $_"}
 $path
})
$dist=Join-Path $root 'dist';New-Item -ItemType Directory -Force $dist | Out-Null
$ini=Get-Content -LiteralPath (Join-Path $package 'mod.ini') -Raw
if($ini -notmatch '(?m)^version=(\d+\.\d+\.\d+)\r?$'){throw 'Invalid package version'}
$zip=Join-Path $dist ('EndfieldMotorcycle-'+$Matches[1]+'-'+(Get-Date -Format 'yyyyMMdd-HHmmss')+'.zip')
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem
$archive=[IO.Compression.ZipFile]::Open($zip,[IO.Compression.ZipArchiveMode]::Create)
try {
 foreach($file in $files){
  [IO.Compression.ZipFileExtensions]::CreateEntryFromFile($archive,(Join-Path $package $file),$file,[IO.Compression.CompressionLevel]::Optimal) | Out-Null
 }
} finally {$archive.Dispose()}
(Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash+'  '+(Split-Path $zip -Leaf) | Set-Content -Encoding ascii ($zip+'.sha256')
Write-Output $zip
