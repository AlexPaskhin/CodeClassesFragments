<#
.SYNOPSIS
    shadowSolutionV2 - Creates "shadow" .csproj copies (*.@.csproj) for every child-folder
    project, rewires references between them, strips legacy TargetFrameworks, ensures an
    AssemblyName, builds a grouped *.@.slnx, and keeps .gitignore files up to date.

.DESCRIPTION
    Run from the solution root. See inline #region blocks for each numbered requirement.
#>

[CmdletBinding()]
param(
    [string]$RootPath = (Get-Location).Path,
    [string]$SolutionName = (Split-Path -Leaf (Get-Location).Path),

    # Target framework monikers to strip out of <TargetFrameworks>
    [string[]]$ObsoleteFrameworks = @('net451','net452','net461','net462','netstandard2.0','netstandard2.1')
)

$ErrorActionPreference = 'Stop'
$ShadowSuffix = '.@.csproj'

#region 1. Find all child-folder *.csproj files
function Get-ChildProjectFiles {
    <#
        Finds every *.csproj that lives in a CHILD folder of $RootPath
        (i.e. excludes any .csproj sitting directly in the root itself).
    #>
    param([string]$Path = $RootPath)

    Get-ChildItem -Path $Path -Recurse -File -Filter '*.csproj' |
        Where-Object {
            $_.FullName -notlike "*$ShadowSuffix" -and
            $_.DirectoryName -ne (Resolve-Path $Path).Path
        }
}
#endregion

#region 3. Empty function - filter out projects by -like folder names
function Test-ProjectFolderExcluded {
    <#
        TODO: Fill in the -like patterns for folder names that should be
        excluded from shadow processing, e.g. 'tests', 'samples*', '*.Tests'.

        Return $true to EXCLUDE the project, $false to include it.
    #>
    param(
        [Parameter(Mandatory)][System.IO.FileInfo]$ProjectFile
    )

    $excludedFolderPatterns = @(
        'bin', 'obj', 'tests', '*.Tests', 'samples*'
    )

    foreach ($pattern in $excludedFolderPatterns) {
        if ($ProjectFile.DirectoryName -like $pattern) {
            return $true
        }
    }

    return $false
}
#endregion

#region 4. Empty function - map project name to alias package name
function Get-ProjectPackageAlias {
    <#
        TODO: Fill in the mapping of project name -> NuGet package name that
        this project should "shadow" (i.e. the PackageReference to replace
        with a ProjectReference to this project's shadow csproj).

        Return $null / empty string if the project has no alias package.
    #>
    param(
        [Parameter(Mandatory)][string]$ProjectName
    )

    $projectToPackageAlias = @{
        # 'MyCompany.Core'    = 'MyCompany.Core.Contracts'
        # 'MyCompany.Logging' = 'MyCompany.Logging.Abstractions'
    }

    if ($projectToPackageAlias.ContainsKey($ProjectName)) {
        return $projectToPackageAlias[$ProjectName]
    }

    return $null
}
#endregion

#region 2. Copy each project to *.@.csproj
function New-ShadowProjectFile {
    param([Parameter(Mandatory)][System.IO.FileInfo]$ProjectFile)

    $shadowName = "$([System.IO.Path]::GetFileNameWithoutExtension($ProjectFile.Name))$ShadowSuffix"
    $shadowPath = Join-Path $ProjectFile.DirectoryName $shadowName

    Copy-Item -Path $ProjectFile.FullName -Destination $shadowPath -Force
    Write-Verbose "Created shadow project: $shadowPath"

    return Get-Item $shadowPath
}
#endregion

#region 5. Update ProjectReference paths *.csproj -> *.@.csproj
function Update-ProjectReferencePaths {
    param([Parameter(Mandatory)][string]$ShadowProjectPath)

    $content = Get-Content -Path $ShadowProjectPath -Raw

    # Rewrite ProjectReference Include="...\Foo.csproj" -> "...\Foo.@.csproj"
    $updated = [regex]::Replace(
        $content,
        '(<ProjectReference\s+[^>]*Include\s*=\s*"[^"]*?)(?<!\.@)\.csproj(")',
        '$1.@.csproj$2'
    )

    if ($updated -ne $content) {
        Set-Content -Path $ShadowProjectPath -Value $updated -NoNewline
        Write-Verbose "Updated ProjectReference paths in: $ShadowProjectPath"
    }

    return $updated
}
#endregion

#region 6. Replace matching PackageReference entries with ProjectReference entries
function Update-PackageReferencesWithAliases {
    param(
        [Parameter(Mandatory)][string]$ShadowProjectPath,
        [Parameter(Mandatory)][System.Collections.IDictionary]$PackageToProjectMap
    )

    $content = Get-Content -Path $ShadowProjectPath -Raw

    foreach ($packageName in $PackageToProjectMap.Keys) {
        $targetShadowPath = $PackageToProjectMap[$packageName]

        $relativePath = [System.IO.Path]::GetRelativePath(
            (Split-Path $ShadowProjectPath -Parent),
            $targetShadowPath
        )

        # Match self-closing or open/close PackageReference tags for this package
        $pattern = '<PackageReference\s+[^>]*Include\s*=\s*"' + [regex]::Escape($packageName) + '"[^>]*?(/>|>.*?</PackageReference>)'
        $replacement = "<ProjectReference Include=`"$relativePath`" />"

        $content = [regex]::Replace($content, $pattern, { param($m) $replacement }, 'Singleline')
    }

    Set-Content -Path $ShadowProjectPath -Value $content -NoNewline
    Write-Verbose "Resolved package aliases in: $ShadowProjectPath"
}
#endregion

#region 7. Remove obsolete TargetFrameworks
function Remove-ObsoleteTargetFrameworks {
    param(
        [Parameter(Mandatory)][string]$ShadowProjectPath,
        [string[]]$Frameworks = $ObsoleteFrameworks
    )

    $content = Get-Content -Path $ShadowProjectPath -Raw

    # Multi-target: <TargetFrameworks>net6.0;net461;netstandard2.0</TargetFrameworks>
    $content = [regex]::Replace($content, '<TargetFrameworks>(.*?)</TargetFrameworks>', {
        param($m)
        $remaining = ($m.Groups[1].Value -split ';') |
            Where-Object { $_.Trim() -and ($Frameworks -notcontains $_.Trim()) }
        "<TargetFrameworks>$($remaining -join ';')</TargetFrameworks>"
    })

    # Single target: <TargetFramework>net461</TargetFramework>
    $content = [regex]::Replace($content, '<TargetFramework>(.*?)</TargetFramework>', {
        param($m)
        if ($Frameworks -contains $m.Groups[1].Value.Trim()) {
            Write-Warning "Project '$ShadowProjectPath' targets only an obsolete framework ('$($m.Groups[1].Value)'); leaving element in place for manual review."
        }
        $m.Value
    })

    Set-Content -Path $ShadowProjectPath -Value $content -NoNewline
    Write-Verbose "Removed obsolete TargetFrameworks in: $ShadowProjectPath"
}
#endregion

#region 8. Add AssemblyName if not already present
function Add-AssemblyNameIfMissing {
    param([Parameter(Mandatory)][string]$ShadowProjectPath)

    $content = Get-Content -Path $ShadowProjectPath -Raw

    if ($content -match '<AssemblyName>') {
        return
    }

    $assemblyName = [System.IO.Path]::GetFileNameWithoutExtension(
        [System.IO.Path]::GetFileNameWithoutExtension($ShadowProjectPath)  # strips both .@ and .csproj
    )

    # Insert into the first PropertyGroup found
    $updated = [regex]::Replace(
        $content,
        '(<PropertyGroup>)',
        "`$1`r`n    <AssemblyName>$assemblyName</AssemblyName>",
        1
    )

    Set-Content -Path $ShadowProjectPath -Value $updated -NoNewline
    Write-Verbose "Added AssemblyName '$assemblyName' to: $ShadowProjectPath"
}
#endregion

#region 9. Manually create a grouped *.@.slnx solution
function New-ShadowSlnx {
    param(
        [Parameter(Mandatory)][System.IO.FileInfo[]]$ShadowProjects,
        [Parameter(Mandatory)][string]$RootPath,
        [Parameter(Mandatory)][string]$SolutionName
    )

    $slnxPath = Join-Path $RootPath "$SolutionName.@.slnx"

    # Group projects by their immediate parent folder relative to root (solution folders)
    $groups = $ShadowProjects | Group-Object {
        $rel = [System.IO.Path]::GetRelativePath($RootPath, $_.DirectoryName)
        ($rel -split '[\\/]')[0]
    } | Sort-Object Name

    $sb = New-Object System.Text.StringBuilder
    [void]$sb.AppendLine('<Solution>')

    foreach ($group in $groups) {
        [void]$sb.AppendLine("  <Folder Name=`"/$($group.Name)/`">")
        foreach ($proj in ($group.Group | Sort-Object Name)) {
            $relPath = [System.IO.Path]::GetRelativePath($RootPath, $proj.FullName).Replace('\', '/')
            [void]$sb.AppendLine("    <Project Path=`"$relPath`" />")
        }
        [void]$sb.AppendLine('  </Folder>')
    }

    [void]$sb.AppendLine('</Solution>')

    Set-Content -Path $slnxPath -Value $sb.ToString() -NoNewline
    Write-Verbose "Created shadow solution: $slnxPath"

    return $slnxPath
}
#endregion

#region 10. Add *.@.csproj to every .gitignore
function Update-GitIgnoreFiles {
    param(
        [Parameter(Mandatory)][string]$RootPath,
        [string]$Pattern = "*$ShadowSuffix"
    )

    $gitIgnores = Get-ChildItem -Path $RootPath -Recurse -File -Filter '.gitignore' -Force

    if (-not $gitIgnores) {
        $rootGitIgnore = Join-Path $RootPath '.gitignore'
        Set-Content -Path $rootGitIgnore -Value $Pattern
        Write-Verbose "Created .gitignore with entry: $Pattern"
        return
    }

    foreach ($gitIgnore in $gitIgnores) {
        $lines = @()
        if (Test-Path $gitIgnore.FullName) {
            $lines = Get-Content -Path $gitIgnore.FullName
        }

        if ($lines -notcontains $Pattern) {
            Add-Content -Path $gitIgnore.FullName -Value $Pattern
            Write-Verbose "Added '$Pattern' to: $($gitIgnore.FullName)"
        }
    }
}
#endregion

#region Orchestration
function Invoke-ShadowSolutionV2 {
    param(
        [string]$RootPath = $RootPath,
        [string]$SolutionName = $SolutionName
    )

    Write-Host "Scanning for child-folder projects under: $RootPath"
    $allProjects = Get-ChildProjectFiles -Path $RootPath

    $includedProjects = $allProjects | Where-Object { -not (Test-ProjectFolderExcluded -ProjectFile $_) }

    if (-not $includedProjects) {
        Write-Warning "No projects found to process."
        return
    }

    Write-Host "Creating shadow projects (*$ShadowSuffix)..."
    $shadowProjects = foreach ($project in $includedProjects) {
        New-ShadowProjectFile -ProjectFile $project
    }

    # Build a lookup: package alias name -> shadow project full path
    $packageToProjectMap = @{}
    foreach ($shadow in $shadowProjects) {
        $projectName = [System.IO.Path]::GetFileNameWithoutExtension(
            [System.IO.Path]::GetFileNameWithoutExtension($shadow.FullName)
        )
        $alias = Get-ProjectPackageAlias -ProjectName $projectName
        if ($alias) {
            $packageToProjectMap[$alias] = $shadow.FullName
        }
    }

    Write-Host "Rewiring references and cleaning up shadow project files..."
    foreach ($shadow in $shadowProjects) {
        Update-ProjectReferencePaths -ShadowProjectPath $shadow.FullName
        Update-PackageReferencesWithAliases -ShadowProjectPath $shadow.FullName -PackageToProjectMap $packageToProjectMap
        Remove-ObsoleteTargetFrameworks -ShadowProjectPath $shadow.FullName
        Add-AssemblyNameIfMissing -ShadowProjectPath $shadow.FullName
    }

    Write-Host "Building grouped shadow solution..."
    $slnxPath = New-ShadowSlnx -ShadowProjects $shadowProjects -RootPath $RootPath -SolutionName $SolutionName

    Write-Host "Updating .gitignore files..."
    Update-GitIgnoreFiles -RootPath $RootPath

    Write-Host "Done. Shadow solution: $slnxPath"
}
#endregion

# Invoke-ShadowSolutionV2 -RootPath $RootPath -SolutionName $SolutionName