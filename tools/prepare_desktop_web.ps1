$ErrorActionPreference = 'Stop'

$repository = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$source = Join-Path $repository 'build\web'
$destination = Join-Path $repository 'desktop-shell\web'
if (-not (Test-Path -LiteralPath (Join-Path $source 'index.html'))) {
    throw 'Run flutter build web before preparing the desktop shell.'
}

New-Item -ItemType Directory -Path $destination -Force | Out-Null
Copy-Item -Path (Join-Path $source '*') -Destination $destination -Recurse -Force

$indexPath = Join-Path $destination 'index.html'
$index = Get-Content -LiteralPath $indexPath -Raw -Encoding UTF8
$index = $index.Replace('<base href="/">', '<base href="./">')
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($indexPath, $index, $utf8NoBom)

$bootstrapPath = Join-Path $destination 'flutter_bootstrap.js'
$bootstrap = Get-Content -LiteralPath $bootstrapPath -Raw -Encoding UTF8
if ($index -notmatch '<base href="\.\/">') {
    throw 'Desktop index.html does not use a relative base URL.'
}
if ($bootstrap -notmatch "canvasKitBaseUrl:\s*'canvaskit/'") {
    throw 'Desktop bootstrap does not use the packaged CanvasKit directory.'
}

Write-Output "Prepared Electron web assets: $destination"
