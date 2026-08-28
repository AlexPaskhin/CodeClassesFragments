<#
.SYNOPSIS
    Creates ".@" shadow copies of all child-folder *.csproj files, rewires references,
    strips net462, builds a grouped .@.slnx, and updates .gitignore files.

.DESCRIPTION
    1. Finds all *.csproj files in child folders (recursively, excluding the root itself).
    2. Copies each "Foo.csproj" to "Foo.@.csproj" alongside it.
    3. Inside every "*.@.csproj", rewrites existing <ProjectReference Include="...*.csproj">
       so the referenced path also points at the "*.@.csproj" version.
    4. Replaces any <PackageReference> whose Include matches a local project name with a
       <ProjectReference> pointing at that project's "*.@.csproj".
    5. Removes "net462" from <TargetFrameworks> (or clears <TargetFramework> if it IS net462).
    6. Manually builds a grouped "<RootFolderName>.@.slnx" listing every "*.@.csproj".
    7. Ensures "*.@.csproj" is present in every .gitignore found in the tree.

.PARAMETER RootPath
    Root folder to operate on. Defaults to current directory.

.EXAMPLE
    ./New-DotAtProjects.ps1 -RootPath C:\src\MySolution
#>

[CmdletBinding()]
param(
    [string]$RootPath = (Get-Location).Path
)

$ErrorActionPreference = 'Stop'
$RootPath = (Resolve-Path $RootPath).Path

function Get-AtCsprojName {
    param([string]$OriginalFileName)
    # Foo.csproj -> Foo.@.csproj
    return ($OriginalFileName -replace '\.csproj$', '.@.csproj')
}

# ---------------------------------------------------------------------------
# Step 1: Find all child-folder *.csproj files (skip anything already "*.@.csproj",
# and skip files sitting directly in the root path — only child folders count).
# ---------------------------------------------------------------------------
$allCsproj = Get-ChildItem -Path $RootPath -Recurse -Filter *.csproj -File |
    Where-Object {
        $_.Name -notlike '*.@.csproj' -and
        (Split-Path $_.DirectoryName -Leaf) -and
        $_.DirectoryName -ne $RootPath
    }

if (-not $allCsproj) {
    Write-Warning "No child-folder *.csproj files found under '$RootPath'."
    return
}

Write-Host "Found $($allCsproj.Count) project file(s)."

# Lookup table: project base name (no extension) -> hashtable of paths, for cross-referencing.
$projectMap = @{}
foreach ($proj in $allCsproj) {
    $baseName = [System.IO.Path]::GetFileNameWithoutExtension($proj.Name)
    $atName   = Get-AtCsprojName $proj.Name
    $atPath   = Join-Path $proj.DirectoryName $atName

    $projectMap[$baseName] = [pscustomobject]@{
        BaseName     = $baseName
        OriginalPath = $proj.FullName
        AtPath       = $atPath
    }
}

# ---------------------------------------------------------------------------
# Step 2: Copy each *.csproj to *.@.csproj
# ---------------------------------------------------------------------------
foreach ($entry in $projectMap.Values) {
    Copy-Item -Path $entry.OriginalPath -Destination $entry.AtPath -Force
    Write-Host "Copied: $($entry.OriginalPath) -> $($entry.AtPath)"
}

# ---------------------------------------------------------------------------
# Helper: compute a relative path (MSBuild-style, backslashes) between two files.
# ---------------------------------------------------------------------------
function Get-RelativeProjectPath {
    param(
        [string]$FromDirectory,
        [string]$ToFile
    )
    $fromUri = New-Object System.Uri(($FromDirectory.TrimEnd('\') + '\'))
    $toUri   = New-Object System.Uri($ToFile)
    $rel     = $fromUri.MakeRelativeUri($toUri).ToString()
    $rel     = [System.Uri]::UnescapeDataString($rel) -replace '/', '\'
    return $rel
}

# ---------------------------------------------------------------------------
# Steps 3, 4, 5: Edit each *.@.csproj's XML content.
# ---------------------------------------------------------------------------
$xmlNamespace = 'http://schemas.microsoft.com/developer/msbuild/2003'

foreach ($entry in $projectMap.Values) {
    [xml]$xml = Get-Content -Path $entry.AtPath -Raw
    $projDir  = Split-Path $entry.AtPath -Parent
    $changed  = $false

    # --- Step 3: update existing ProjectReference Include paths to *.@.csproj ---
    $projRefs = $xml.SelectNodes("//*[local-name()='ProjectReference']")
    foreach ($pr in @($projRefs)) {
        $include = $pr.GetAttribute('Include')
        if ($include -and $include -like '*.csproj' -and $include -notlike '*.@.csproj') {
            $newInclude = $include -replace '\.csproj$', '.@.csproj'
            $pr.SetAttribute('Include', $newInclude)
            $changed = $true
            Write-Host "  [3] $($entry.BaseName): ProjectReference '$include' -> '$newInclude'"
        }
    }

    # --- Step 4: replace matching PackageReference entries with ProjectReference ---
    $pkgRefs = $xml.SelectNodes("//*[local-name()='PackageReference']")
    foreach ($pkg in @($pkgRefs)) {
        $pkgName = $pkg.GetAttribute('Include')
        if (-not $pkgName) { $pkgName = $pkg.GetAttribute('Update') }
        if ($pkgName -and $projectMap.ContainsKey($pkgName)) {
            $target      = $projectMap[$pkgName]
            $relPath     = Get-RelativeProjectPath -FromDirectory $projDir -ToFile $target.AtPath

            $newNode = $xml.CreateElement('ProjectReference', $pkg.NamespaceURI)
            $newNode.SetAttribute('Include', $relPath)

            $pkg.ParentNode.ReplaceChild($newNode, $pkg) | Out-Null
            $changed = $true
            Write-Host "  [4] $($entry.BaseName): PackageReference '$pkgName' -> ProjectReference '$relPath'"
        }
    }

    # --- Step 5: remove net462 from TargetFrameworks ---
    $tfmsNode = $xml.SelectSingleNode("//*[local-name()='TargetFrameworks']")
    if ($tfmsNode -and $tfmsNode.InnerText -match 'net462') {
        $remaining = ($tfmsNode.InnerText -split ';' |
            Where-Object { $_.Trim() -ne 'net462' -and $_.Trim() -ne '' }) -join ';'
        $tfmsNode.InnerText = $remaining
        $changed = $true
        Write-Host "  [5] $($entry.BaseName): TargetFrameworks -> '$remaining'"
    }

    $tfmNode = $xml.SelectSingleNode("//*[local-name()='TargetFramework']")
    if ($tfmNode -and $tfmNode.InnerText.Trim() -eq 'net462') {
        Write-Warning "  [5] $($entry.BaseName): single TargetFramework is net462 — leaving as-is (would empty the project). Review manually."
    }

    if ($changed) {
        $xml.Save($entry.AtPath)
    }
}

# ---------------------------------------------------------------------------
# Step 6: Manually build a grouped *.@.slnx solution file.
# Groups projects by their immediate parent folder name (solution folders).
# ---------------------------------------------------------------------------
$solutionName = (Split-Path $RootPath -Leaf) + '.@.slnx'
$solutionPath = Join-Path $RootPath $solutionName

$groups = $projectMap.Values | Group-Object { Split-Path (Split-Path $_.AtPath -Parent) -Leaf }

$sb = New-Object System.Text.StringBuilder
[void]$sb.AppendLine('<Solution>')
foreach ($group in $groups | Sort-Object Name) {
    [void]$sb.AppendLine("  <Folder Name=""/$($group.Name)/"">")
    foreach ($entry in $group.Group | Sort-Object BaseName) {
        $relToSln = Get-RelativeProjectPath -FromDirectory $RootPath -ToFile $entry.AtPath
        [void]$sb.AppendLine("    <Project Path=""$relToSln"" />")
    }
    [void]$sb.AppendLine('  </Folder>')
}
[void]$sb.AppendLine('</Solution>')

Set-Content -Path $solutionPath -Value $sb.ToString() -Encoding UTF8
Write-Host "Created solution: $solutionPath"

# ---------------------------------------------------------------------------
# Step 7: Add *.@.csproj to every .gitignore under RootPath (create root one if none exist).
# ---------------------------------------------------------------------------
$ignoreEntry   = '*.@.csproj'
$gitignoreFiles = Get-ChildItem -Path $RootPath -Recurse -Filter '.gitignore' -File -ErrorAction SilentlyContinue

if (-not $gitignoreFiles) {
    $rootGitignore = Join-Path $RootPath '.gitignore'
    Set-Content -Path $rootGitignore -Value $ignoreEntry -Encoding UTF8
    Write-Host "Created .gitignore: $rootGitignore"
} else {
    foreach ($gi in $gitignoreFiles) {
        $lines = @(Get-Content -Path $gi.FullName -ErrorAction SilentlyContinue)
        if ($lines -notcontains $ignoreEntry) {
            Add-Content -Path $gi.FullName -Value $ignoreEntry
            Write-Host "Updated .gitignore: $($gi.FullName)"
        } else {
            Write-Host "Already present in: $($gi.FullName)"
        }
    }
}

Write-Host "`nDone. Processed $($projectMap.Count) project(s)."