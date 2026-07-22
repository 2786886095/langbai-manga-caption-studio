param(
    [Parameter(Mandatory = $true)]
    [string]$SourceProjects,

    [Parameter(Mandatory = $true)]
    [string]$DestinationProjects
)

$ErrorActionPreference = 'Stop'
$source = [System.IO.Path]::GetFullPath($SourceProjects)
$destination = [System.IO.Path]::GetFullPath($DestinationProjects)
if (-not (Test-Path -LiteralPath $source -PathType Container)) {
    throw "Source project directory does not exist: $source"
}
if ($destination.StartsWith($source, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw 'Destination must not be inside the source project directory.'
}
if (Test-Path -LiteralPath $destination) {
    throw "Destination already exists: $destination"
}

New-Item -ItemType Directory -Path $destination | Out-Null
Get-ChildItem -LiteralPath $source -Force | ForEach-Object {
    Copy-Item -LiteralPath $_.FullName -Destination $destination -Recurse -Force
}

$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$report = @()
Get-ChildItem -LiteralPath $destination -Directory | ForEach-Object {
    $projectId = $_.Name
    $manifestPath = Join-Path $_.FullName 'manifest.json'
    $editsPath = Join-Path $destination ($projectId + '.edits.json')
    if (-not (Test-Path -LiteralPath $manifestPath) -or
        -not (Test-Path -LiteralPath $editsPath)) {
        return
    }

    $manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 |
        ConvertFrom-Json
    $edits = Get-Content -LiteralPath $editsPath -Raw -Encoding UTF8 |
        ConvertFrom-Json
    if ($manifest.format -ne 'bubble-caption-studio-manifest' -or
        $edits.format -ne 'bubble-caption-studio-edits' -or
        [int]$edits.schemaVersion -ne 1) {
        return
    }

    $manifestPages = @{}
    foreach ($page in @($manifest.pages)) {
        $manifestPages[[string]$page.pageId] = $page
    }
    $recoveredPages = 0
    $recoveredBubbles = 0
    foreach ($editPage in @($edits.pages)) {
        $manifestPage = $manifestPages[[string]$editPage.pageId]
        if ($null -eq $manifestPage) { continue }
        $editCaptionCount = @($editPage.captions).Count
        $editPlacementCount = @($editPage.placements).Count
        $manifestCaptionCount = @($manifestPage.captions).Count
        $manifestPlacementCount = @($manifestPage.placements).Count
        if ($editCaptionCount -eq 0 -and
            $editPlacementCount -eq 0 -and
            $manifestCaptionCount -gt 0 -and
            $manifestCaptionCount -eq $manifestPlacementCount) {
            $editPage.captions = $manifestPage.captions
            $editPage.placements = $manifestPage.placements
            $editPage.approved = $manifestPage.approved
            $recoveredPages++
            $recoveredBubbles += $manifestCaptionCount
        }
    }

    if ($recoveredPages -gt 0) {
        $edits.schemaVersion = 2
        $edits.script = $manifest.script
        $edits.savedAt = [DateTime]::UtcNow.ToString('o')
        $json = $edits | ConvertTo-Json -Depth 100 -Compress
        [System.IO.File]::WriteAllText($editsPath, $json, $utf8NoBom)
    }
    $report += [pscustomobject]@{
        Project = $projectId
        RecoveredPages = $recoveredPages
        RecoveredBubbles = $recoveredBubbles
    }
}

$report | Sort-Object Project
