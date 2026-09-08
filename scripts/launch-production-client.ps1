<#
 # This file is part of Baritone.
 #
 # Baritone is free software: you can redistribute it and/or modify
 # it under the terms of the GNU Lesser General Public License as published by
 # the Free Software Foundation, either version 3 of the License, or
 # (at your option) any later version.
 #
 # Baritone is distributed in the hope that it will be useful,
 # but WITHOUT ANY WARRANTY; without even the implied warranty of
 # MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 # GNU Lesser General Public License for more details.
 #
 # You should have received a copy of the GNU Lesser General Public License
 # along with Baritone.  If not, see <https://www.gnu.org/licenses/>.
 #>

<#
.SYNOPSIS
Boots a PRODUCTION Fabric client with a Nylium universal jar installed.

.DESCRIPTION
A dev client cannot verify a universal jar: unimined runs the game in the `named` namespace while
the jar's modules are remapped to `intermediary`, and the kernel extracts a module at prelaunch,
after Fabric's dev remapping step has already run. So the client has to be a real one.

Reuses an existing vanilla installation read-only for libraries and assets, merges the Fabric
profile JSON from meta.fabricmc.net over the vanilla version JSON, extracts the Windows natives and
launches KnotClient against a scratch game directory. Copy the universal jar into
<GameDirectory>/mods before running.

.EXAMPLE
./scripts/launch-production-client.ps1 -MinecraftVersion 1.21.10 -LoaderVersion 0.16.9 `
    -GameDirectory C:\temp\client-1.21.10 -JavaExecutable C:\jdk-21\bin\java.exe
#>

param(
    [Parameter(Mandatory=$true)][string]$MinecraftVersion,
    [Parameter(Mandatory=$true)][string]$LoaderVersion,
    [Parameter(Mandatory=$true)][string]$GameDirectory,
    [Parameter(Mandatory=$true)][string]$JavaExecutable,
    [string]$VanillaRoot = "$env:APPDATA\.minecraft",
    [string]$ReadyPattern = 'Sound engine started',
    [int]$ReadyTimeoutSeconds = 420,
    [int]$LingerSeconds = 20,
    [switch]$ResolveOnly
)

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$libraryRoot = Join-Path $GameDirectory 'libraries'
$nativesDirectory = Join-Path $GameDirectory 'natives'
New-Item -ItemType Directory -Force -Path $GameDirectory, $libraryRoot, $nativesDirectory | Out-Null

function Get-Json([string]$url) {
    (New-Object System.Net.WebClient).DownloadString($url) | ConvertFrom-Json
}

function ConvertTo-MavenPath([string]$coordinate) {
    $parts = $coordinate.Split(':')
    $group = $parts[0].Replace('.', '/')
    $artifact = $parts[1]
    $version = $parts[2]
    $suffix = if ($parts.Count -gt 3) { "-$($parts[3])" } else { '' }
    "$group/$artifact/$version/$artifact-$version$suffix.jar"
}

# A library with no rules is unconditionally allowed; with rules, the last matching rule wins and an
# unmatched library is excluded, which is how the vanilla manifest expresses per-OS natives.
function Test-LibraryAllowed($library) {
    if (-not $library.PSObject.Properties['rules']) { return $true }
    $allowed = $false
    foreach ($rule in $library.rules) {
        $matchesRule = $true
        if ($rule.PSObject.Properties['os'] -and $rule.os.PSObject.Properties['name']) {
            $matchesRule = ($rule.os.name -eq 'windows')
        }
        if ($matchesRule) { $allowed = ($rule.action -eq 'allow') }
    }
    return $allowed
}

function Resolve-Library($library) {
    if ($library.PSObject.Properties['downloads'] -and $library.downloads.PSObject.Properties['artifact']) {
        return @{ Path = $library.downloads.artifact.path; Url = $library.downloads.artifact.url }
    }
    $path = ConvertTo-MavenPath $library.name
    $base = if ($library.PSObject.Properties['url'] -and $library.url) { $library.url } else { 'https://maven.fabricmc.net/' }
    return @{ Path = $path; Url = ($base.TrimEnd('/') + '/' + $path) }
}

$classpath = New-Object System.Collections.Generic.List[string]
$downloaded = 0
$reusedFromVanilla = 0
$nativeArchives = New-Object System.Collections.Generic.List[string]

# Keyed on group:artifact:classifier rather than the full coordinate, because Fabric's profile and
# the vanilla manifest both ship ASM at different versions and Fabric refuses to start with two on
# the classpath. Fabric's libraries are added first, so the child's version wins, which is the same
# precedence the vanilla launcher applies when merging an inheritsFrom profile.
$seenLibraryKeys = New-Object System.Collections.Generic.HashSet[string]

function Add-Libraries($libraries) {
    foreach ($library in $libraries) {
        if (-not (Test-LibraryAllowed $library)) { continue }
        $coordinate = $library.name.Split(':')
        $key = $coordinate[0] + ':' + $coordinate[1]
        if ($coordinate.Count -gt 3) { $key += ':' + $coordinate[3] }
        if (-not $seenLibraryKeys.Add($key)) { continue }
        $resolved = Resolve-Library $library
        $vanillaCopy = Join-Path $VanillaRoot ("libraries/" + $resolved.Path)
        $localCopy = Join-Path $libraryRoot $resolved.Path
        if (Test-Path $vanillaCopy) {
            $script:reusedFromVanilla++
            $jar = $vanillaCopy
        } elseif (Test-Path $localCopy) {
            $jar = $localCopy
        } else {
            New-Item -ItemType Directory -Force -Path (Split-Path $localCopy) | Out-Null
            (New-Object System.Net.WebClient).DownloadFile($resolved.Url, $localCopy)
            $script:downloaded++
            $jar = $localCopy
        }
        if ($classpath -notcontains $jar) { $classpath.Add($jar) }
        if ($library.name -match 'natives-windows') { $nativeArchives.Add($jar) }
    }
}

$vanilla = Get-Content (Join-Path $VanillaRoot "versions/$MinecraftVersion/$MinecraftVersion.json") -Raw | ConvertFrom-Json
$fabric = Get-Json "https://meta.fabricmc.net/v2/versions/loader/$MinecraftVersion/$LoaderVersion/profile/json"

Add-Libraries $fabric.libraries
Add-Libraries $vanilla.libraries

$clientJar = Join-Path $VanillaRoot "versions/$MinecraftVersion/$MinecraftVersion.jar"
if (-not (Test-Path $clientJar)) { throw "Vanilla client jar missing: $clientJar" }
$classpath.Add($clientJar)

foreach ($archive in $nativeArchives) {
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = [System.IO.Compression.ZipFile]::OpenRead($archive)
    try {
        foreach ($entry in $zip.Entries) {
            if ($entry.Name -like '*.dll') {
                $target = Join-Path $nativesDirectory $entry.Name
                if (-not (Test-Path $target)) {
                    [System.IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $target, $false)
                }
            }
        }
    } finally { $zip.Dispose() }
}

$assetIndex = $vanilla.assetIndex.id
$assetsDirectory = Join-Path $VanillaRoot 'assets'
if (-not (Test-Path (Join-Path $assetsDirectory "indexes/$assetIndex.json"))) {
    throw "Asset index $assetIndex is not present under $assetsDirectory; refusing to guess."
}

Write-Output "minecraft=$MinecraftVersion loader=$LoaderVersion mainClass=$($fabric.mainClass)"
Write-Output "classpath_entries=$($classpath.Count) reused_from_vanilla=$reusedFromVanilla downloaded=$downloaded natives=$($nativeArchives.Count)"
Write-Output "asset_index=$assetIndex"
if ($ResolveOnly) { return }

$argumentFile = Join-Path $GameDirectory 'launch-args.txt'
# Inside a java @argfile a backslash escapes the next character, so Windows paths must be written
# with forward slashes or the classpath silently arrives mangled.
$classpathArgument = (($classpath | ForEach-Object { $_.Replace('\', '/') }) -join ';')
$nativesArgument = $nativesDirectory.Replace('\', '/')
$gameArgument = $GameDirectory.Replace('\', '/')
$assetsArgument = $assetsDirectory.Replace('\', '/')
@(
    "-Xmx2G",
    "-Djava.library.path=`"$nativesArgument`"",
    "-Dmixin.debug.verbose=true",
    "-cp `"$classpathArgument`"",
    $fabric.mainClass,
    "--username Dev",
    "--version fabric-loader-$LoaderVersion-$MinecraftVersion",
    "--gameDir `"$gameArgument`"",
    "--assetsDir `"$assetsArgument`"",
    "--assetIndex $assetIndex",
    "--uuid 00000000000040008000000000000000",
    "--accessToken 0",
    "--userType legacy",
    "--versionType release"
) | Set-Content -Encoding ascii $argumentFile

$log = Join-Path $GameDirectory 'client.log'
if (Test-Path $log) { Remove-Item $log }

try { [Console]::InputEncoding = New-Object System.Text.UTF8Encoding $false } catch { }

$startInfo = New-Object System.Diagnostics.ProcessStartInfo
$startInfo.FileName = $JavaExecutable
$startInfo.Arguments = "@`"$argumentFile`""
$startInfo.WorkingDirectory = $GameDirectory
$startInfo.UseShellExecute = $false
$startInfo.RedirectStandardOutput = $true
$startInfo.RedirectStandardError = $false

$process = [System.Diagnostics.Process]::Start($startInfo)
$collected = New-Object System.Collections.Generic.List[string]
$ready = $false
$readyDeadline = (Get-Date).AddSeconds($ReadyTimeoutSeconds)
$lingerDeadline = [DateTime]::MaxValue
$pending = $null

while ($true) {
    if ($null -eq $pending) { $pending = $process.StandardOutput.ReadLineAsync() }
    if ($pending.Wait(1000)) {
        $line = $pending.Result
        $pending = $null
        if ($null -eq $line) { break }
        $collected.Add($line)
        if (-not $ready -and $line -match $ReadyPattern) {
            $ready = $true
            $lingerDeadline = (Get-Date).AddSeconds($LingerSeconds)
        }
    } else {
        $now = Get-Date
        if (-not $ready -and $now -gt $readyDeadline) {
            $collected.Add('[driver] ready timeout elapsed')
            break
        }
        if ($ready -and $now -gt $lingerDeadline) { break }
    }
}

$survivedLinger = -not $process.HasExited
if (-not $process.HasExited) { $process.Kill(); $process.WaitForExit(30000) | Out-Null }
$collected | Set-Content -Encoding utf8 $log

Write-Output "reached_ready=$ready"
Write-Output "alive_after_linger=$survivedLinger"
Write-Output "exit_code=$($process.ExitCode)"
Write-Output "log_lines=$($collected.Count)"
