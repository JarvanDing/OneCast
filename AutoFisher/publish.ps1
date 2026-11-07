# Build a single-file AutoFisher.exe (NAudio embedded via Costura.Fody)
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$out = Join-Path $root "publish"
$cfg = "Release"

Write-Host "Restoring..."
dotnet restore $root
Write-Host "Building $cfg..."
dotnet build (Join-Path $root "AutoFisher.csproj") -c $cfg
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

$bin = Join-Path $root "bin\$cfg\net48"
if (Test-Path $out) { Remove-Item $out -Recurse -Force }
New-Item -ItemType Directory -Path $out | Out-Null

Copy-Item (Join-Path $bin "AutoFisher.exe") (Join-Path $out "AutoFisher.exe") -Force
# Costura embeds managed deps; keep README for the zip
Copy-Item (Join-Path $root "README.md") (Join-Path $out "README.md") -Force
Copy-Item (Join-Path $root "Assets\autofisher-logo.jpg") (Join-Path $out "autofisher-logo.jpg") -Force

$zip = Join-Path $root "AutoFisher-portable.zip"
if (Test-Path $zip) { Remove-Item $zip -Force }
Compress-Archive -Path (Join-Path $out "*") -DestinationPath $zip -Force

Write-Host ""
Write-Host "Single-file EXE: $(Join-Path $out 'AutoFisher.exe')"
Get-ChildItem $out | Format-Table Name, Length
Write-Host "Zip: $zip"
Get-Item $zip | Format-List FullName, Length
