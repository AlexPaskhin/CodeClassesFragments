[CmdletBinding()]
param(
    [string] $Root = (Get-Location).Path,

    [string] $SolutionName = $null
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$Root = (Resolve-Path $Root).Path

if ([string]::IsNullOrWhiteSpace($SolutionName)) {
    $SolutionName = "$(Split-Path $Root -Leaf).@"
}

$solutionPath = Join-Path $Root "$SolutionName.slnx"

Write-Host "Root: $Root"
Write-Host "Solution: $solutionPath"

function Get-RelativeUnixPath {
    param(
        [string] $From,
        [string] $To
    )

    $fromUri = [System.Uri]::new(
        ((Resolve-Path $From).Path.TrimEnd('\') + '\')
    )

    $toUri = [System.Uri]::new(
        (Resolve-Path $To).Path
    )

    $relative = $fromUri.MakeRelativeUri($toUri).ToString()
    return [System.Uri]::UnescapeDataString($relative).Replace('\', '/')
}

function Get-ProjectKey {
    param(
        [System.Xml.XmlElement] $ProjectFile,
        [string] $FilePath
    )

    $assemblyName = $ProjectFile.PropertyGroup.AssemblyName |
        Where-Object { $_ -and $_.'#text' } |
        Select-Object -First 1

    if ($assemblyName -and -not [string]::IsNullOrWhiteSpace($assemblyName.'#text')) {
        return $assemblyName.'#text'.Trim()
    }

    $fileName = [System.IO.Path]::GetFileNameWithoutExtension($FilePath)

    if ($fileName.EndsWith('.@')) {
        return $fileName.Substring(0, $fileName.Length - 2)
    }

    return $fileName
}

# Find original projects only. Generated *.@.csproj files are ignored.
$sourceProjects = @(
    Get-ChildItem `
        -Path $Root `
        -Recurse `
        -File `
        -Filter '*.csproj' |
    Where-Object {
        $_.FullName -notmatch '[\\/](bin|obj|\.git)[\\/]' -and
        $_.Name -notlike '*.@.csproj'
    }
)

if ($sourceProjects.Count -eq 0) {
    throw "No source *.csproj files were found below '$Root'."
}

Write-Host "Found $($sourceProjects.Count) source project(s)."

# Copy every project to *.@.csproj.
$generatedProjects = foreach ($sourceProject in $sourceProjects) {
    $targetName = "$($sourceProject.BaseName).@.csproj"
    $targetPath = Join-Path $sourceProject.DirectoryName $targetName

    Copy-Item `
        -LiteralPath $sourceProject.FullName `
        -Destination $targetPath `
        -Force

    Write-Host "Copied: $($sourceProject.FullName) -> $targetPath"

    Get-Item -LiteralPath $targetPath
}

# Build a lookup of project names to generated project files.
$projectLookup = @{}

foreach ($generatedProject in $generatedProjects) {
    [xml] $projectXml = Get-Content `
        -LiteralPath $generatedProject.FullName `
        -Raw

    $projectElement = $projectXml.DocumentElement
    $projectKey = Get-ProjectKey `
        -ProjectFile $projectElement `
        -FilePath $generatedProject.FullName

    $projectLookup[$projectKey] = $generatedProject

    # Also allow matching by the original file name.
    $originalProjectName = $generatedProject.BaseName -replace '\.@$', ''
    $projectLookup[$originalProjectName] = $generatedProject
}

# Replace matching PackageReference elements with ProjectReference elements.
foreach ($generatedProject in $generatedProjects) {
    [xml] $projectXml = Get-Content `
        -LiteralPath $generatedProject.FullName `
        -Raw

    $projectElement = $projectXml.DocumentElement
    $namespaceUri = $projectElement.NamespaceURI

    $packageReferences = @(
        $projectXml.SelectNodes(
            "//*[local-name()='PackageReference']"
        )
    )

    $replacementCount = 0

    foreach ($packageReference in $packageReferences) {
        $packageName = $packageReference.GetAttribute('Include')

        if ([string]::IsNullOrWhiteSpace($packageName)) {
            continue
        }

        if (-not $projectLookup.ContainsKey($packageName)) {
            continue
        }

        $targetProject = $projectLookup[$packageName]

        if ($targetProject.FullName -eq $generatedProject.FullName) {
            continue
        }

        $relativeProjectPath = Get-RelativeUnixPath `
            -From $generatedProject.DirectoryName `
            -To $targetProject.FullName

        $projectReference = $projectXml.CreateElement(
            'ProjectReference',
            $namespaceUri
        )

        # Preserve attributes such as Condition, but replace Include.
        foreach ($attribute in $packageReference.Attributes) {
            if ($attribute.Name -ne 'Include') {
                $projectReference.SetAttribute(
                    $attribute.Name,
                    $attribute.Value
                )
            }
        }

        $projectReference.SetAttribute(
            'Include',
            $relativeProjectPath
        )

        [void] $packageReference.ParentNode.ReplaceChild(
            $projectReference,
            $packageReference
        )

        $replacementCount++

        Write-Host (
            "Updated {0}: PackageReference '{1}' -> ProjectReference '{2}'" -f `
            $generatedProject.Name,
            $packageName,
            $relativeProjectPath
        )
    }

    if ($replacementCount -gt 0) {
        $settings = [System.Xml.XmlWriterSettings]::new()
        $settings.Indent = $true
        $settings.OmitXmlDeclaration = $false
        $settings.Encoding = [System.Text.UTF8Encoding]::new($false)

        $writer = [System.Xml.XmlWriter]::Create(
            $generatedProject.FullName,
            $settings
        )

        try {
            $projectXml.Save($writer)
        }
        finally {
            $writer.Dispose()
        }
    }
}

# Update every .gitignore below the root.
$gitignoreFiles = @(
    Get-ChildItem `
        -Path $Root `
        -Recurse `
        -File `
        -Filter '.gitignore' |
    Where-Object {
        $_.FullName -notmatch '[\\/](bin|obj)[\\/]'
    }
)

foreach ($gitignore in $gitignoreFiles) {
    $content = Get-Content `
        -LiteralPath $gitignore.FullName `
        -Raw

    $lines = @($content -split "`r?`n")

    if (-not ($lines -contains '*.@.csproj')) {
        $newContent = $content.TrimEnd() + [Environment]::NewLine + '*.@.csproj' + [Environment]::NewLine

        Set-Content `
            -LiteralPath $gitignore.FullName `
            -Value $newContent `
            -Encoding utf8

        Write-Host "Updated .gitignore: $($gitignore.FullName)"
    }
}

# Remove an old generated solution if present.
if (Test-Path -LiteralPath $solutionPath) {
    Remove-Item -LiteralPath $solutionPath -Force
}

# Create an empty SLNX solution.
& dotnet new sln `
    --name $SolutionName `
    --output $Root `
    --format slnx `
    --force

if ($LASTEXITCODE -ne 0) {
    throw "Failed to create '$solutionPath'."
}

# Add generated projects, grouping them by their relative directory.
foreach ($generatedProject in $generatedProjects) {
    $relativeDirectory = [System.IO.Path]::GetRelativePath(
        $Root,
        $generatedProject.DirectoryName
    )

    $relativeProjectPath = [System.IO.Path]::GetRelativePath(
        $Root,
        $generatedProject.FullName
    )

    $relativeDirectory = $relativeDirectory.Replace('\', '/')
    $relativeProjectPath = $relativeProjectPath.Replace('\', '/')

    if (
        [string]::IsNullOrWhiteSpace($relativeDirectory) -or
        $relativeDirectory -eq '.'
    ) {
        & dotnet sln $solutionPath add $relativeProjectPath
    }
    else {
        & dotnet sln $solutionPath add `
            $relativeProjectPath `
            --solution-folder $relativeDirectory
    }

    if ($LASTEXITCODE -ne 0) {
        throw "Failed to add '$relativeProjectPath' to '$solutionPath'."
    }
}

Write-Host ''
Write-Host 'Completed successfully.'
Write-Host "Generated projects: $($generatedProjects.Count)"
Write-Host "Generated solution: $solutionPath"