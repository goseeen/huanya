param([ValidateSet('win-x64','win-arm64','win-x86')][string]$Runtime = 'win-x64')
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$repo = Split-Path $root -Parent
$out = Join-Path $repo "dist/windows/huanya-2.0.0-preview.1-$Runtime"
dotnet run --project "$root/Huanya.Tests/Huanya.Tests.csproj" -c Release
if ($LASTEXITCODE -ne 0) { throw 'Tests failed' }
dotnet publish "$root/Huanya.Desktop/Huanya.Desktop.csproj" -c Release -r $Runtime --self-contained true -p:PublishSingleFile=false -p:PublishTrimmed=false -o $out
if ($LASTEXITCODE -ne 0) { throw 'Publish failed' }
Get-ChildItem $out -Filter *.pdb -Recurse | Remove-Item
Copy-Item "$repo/LICENSE" $out
Copy-Item "$root/THIRD_PARTY_NOTICES.md" $out
Copy-Item "$root/README.md" "$out/README.md"
Compress-Archive -Path "$out/*" -DestinationPath "$out.zip" -Force
(Get-FileHash "$out.zip" -Algorithm SHA256).Hash.ToLower() + '  ' + (Split-Path "$out.zip" -Leaf) | Set-Content "$out.sha256" -Encoding utf8
Write-Host "Created $out.zip"
