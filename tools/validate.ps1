param(
    [string]$GodotPath = $env:MERGEFALL_GODOT,
    [switch]$SkipExport
)

$ErrorActionPreference = "Stop"
$ProjectRoot = Split-Path -Parent $PSScriptRoot

function Resolve-Godot {
    param([string]$RequestedPath)

    if ($RequestedPath -and (Test-Path -LiteralPath $RequestedPath)) {
        return (Resolve-Path -LiteralPath $RequestedPath).Path
    }

    $localGodot = Join-Path $ProjectRoot "tools/local-godot/Godot_v4.7.1-stable_win64_console.exe"
    if (Test-Path -LiteralPath $localGodot) {
        return $localGodot
    }

    $pathCommand = Get-Command godot -ErrorAction SilentlyContinue
    if ($pathCommand) {
        return $pathCommand.Source
    }

    throw "Godot 4.7.1 was not found. Set MERGEFALL_GODOT or install godot on PATH."
}

$Godot = Resolve-Godot $GodotPath
Write-Host "Using Godot: $Godot"

Push-Location $ProjectRoot
try {
    & $Godot --headless --import --quit
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

    & $Godot --headless -s res://tests/run_rules_tests.gd
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

    & $Godot --headless -s res://tests/falling_feel_test_runner.gd
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

    if (-not $SkipExport) {
        New-Item -ItemType Directory -Force -Path "build/web" | Out-Null
        & $Godot --headless --export-release Web build/web/index.html
        if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
    }
}
finally {
    Pop-Location
}
