# Nugetizer.2019.10.19 Version

<#
    .SYNOPSIS
        Idempotent initialization of nuget packages to work with Unity's Assembly Definitions
    .DESCRIPTION
        This is invoked automatically for each package by our restore_packages.bat. It's also
        invoked by Visual Studio both more and less frequently than one would prefer.
    .NOTES
        Variables named "Dir" are absolute or relative to CD. Variables named "Folder" are relative
        to their parent, i.e. it's just the name of the folder

        It extracts the package to transform this directory structure:
        /...                                    $nugetParentDir
          /nuget_packages                       $nugetRootDir
            /source                             $nugetSourceDir
              /packagename.version              $installPath
                /lib                            ($libFolder)
                  /netversion                   ($netVersionFolder)
                    /Runtime/...                $runtimeSourceDir
                    /Editor/...                 $editorSourceDir
                    /Foundation/...             $foundationSourceDir
                  /native                       $nativeSourceDir, ($nativeFolder)
                /tools                          $toolsPath, ideally...

        Into this directory structure:
        /...                                    $nugetParentDir
          /Runtime
            /nuget                              $runtimeDestinationDir, ($outputNugetFolder)
              /packagename.version/...
          /Editor
            /nuget                              $editorDestinationDir, ($outputNugetFolder)
              /packagename.version/...
          /nuget_packages                       $nugetRootDir
            /Foundation                         $foundationDestinationDir
              /packagename.version/...

        The init.ps1 contained in VTUE also installs assembly definitions for these packages.
#>

param($installPath, $toolsPath, $package, [switch]$verbose, [switch]$interactive)
Set-StrictMode -Version 1.0

$alwaysDebug = $false # change to $true for more logging and pausing

# TODO: Sure would be nice to derive these, instead of hard-coding these assumptions...
$nugetRootFolder = "nuget_packages"     # parse from nuget.config at runtime?
$nugetPackageSourceDir = ""             # parse from nuget.config at runtime?

$libFolder = "lib"                      # parse from nuspec at build time?
$netVersionFolder = "net46"             # parse from nuspec at build time?
$nativeFolder = "native"                # parse from nuspec at build time?
$nugetOutputFolder = "nuget"
$logFile = ".\vtnuget-logs\vtnuget.install.log"      # this is fine. Could include packageName, parsed at build-time (e.g. from name of nuSpec)

function Main() {

    $packageName = Split-Path -Leaf $installPath

    if ([String]::IsNullOrWhitespace($packageName)) {
        $packageName = Split-Path -Leaf (Split-Path -Parent $PSScriptRoot)
    }

    if ([String]::IsNullOrWhitespace($packageName)) {
        log "*** Invalid Arguments to Script $($PSScriptRoot)/$($MyInvocation.ScriptName)! I cannot even figure out what `$packageName is supposed to be... " -AsError
        exit 1
    }

    $filesToInit = Count-PackageFiles
    if ($filesToInit -eq 0) {
        echo "* Package $packageName has nothing to initialize. Exiting."
        exit 0
    }

    Configure-Log

    # these spaces makes print-f debugging saner
    log ""
    log "* Package $packageName - init.ps1 started at $(Get-Date -Format o)"
    log "  Parameters Received:" -Debug
    log "    `$installPath:   $installPath" -Debug
    log "    `$toolspath:     $toolsPath" -Debug
    log "    `$package:       $package" -Debug
    log "    `$verbose:       $verbose" -Debug
    log "    `$interactive:   $interactive" -Debug

    if ($package -ne "NuGet.PackageManagement.VThera.ScriptPackage") {
        log "Hey! Listen! - Initializing packages with Visual Studio isn't supported yet.  Please run restore_packages.bat"
        exit 2
    }

    Debug-Pause

    log "  * Initializing $packageName NuGet Package..."

    $nugetRootDir, $packageSourceDir = Find-NugetDirs($installPath)
    $nugetParentDir = (Split-Path -Path $nugetRootDir)

    $runtimeSourceDir = [IO.Path]::Combine($installPath, $libFolder, $netVersionFolder, "Runtime")
    $editorSourceDir = [IO.Path]::Combine($installPath, $libFolder, $netVersionFolder, "Editor")
    $foundationSourceDir = [IO.Path]::Combine($installPath, $libFolder, $netVersionFolder, "Foundation")
    $nativeSourceDir = [IO.Path]::Combine($installPath, $libFolder, $nativeFolder)

    $runtimeDestinationDir = [IO.Path]::Combine($nugetParentDir, "Runtime", $nugetOutputFolder)
    $editorDestinationDir = [IO.Path]::Combine($nugetParentDir, "Editor", $nugetOutputFolder)
    $foundationDestinationDir = [IO.Path]::Combine($nugetRootDir, "Foundation", $nugetOutputFolder) # yes, this one is intentionally different

    #This is done by everyone:
    Move-DirContents $runtimeSourceDir $runtimeDestinationDir $packageName
    Move-DirContents $editorSourceDir $editorDestinationDir $packageName
    Move-DirContents $foundationSourceDir $foundationDestinationDir $packageName
    Move-DirContents $nativeSourceDir $runtimeDestinationDir $packageName
	
	#SteamVR needs action input files moved to the root directory
	Move-SteamVR-Files $runtimeDestinationDir $nugetParentDir

    # TODO: check to see if any files are left behind and if so indicate that something's bad about the package?

    Debug-Pause

    log "- init.ps1 completed - $packageName"

    $archivedLog = "$([io.path]::GetFileNameWithoutExtension("$logFile")).$(Get-Date -Format FileDateTimeUniversal)$([io.path]::GetExtension("$logFile"))"
    Move-Item "$logFile" (Join-Path (Split-Path $logFile -Parent) "$archivedLog")

    if ($alwaysDebug -eq $true -or $verbose.IsPresent) {
        echo "  this logFile is archived as $archivedLog"
    }

    log ""
}

function Move-SteamVR-Files($sourceDir, $parentDir) {
	
	$items = @("actions.json",
			   "bindings_holographic_controller.json",
			   "bindings_knuckles.json",
			   "bindings_oculus_touch.json",
			   "bindings_vive_controller.json")

	$folders = get-ChildItem $sourceDir -recurse | where {$_.name -like "com.vthera.vrtk*"} | select name
	
	foreach ($folder in $folders.Name) {
		$sourcePath = "$sourceDir\$folder\SteamVR_VRTK_Actions\1\"
		if((Test-Path $sourcePath) -eq $False){
			continue
		}
		$assetsFolder = (Split-Path -Path $parentDir)
		$assetsParent = (Split-Path -Path $assetsFolder)
		
		foreach ($item in $items) {
			$itemPath = "$sourcePath\$item"
			$destPath = "$assetsParent\$item"
			if((Test-Path $destPath) -eq $False)
			{
				Copy-Item -Path $itemPath -Destination $assetsParent
			}
		}
	}
}

function Count-PackageFiles() {
    $filesToInit = 0
    foreach ($dirEntry in Get-ChildItem (Join-Path $installPath $libFolder) -Recurse -Force -File -Exclude *.meta) {
        $filesToInit += 1
    }
    return $filesToInit
}

#### TODO: Maybe this could be read from the nuget.config file? or query nuget repositoryPath / use default
function Find-NugetDirs($installPath) {
    # find the root nuget package directory
    $nugetRootDir = $installPath
    $stopFolder = Split-Path -Leaf $nugetRootDir

    $counter = 0
    # if it's not this directory, keep looking upwards for it.
    while($stopFolder -ne $nugetRootFolder -or [String]::IsNullOrWhitespace($stopFolder)) {
        $nugetRootDir = Split-Path -Path $nugetRootDir
        $stopFolder = Split-Path -Leaf $nugetRootDir
        $counter = $counter + 1
        if ($counter -gt 255) {
            break;
        }
    }

    if ($stopFolder -eq "" -or $stopFolder -eq $null -or -$counter -ge 255) {
        log "*** Malformed Package! Cannot find '$nugetRootName' directory as parent of $installPath (after $counter searches)" -AsError
        exit 1
    }

    $packageSourceDir = Join-Path $nugetRootDir $stopFolder
    return $nugetRootDir, $packageSourceDir
}

function Move-DirContents($sourceDir, $destinationDir, $packageName) {
    $shortSrc, $shortDest = Get-LoggableNames $sourceDir $destinationDir $packageName

    # Are there any files to move?
    if (!(Test-Path $sourceDir) -or ((Get-ChildItem $sourceDir | Measure-Object).Count) -eq 0) {
        log "    - $shortSrc is not present in this package" -Debug
        return
    }

    $outputDir = (Join-Path $destinationDir $packageName)

    log "    * Copying $shortSrc to $shortDest"
    log "    * $sourceDir -->" -Debug
    log "        $outputDir" -Debug
    Debug-Pause

    # Simple/Fast option: outputDir does not exist at all.
    if (!(Test-Path $outputDir)) {

        # Ensure parent directory exists
        if (!(Test-Path $destinationDir)) {
            New-Item $destinationDir -ItemType Directory | Out-Null
        }

        # Just copy the whole folder over into parent, and then rename it
        Move-Item -Path $sourceDir -Destination $destinationDir -PassThru | Rename-Item -Force -NewName $packageName

    } else {
        # Hard-mode. We have to merge the contents of these directories. Don't allow *file* collisions:
        # we'll call those malformed packages.

        # For every file in all subdirectories of source: move it to where it's supposed to go.
        foreach ($dirEntry in Get-ChildItem $sourceDir -Force -Recurse -File) {

            # Why am I manipulating strings like this I hate everything ='(
            $destFile = ($dirEntry.FullName).substring($dirEntry.FullName.indexOf($sourceDir) + $sourceDir.Length + 1)

            # This is gross too =''(
            $finalDestination = Join-Path $outputDir $destFile
            $ultimateDir = Split-Path $finalDestination # fox only, no items

            if (!(Test-Path $ultimateDir)) {
                New-Item $ultimateDir -ItemType Directory | Out-Null
            }

            Move-Item -Path $dirEntry.FullName -Destination $finalDestination
        }

        # In retrospect, it would've been nice to implement this in terms of the above when possible?
        # Or, at the very least, clean up all the folders we've left behind...
        $leftOvers = 0
        foreach ($dirEntry in Get-ChildItem $sourceDir -Force -Recurse -File) {
            $leftOvers += 1
        }
        if ($leftOvers -eq 0) {
            foreach ($dirEntry in Get-ChildItem $sourceDir -Force -Directory) {
                Remove-Item $($dirEntry.FullName) -Recurse -Force
            }
        }
    }
}

function Get-LoggableNames($sourceDir, $destinationDir, $packageName) {
    $shortSource = Splice-Path $sourceDir $nugetRootFolder
    $shortDest = Splice-Path $destinationDir $nugetParentDir -IncludeParent

    return $shortSource, (Join-Path $shortDest $packageName)
}

function Splice-Path($path, $ancestor, [switch]$includeParent) {
    # Split into folders, find first index of ancestor, and return the rest from there...
    $folders = $path.Split([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
    $ancestors = $ancestor.Split([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)

    $index = 0
    $ancestorMatch = $false
    while ($ancestorMatch -eq $false -and $index -lt $folders.Count) {
        if ($folders[$index] -eq $ancestors[$ancestors.Count-1]) {
            $ancestorMatch = $true
            for ($i = 1; $i -lt $ancestors.Count-1; $i += 1) {
                $ancestors = $ancestors -and $folders[$index-$i] -eq $ancestors[$ancestors.Count-1-$i]
            }
        }
        $index += 1
    }

    $startIndex = $index
    if ($includeParent.IsPresent -and $index -gt 0) {
        $startIndex = $index - 1
    }

    $result = $folders[$startIndex]
    for ($i = $startIndex+1; $i -lt $folders.Count; $i += 1) {
        $result = Join-Path $result $folders[$i]
    }

    return $result
}

function Configure-Log() {
    $orig = $logFile
    if ($PSScriptRoot -eq "") {
        $PSScriptRoot = "."
    }
    $fallBacks = @($(Join-Path $PWD "vtnuget.install.log"), $(Join-Path $($PSScriptRoot) "vtnuget.install.log"), $(Join-Path $HOME "vtnuget.install.log"), $(Join-Path $env:TEMP "vtnuget.install.log") )
    $fallBackIndex = 0
    $success = $false

    Do {
        # The code for doing this the "correct" way is literally hundreds of lines long: https://www.powershellgallery.com/packages/Carbon/2.2.0/Content/Functions%5CTest-Permission.ps1
        Try {
            $logdir = Split-Path "$logFile" -Parent
            if (!(Test-Path $logdir)) {
                New-Item $logdir -ItemType Directory | Out-Null
            }
            [io.file]::OpenWrite($logFile).close()
        } Catch {
            $script:logFile = $fallBacks[$fallBackIndex]
            $fallBackIndex += 1;
        }
        $success = $true
    } While ($success -ne $true -and $fallBackIndex -lt $fallBacks.Count)

    if ($success -ne $true) {
        $script:logFile = $null
        log "!!! Unable to log this output to a file."
    } else {
        log "Logging to file $(Resolve-Path $logFile)"
        if ($fallBackIndex -gt 0) {
            log "    (Unable to write to $(Resolve-Path $orig) due to errors.)"
        }
    }
}

function log() {
    param(
        [string]$msg,
        [switch]$Debug,
        [switch]$AsError
    )

    if ($AsError.IsPresent) {
        Write-Error "$msg"
    } elseif ($alwaysDebug -eq $true -or $verbose.IsPresent -or !$Debug.IsPresent) {
        echo "$msg"
    }

    if ($logFile -ne $null) {
        # Tee exists, but it's total garbage because it defaults to UTF16 and you can't change it ='(
        # This way of doing things could be slightly less awful in PowerShell 6...
        $utf8NoBOM = New-Object System.Text.UTF8Encoding $False
        [System.IO.File]::AppendAllLines($logFile, [string[]]$msg, $utf8NoBOM)
    }
}

<#
.SYNOPSIS
Writes text to stderr when running in a regular console window,
to the host''s error stream otherwise.

.DESCRIPTION
Writing to true stderr allows you to write a well-behaved CLI
as a PS script that can be invoked from a batch file, for instance.

Note that PS by default sends ALL its streams to *stdout* when invoked from
cmd.exe.

This function acts similarly to Write-Host in that it simply calls
.ToString() on its input; to get the default output format, invoke
it via a pipeline and precede with Out-String.

NB: didn't actually end up using this because it doesn't show up as a pretty
error, and I didn't want to go through the work of adding colors (esp. if
not being piped to a file!)

#>
function Write-StdErr {
    param ([PSObject] $InputObject)
    $outFunc = if ($Host.Name -eq 'ConsoleHost') {
        [Console]::Error.WriteLine
    } else {
        $host.ui.WriteErrorLine
    }
    if ($InputObject) {
        [void] $outFunc.Invoke($InputObject.ToString())
    } else {
        [string[]] $lines = @()
        $Input | % { $lines += $_.ToString() }
        [void] $outFunc.Invoke($lines -join "$([Environment]::NewLine)")
    }
}

function Debug-Pause() {
    if ($alwaysDebug -eq $true -or $interactive.IsPresent) {
        pause
    }
}

# wtf PowerShell...
function max($arr) {
    return ($arr | Measure-Object -Maximum).Maximum
}

Main
