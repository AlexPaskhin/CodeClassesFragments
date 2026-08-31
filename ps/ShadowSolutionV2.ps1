<#
.SYNOPSIS
    ShadowSolutionV2 - Creates shadow (*.@.csproj) copies of all child project files,
    rewires references between them, strips legacy target frameworks, ensures an
    AssemblyName is set, builds a grouped shadow *.@.slnx solution, and updates
    every .gitignore to exclude the generated shadow files.

.DESCRIPTION
    Run this script from the solution root. It operates on all *.csproj files found
    in child folders (recursively).

.NOTES
    Requires PowerShell 5.1+ (uses [xml] for csproj manipulation).
#>

[CmdletBinding()]
param(
    [string]$RootPath = (Get-Location).Path,

    # Name of the grouped shadow solution file that will be created (without extension).
    [string]$SlnxName = 'Solution.@',

    # Frameworks to strip from every TargetFramework(s) element.
    [string[]]$FrameworksToRemove = @(
        'net451','net452','net461','net462','netstandard2.0','netstandard2.1'
    )
)

$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# 3. Empty filter function - customize -like patterns here to exclude folders
#    (case-insensitive). Return $true to EXCLUDE a project.
# ---------------------------------------------------------------------------
function Test-ExcludedFolder {
    param(
        [Parameter(Mandatory)][string]$FolderName
    )

    # Add -like patterns below, e.g.:
    # $excludePatterns = @('*obj*', '*bin*', '*test*')
    $excludePatterns = @()

    foreach ($pattern in $excludePatterns) {
        if ($FolderName -like $pattern) {
            return $true
        }
    }

    return $false
}

# ---------------------------------------------------------------------------
# 1. Find all *.csproj files in child folders (skip already-shadowed files)
# ---------------------------------------------------------------------------
function Get-SourceProjects {
    param([string]$Root)

    Get-ChildItem -Path $Root -Recurse -Filter '*.csproj' -File |
        Where-Object {
            $_.Name -notlike '*.@.csproj' -and
            -not (Test-ExcludedFolder -FolderName $_.Directory.Name)
        }
}

# ---------------------------------------------------------------------------
# 2. Copy each project to *.@.csproj
# ---------------------------------------------------------------------------
function Copy-ShadowProject {
    param([System.IO.FileInfo]$SourceFile)

    $shadowName = "$($SourceFile.BaseName).@.csproj"
    $shadowPath = Join-Path $SourceFile.DirectoryName $shadowName

    Copy-Item -Path $SourceFile.FullName -Destination $shadowPath -Force
    return Get-Item $shadowPath
}

# ---------------------------------------------------------------------------
# 4. In ProjectReference entries, update *.csproj -> *.@.csproj
# ---------------------------------------------------------------------------
function Update-ProjectReferences {
    param([xml]$Xml)

    $refs = $Xml.SelectNodes('//ProjectReference')
    foreach ($ref in $refs) {
        $include = $ref.GetAttribute('Include')
        if ([string]::IsNullOrWhiteSpace($include)) { continue }
        if ($include -like '*.csproj' -and $include -notlike '*.@.csproj') {
            $newInclude = $include -replace '\.csproj$', '.@.csproj'
            $ref.SetAttribute('Include', $newInclude)
        }
    }
}

# ---------------------------------------------------------------------------
# 5. Replace matching PackageReference entries with ProjectReference entries
#    A PackageReference is "matching" if its Include name equals the
#    AssemblyName/project name of one of the discovered shadow projects.
# ---------------------------------------------------------------------------
function Convert-PackageReferenceToProjectReference {
    param(
        [xml]$Xml,
        [System.IO.FileInfo]$ShadowProjectFile,
        [hashtable]$ProjectNameMap   # Name -> shadow .csproj full path
    )

    $packageRefs = @($Xml.SelectNodes('//PackageReference'))
    foreach ($pkgRef in $packageRefs) {
        $pkgName = $pkgRef.GetAttribute('Include')
        if ([string]::IsNullOrWhiteSpace($pkgName)) { continue }

        if ($ProjectNameMap.ContainsKey($pkgName)) {
            $targetShadowPath = $ProjectNameMap[$pkgName]
            $relativePath = Resolve-RelativePath -From $ShadowProjectFile.DirectoryName -To $targetShadowPath

            $itemGroup = $pkgRef.ParentNode
            $projRef = $Xml.CreateElement('ProjectReference')
            $projRef.SetAttribute('Include', $relativePath)
            $itemGroup.ReplaceChild($projRef, $pkgRef) | Out-Null
        }
    }
}

function Resolve-RelativePath {
    param([string]$From, [string]$To)

    $fromUri = New-Object System.Uri(($From.TrimEnd('\') + '\'))
    $toUri = New-Object System.Uri($To)
    $relativeUri = $fromUri.MakeRelativeUri($toUri)
    return ([System.Uri]::UnescapeDataString($relativeUri.ToString())) -replace '/', '\'
}

# ---------------------------------------------------------------------------
# 6. Remove legacy target frameworks
# ---------------------------------------------------------------------------
function Remove-TargetFrameworks {
    param([xml]$Xml, [string[]]$Frameworks)

    foreach ($tag in @('TargetFrameworks', 'TargetFramework')) {
        $nodes = $Xml.SelectNodes("//$tag")
        foreach ($node in $nodes) {
            $values = $node.InnerText -split ';' | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' }
            $filtered = $values | Where-Object {
                $current = $_
                -not ($Frameworks | Where-Object { $current -ieq $_ })
            }

            if ($filtered.Count -eq 0) {
                $node.ParentNode.RemoveChild($node) | Out-Null
            }
            elseif ($tag -eq 'TargetFrameworks' -and $filtered.Count -eq 1) {
                # Collapse to single TargetFramework element
                $newNode = $Xml.CreateElement('TargetFramework')
                $newNode.InnerText = $filtered[0]
                $node.ParentNode.ReplaceChild($newNode, $node) | Out-Null
            }
            else {
                $node.InnerText = ($filtered -join ';')
            }
        }
    }
}

# ---------------------------------------------------------------------------
# 7. Add AssemblyName if missing
# ---------------------------------------------------------------------------
function Add-AssemblyNameIfMissing {
    param([xml]$Xml, [string]$DefaultName)

    $existing = $Xml.SelectSingleNode('//AssemblyName')
    if (-not $existing) {
        $propertyGroup = $Xml.SelectSingleNode('//PropertyGroup')
        if (-not $propertyGroup) {
            $propertyGroup = $Xml.CreateElement('PropertyGroup')
            $Xml.Project.AppendChild($propertyGroup) | Out-Null
        }
        $asmName = $Xml.CreateElement('AssemblyName')
        $asmName.InnerText = $DefaultName
        $propertyGroup.AppendChild($asmName) | Out-Null
    }
}

# ---------------------------------------------------------------------------
# 8. Build grouped *.@.slnx solution manually
# ---------------------------------------------------------------------------
function New-ShadowSlnx {
    param(
        [string]$Root,
        [string]$SlnxName,
        [System.IO.FileInfo[]]$ShadowProjects
    )

    $slnxPath = Join-Path $Root "$SlnxName.slnx"

    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine('<Solution>')

    $grouped = $ShadowProjects | Group-Object { $_.Directory.Parent.Name }

    foreach ($group in $grouped) {
        $folderName = $group.Name
        [void]$sb.AppendLine("  <Folder Name=""/$folderName/"">")
        foreach ($proj in $group.Group) {
            $relPath = Resolve-RelativePath -From $Root -To $proj.FullName
            [void]$sb.AppendLine("    <Project Path=""$relPath"" />")
        }
        [void]$sb.AppendLine('  </Folder>')
    }

    [void]$sb.AppendLine('</Solution>')

    Set-Content -Path $slnxPath -Value $sb.ToString() -Encoding UTF8
    Write-Host "Created shadow solution: $slnxPath"
}

# ---------------------------------------------------------------------------
# 9. Add *.@.csproj to every .gitignore (create root .gitignore if none exist)
# ---------------------------------------------------------------------------
function Update-GitIgnoreFiles {
    param([string]$Root)

    $entry = '*.@.csproj'
    $gitignores = @(Get-ChildItem -Path $Root -Recurse -Filter '.gitignore' -File)

    if ($gitignores.Count -eq 0) {
        $rootGitIgnore = Join-Path $Root '.gitignore'
        Set-Content -Path $rootGitIgnore -Value $entry -Encoding UTF8
        Write-Host "Created .gitignore: $rootGitIgnore"
        return
    }

    foreach ($gi in $gitignores) {
        $lines = @(Get-Content -Path $gi.FullName -ErrorAction SilentlyContinue)
        if (-not ($lines -contains $entry)) {
            Add-Content -Path $gi.FullName -Value $entry
            Write-Host "Updated .gitignore: $($gi.FullName)"
        }
    }
}

# ===========================================================================
# MAIN
# ===========================================================================

Write-Host "ShadowSolutionV2 starting in: $RootPath"

$sourceProjects = Get-SourceProjects -Root $RootPath
if ($sourceProjects.Count -eq 0) {
    Write-Warning "No source *.csproj files found."
    return
}

# Pass 1: copy all shadow projects and build name -> shadow path map
$shadowProjects = New-Object System.Collections.Generic.List[System.IO.FileInfo]
$projectNameMap = @{}

foreach ($src in $sourceProjects) {
    $shadow = Copy-ShadowProject -SourceFile $src
    $shadowProjects.Add($shadow)
    $projectNameMap[$src.BaseName] = $shadow.FullName
}

# Pass 2: edit each shadow project's XML content
foreach ($shadow in $shadowProjects) {
    [xml]$xml = Get-Content -Path $shadow.FullName -Raw

    Update-ProjectReferences -Xml $xml
    Convert-PackageReferenceToProjectReference -Xml $xml -ShadowProjectFile $shadow -ProjectNameMap $projectNameMap
    Remove-TargetFrameworks -Xml $xml -Frameworks $FrameworksToRemove

    $defaultAssemblyName = $shadow.BaseName -replace '\.@$', ''
    Add-AssemblyNameIfMissing -Xml $xml -DefaultName $defaultAssemblyName

    $xml.Save($shadow.FullName)
    Write-Host "Processed shadow project: $($shadow.FullName)"
}

# Step 8: grouped shadow slnx
New-ShadowSlnx -Root $RootPath -SlnxName $SlnxName -ShadowProjects $shadowProjects

# Step 9: gitignore updates
Update-GitIgnoreFiles -Root $RootPath

Write-Host "ShadowSolutionV2 complete."