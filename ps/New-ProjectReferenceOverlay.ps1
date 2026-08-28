<#
.SYNOPSIS
    Generates "@"-overlay csproj files that use ProjectReference instead of
    matching PackageReference entries, strips net462 from TargetFrameworks,
    builds a grouped .slnx solution referencing the overlay projects, and
    ensures every .gitignore excludes the generated files.

.DESCRIPTION
    1. Finds all *.csproj files in child folders of the repo root.
    2. Copies each "Foo.csproj" -> "Foo.@.csproj".
    3. For every PackageReference in the overlay whose Include name matches
       the name of another discovered project, replaces it with a
       ProjectReference pointing at that project's own "@"-overlay csproj.
    4. Removes "net462" from any <TargetFramework(s)> element.
    5. Creates a single grouped Solution.@.slnx (new XML .slnx format),
       grouping projects by their parent folder.
    6. Appends "*.@.csproj" to every .gitignore found in the repo (creating
       one at the root if none exist).

.PARAMETER RepoRoot
    Root folder to operate on. Defaults to current directory.

.PARAMETER SolutionName
    Base name for the generated slnx file (without extension). Defaults to
    the repo root folder name.

.EXAMPLE
    ./New-ProjectReferenceOverlay.ps1 -RepoRoot C:\src\MySolution
#>

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string]$RepoRoot = (Get-Location).Path,
    [string]$SolutionName
)

$ErrorActionPreference = 'Stop'
$RepoRoot = (Resolve-Path $RepoRoot).Path

if (-not $SolutionName) {
    $SolutionName = Split-Path $RepoRoot -Leaf
}

# ---------------------------------------------------------------------------
# 1. Find all child-folder *.csproj files (exclude anything already an overlay)
# ---------------------------------------------------------------------------
$projects = Get-ChildItem -Path $RepoRoot -Recurse -Filter *.csproj -File |
    Where-Object { $_.Name -notmatch '\.@\.csproj$' }

if (-not $projects) {
    Write-Warning "No .csproj files found under $RepoRoot"
    return
}

Write-Host "Found $($projects.Count) project(s):" -ForegroundColor Cyan
$projects | ForEach-Object { Write-Host "  $($_.FullName)" }

# Map: project short name (no extension) -> original csproj FileInfo
$projectByName = @{}
foreach ($p in $projects) {
    $shortName = [System.IO.Path]::GetFileNameWithoutExtension($p.Name)
    $projectByName[$shortName] = $p
}

function Get-OverlayPath {
    param([System.IO.FileInfo]$Project)
    $dir  = $Project.DirectoryName
    $name = [System.IO.Path]::GetFileNameWithoutExtension($Project.Name)
    Join-Path $dir "$name.@.csproj"
}

$overlayPaths = @{}  # short name -> overlay full path

# ---------------------------------------------------------------------------
# 2. Copy each csproj to *.@.csproj
# ---------------------------------------------------------------------------
foreach ($p in $projects) {
    $overlay = Get-OverlayPath -Project $p
    $overlayPaths[[System.IO.Path]::GetFileNameWithoutExtension($p.Name)] = $overlay

    if ($PSCmdlet.ShouldProcess($overlay, "Copy from $($p.FullName)")) {
        Copy-Item -Path $p.FullName -Destination $overlay -Force
        Write-Host "Created overlay: $overlay" -ForegroundColor Green
    }
}

# ---------------------------------------------------------------------------
# 3 & 4. Edit each overlay: swap matching PackageReference -> ProjectReference,
#        and strip net462 from TargetFramework(s)
# ---------------------------------------------------------------------------
foreach ($p in $projects) {
    $shortName    = [System.IO.Path]::GetFileNameWithoutExtension($p.Name)
    $overlayPath  = $overlayPaths[$shortName]

    [xml]$xml = Get-Content -Path $overlayPath -Raw
    $ns = $xml.DocumentElement.NamespaceURI

    # --- 3. Replace matching PackageReference with ProjectReference ---
    $packageRefs = $xml.SelectNodes("//PackageReference")
    foreach ($pkgRef in @($packageRefs)) {
        $include = $pkgRef.GetAttribute("Include")
        if ($include -and $projectByName.ContainsKey($include)) {
            $targetProject = $projectByName[$include]
            $targetOverlay = Get-OverlayPath -Project $targetProject
            $relPath = [System.IO.Path]::GetRelativePath(
                (Split-Path $overlayPath -Parent), $targetOverlay
            )

            $projRef = $xml.CreateElement("ProjectReference", $ns)
            $projRef.SetAttribute("Include", $relPath)
            $pkgRef.ParentNode.ReplaceChild($projRef, $pkgRef) | Out-Null

            Write-Host "  [$shortName] PackageReference '$include' -> ProjectReference '$relPath'"
        }
    }

    # --- 4. Remove net462 from TargetFramework(s) ---
    foreach ($tag in @("TargetFrameworks", "TargetFramework")) {
        $nodes = $xml.SelectNodes("//$tag")
        foreach ($node in $nodes) {
            if (-not $node.InnerText) { continue }
            $frameworks = $node.InnerText -split ';' |
                Where-Object { $_.Trim() -and $_.Trim() -ne 'net462' }

            if ($frameworks.Count -eq 0) {
                Write-Warning "  [$shortName] Removing net462 leaves no target frameworks in $tag."
                $node.InnerText = ''
            }
            elseif ($frameworks.Count -eq 1 -and $tag -eq 'TargetFrameworks') {
                # Collapse to singular element if only one framework remains
                $singular = $xml.CreateElement("TargetFramework", $ns)
                $singular.InnerText = $frameworks[0]
                $node.ParentNode.ReplaceChild($singular, $node) | Out-Null
            }
            else {
                $node.InnerText = ($frameworks -join ';')
            }
        }
    }

    $xml.Save($overlayPath)
}

# ---------------------------------------------------------------------------
# 5. Manually build a grouped .slnx solution (new XML-based format)
# ---------------------------------------------------------------------------
$slnxPath = Join-Path $RepoRoot "$SolutionName.@.slnx"

# Group overlay projects by their parent folder name
$grouped = $projects | Group-Object { Split-Path $_.DirectoryName -Leaf }

$sb = New-Object System.Text.StringBuilder
[void]$sb.AppendLine('<Solution>')

foreach ($group in $grouped | Sort-Object Name) {
    [void]$sb.AppendLine("  <Folder Name=`"/$($group.Name)/`">")
    foreach ($p in ($group.Group | Sort-Object Name)) {
        $overlay = $overlayPaths[[System.IO.Path]::GetFileNameWithoutExtension($p.Name)]
        $relPath = [System.IO.Path]::GetRelativePath($RepoRoot, $overlay) -replace '\\','/'
        [void]$sb.AppendLine("    <Project Path=`"$relPath`" />")
    }
    [void]$sb.AppendLine('  </Folder>')
}

[void]$sb.AppendLine('</Solution>')

if ($PSCmdlet.ShouldProcess($slnxPath, "Write solution file")) {
    Set-Content -Path $slnxPath -Value $sb.ToString() -Encoding UTF8
    Write-Host "Created solution: $slnxPath" -ForegroundColor Green
}

# ---------------------------------------------------------------------------
# 6. Add *.@.csproj to every .gitignore (create one at root if none exist)
# ---------------------------------------------------------------------------
$ignoreEntry = '*.@.csproj'
$gitignores = Get-ChildItem -Path $RepoRoot -Recurse -Filter .gitignore -File -Force

if (-not $gitignores) {
    $rootIgnore = Join-Path $RepoRoot ".gitignore"
    Set-Content -Path $rootIgnore -Value $ignoreEntry -Encoding UTF8
    Write-Host "Created .gitignore at root with '$ignoreEntry'" -ForegroundColor Green
}
else {
    foreach ($gi in $gitignores) {
        $lines = @(Get-Content -Path $gi.FullName -ErrorAction SilentlyContinue)
        if ($lines -notcontains $ignoreEntry) {
            if ($PSCmdlet.ShouldProcess($gi.FullName, "Append '$ignoreEntry'")) {
                Add-Content -Path $gi.FullName -Value $ignoreEntry
                Write-Host "Updated $($gi.FullName)" -ForegroundColor Green
            }
        }
        else {
            Write-Host "$($gi.FullName) already ignores '$ignoreEntry'"
        }
    }
}

Write-Host "`nDone." -ForegroundColor Cyan