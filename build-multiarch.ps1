<#
.SYNOPSIS
    Build foo_obs_overlay for both x64 and Win32 and assemble a single unified
    multi-arch .fb2k-component.

.DESCRIPTION
    foobar2000 2.x installs one component archive that carries every CPU-arch
    build: the 32-bit (Win32) DLL sits at the zip root; the 64-bit DLL sits under
    x64/. This script configures and builds each arch in its OWN tree with the
    Visual Studio generator (which selects the target arch and toolchain env from
    -A alone, so no vcvars step is needed), then zips both DLLs into the unified
    layout.

    It deliberately uses fresh trees (component/build-x64, component/build-x86)
    and never writes to the developer's existing component/build (Ninja) tree.

.EXAMPLE
    pwsh ./build-multiarch.ps1
    pwsh ./build-multiarch.ps1 -Config Debug
#>
[CmdletBinding()]
param(
    [string]$Config    = "Release",
    [string]$Generator = "Visual Studio 17 2022"
)

$ErrorActionPreference = "Stop"
$repo = $PSScriptRoot
$src  = Join-Path $repo "component"

function Invoke-Cmake {
    param([string[]] $CmakeArgs)
    & cmake @CmakeArgs
    if ($LASTEXITCODE -ne 0) { throw "cmake failed ($LASTEXITCODE): cmake $($CmakeArgs -join ' ')" }
}

function Build-Arch {
    param([string]$Arch, [string]$BuildDir)
    Write-Host "==> Configuring $Arch -> $BuildDir" -ForegroundColor Cyan
    Invoke-Cmake @('-S', $src, '-B', $BuildDir, '-G', $Generator, '-A', $Arch)
    Write-Host "==> Building $Arch ($Config)" -ForegroundColor Cyan
    Invoke-Cmake @('--build', $BuildDir, '--config', $Config, '--target', 'foo_obs_overlay')
}

$x64Dir = Join-Path $src "build-x64"
$x86Dir = Join-Path $src "build-x86"

Build-Arch -Arch "x64"   -BuildDir $x64Dir
Build-Arch -Arch "Win32" -BuildDir $x86Dir

# Visual Studio (multi-config) generator emits the DLL under <BuildDir>/<Config>/.
$x64Dll = Join-Path $x64Dir "$Config\foo_obs_overlay.dll"
$x86Dll = Join-Path $x86Dir "$Config\foo_obs_overlay.dll"
foreach ($dll in @($x64Dll, $x86Dll)) {
    if (-not (Test-Path $dll)) { throw "expected DLL not found: $dll" }
}

# Stage the unified layout: Win32 DLL at root, x64 DLL under x64/.
$dist  = Join-Path $src "dist"
$stage = Join-Path $dist "package"
if (Test-Path $stage) { Remove-Item -Recurse -Force $stage }
New-Item -ItemType Directory -Force (Join-Path $stage "x64") | Out-Null
Copy-Item $x86Dll (Join-Path $stage "foo_obs_overlay.dll")     -Force
Copy-Item $x64Dll (Join-Path $stage "x64\foo_obs_overlay.dll") -Force

$out = Join-Path $dist "foo_obs_overlay.fb2k-component"
if (Test-Path $out) { Remove-Item -Force $out }

# cmake -E tar writes a portable zip with forward-slash entries (matches the
# per-tree packaging in CMakeLists.txt). Paths are relative to the stage dir.
Push-Location $stage
try {
    Invoke-Cmake @('-E', 'tar', 'cf', $out, '--format=zip', 'foo_obs_overlay.dll', 'x64/foo_obs_overlay.dll')
} finally {
    Pop-Location
}

Write-Host ""
Write-Host "Unified multi-arch package:" -ForegroundColor Green
Write-Host "  $out"
Write-Host "  contents:"
& cmake -E tar tf $out | ForEach-Object { Write-Host "    $_" }
