$ErrorActionPreference = 'Stop'

$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$Build = Join-Path $Root 'build'
$Dist = Join-Path $Root 'dist'

cmake -S $Root -B $Build -A x64
cmake --build $Build --config Release
ctest --test-dir $Build -C Release --output-on-failure

New-Item -ItemType Directory -Force -Path $Dist | Out-Null
Copy-Item -Force (Join-Path $Build 'Release\RlfcMemoryBridge.dll') $Dist
Copy-Item -Force (Join-Path $Build 'Release\RlfcMemoryBridge.lib') $Dist -ErrorAction SilentlyContinue

Get-FileHash (Join-Path $Dist 'RlfcMemoryBridge.dll') -Algorithm SHA256
Write-Host "Built: $Dist\RlfcMemoryBridge.dll"
