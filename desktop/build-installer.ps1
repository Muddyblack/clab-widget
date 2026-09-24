# Builds CLAB-Widget-Setup-<version>.exe (repository root) from PyInstaller's
# "dist\CLAB Widget" folder with Inno Setup — see desktop/installer.iss. Used by
# .github/workflows/desktop.yml (which release.yml runs for a tag); run it from
# the repository root after
#   pyinstaller --noconfirm desktop/clab-widget.spec
#
#   desktop/build-installer.ps1 -Version 0.2.0
param([Parameter(Mandatory = $true)][string]$Version)
$ErrorActionPreference = "Stop"

function Find-Iscc {
    $onPath = Get-Command ISCC.exe -ErrorAction SilentlyContinue
    if ($onPath) { return $onPath.Source }
    $found = foreach ($root in ${env:ProgramFiles(x86)}, $env:ProgramFiles, "$env:LOCALAPPDATA\Programs") {
        if ($root) { Get-Item -Path (Join-Path $root "Inno Setup *\ISCC.exe") -ErrorAction SilentlyContinue }
    }
    return ($found | Sort-Object FullName -Descending | Select-Object -First 1).FullName
}

$iscc = Find-Iscc
if (-not $iscc) {
    choco install innosetup -y --no-progress | Out-Null
    $iscc = Find-Iscc
}
if (-not $iscc) { throw "Inno Setup's ISCC.exe was not found, and installing it with Chocolatey did not help." }
Write-Output "Using $iscc"

& $iscc "/DAppVersion=$Version" "desktop\installer.iss"
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
