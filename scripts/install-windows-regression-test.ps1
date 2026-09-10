$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSCommandPath)
$installerPath = Join-Path $repoRoot "scripts\install.ps1"
$tokens = $null
$parseErrors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile(
    $installerPath,
    [ref]$tokens,
    [ref]$parseErrors
)
if ($parseErrors.Count -ne 0) {
    throw "install.ps1 has PowerShell parse errors: $($parseErrors -join '; ')"
}

$functionAst = $ast.Find(
    { param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq "Ensure-ResourceRootEntry" },
    $true
)
if (-not $functionAst) {
    throw "Ensure-ResourceRootEntry is missing from install.ps1"
}
Invoke-Expression $functionAst.Extent.Text

$testRoot = Join-Path ([System.IO.Path]::GetTempPath()) "ryk-install-windows-$([Guid]::NewGuid().ToString('N'))"
$oldProfile = $PROFILE
try {
    New-Item -ItemType Directory -Path $testRoot | Out-Null
    $PROFILE = Join-Path $testRoot "Microsoft.PowerShell_profile.ps1"
    $firstRoot = Join-Path $testRoot "share\0.0.1"
    $secondRoot = Join-Path $testRoot "share\0.0.2"

    Ensure-ResourceRootEntry $firstRoot
    Ensure-ResourceRootEntry $secondRoot

    $profileLines = @(Get-Content -LiteralPath $PROFILE)
    $markerLines = @($profileLines | Where-Object { $_ -eq "# ryk runtime assets" })
    $rootLines = @($profileLines | Where-Object { $_ -match '^\$env:RYK_RESOURCE_ROOT\s*=' })
    if ($markerLines.Count -ne 1) {
        throw "expected one runtime marker after repeated setup, got $($markerLines.Count)"
    }
    if ($rootLines.Count -ne 1 -or $rootLines[0] -ne "`$env:RYK_RESOURCE_ROOT = `"$secondRoot`"") {
        throw "repeated setup did not replace the runtime root: $($rootLines -join '; ')"
    }
    Write-Host "[install-windows-regression] passed"
} finally {
    $PROFILE = $oldProfile
    Remove-Item -LiteralPath $testRoot -Recurse -Force -ErrorAction SilentlyContinue
}
