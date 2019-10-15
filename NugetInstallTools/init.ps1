param($installPath, $toolsPath, $package)

# Nugetizer

$alwaysDebug = $false # change to $true for more logging and pausing

# TODO: Sure would be nice to derive these, instead of hard-coding these assumptions...
$nugetRootName = "nuget_packages"       # parse from nuget.config at runtime?
$srcFolder = "lib"                      # parse from nuspec at build time?    # ... or libFolder?
$netVersionFolder = "net46"             # parse from nuspec at build time?
$nativeFolder = "native"                # parse from nuspec at build time?
$logFile = ".\vtnuget-logs\vtnuget.install.log"      # this is fine. Could include packageName, parsed at build-time (e.g. from name of nuSpec)

function Main() {

    $filesToInit = Count-PackageFiles
    if ($filesToInit -eq 0) {
        echo "* Package $(Split-Path $installPath -Leaf) has nothing to initialize. Exiting."
        exit 0
    }

    Configure-Log

    # these spaces makes print-f debugging saner
    log ""
    log "* Package $(Split-Path $installPath -Leaf) - init.ps1 started at $(Get-Date -Format o)"
    log "  Parameters Received:" -Debug
    log "    `$installPath:   $installPath" -Debug
    log "    `$toolspath:     $toolsPath" -Debug
    log "    `$package:       $package" -Debug

    if ($package -ne "NuGet.PackageManagement.VThera.ScriptPackage") {
        log "Hey! Listen! - Initializing packages with Visual Studio isn't supported yet.  Please run restore_packages.bat"
        exit 1
    }

    Debug-Pause

    #### TODO: Maybe this could be read from the nuget.config file?
    # find the root nuget package directory
    $nugetRootDir = $installPath
    $packageName = Split-Path -Leaf $nugetRootDir
    $stop_dir = $packageName

    $counter = 0
    # if it's not this directory, keep looking upwards for it.
    while($stop_dir -ne "$nugetRootName" -or $stop_dir -eq "") {
        $nugetRootDir = Split-Path -Path $nugetRootDir
        $stop_dir = Split-Path -Leaf $nugetRootDir
    }

    if ($stop_dir -eq "" -or $stop_dir -eq $null) {
        # TODO: would be nice if this weren't hard-coded:
        $msg = "*** Malformed Package! Cannot find '$nugetRootName' directory as parent of $installPath"
        log "$msg" -AsError
        exit 1
    }

    log "  * Initializing $packageName NuGet Package..."

    $nugetRootDir = Join-Path $nugetRootDir $stop_dir
    #### end of mess that could be replaced by call to nuget, probably

    $runtimeSource = [IO.Path]::Combine($installPath, $srcFolder, $netVersionFolder, "Runtime")
    $editorSource = [IO.Path]::Combine($installPath, $srcFolder, $netVersionFolder, "Editor")
    $foundationSource = [IO.Path]::Combine($installPath, $srcFolder, $netVersionFolder, "Foundation")
    $pluginSource = [IO.Path]::Combine($installPath, $srcFolder, $nativeFolder)

    $runtimeDestinationFolder = [IO.Path]::Combine((Split-Path -Path $nugetRootDir), "Runtime")
    $editorDestinationFolder = [IO.Path]::Combine((Split-Path -Path $nugetRootDir), "Editor")
    $foundationDestinationFolder = [IO.Path]::Combine((Split-Path -Path $nugetRootDir), "Foundation")


    #This is done by everyone:
    Move-DirContents $runtimeSource $runtimeDestinationFolder $packageName
    Move-DirContents $editorSource $editorDestinationFolder $packageName
    Move-DirContents $foundationSource $foundationDestinationFolder $packageName
    Move-DirContents $pluginSource $runtimeDestinationFolder $packageName

    # TODO: check to see if any files are left behind and if so indicate that something's bad about the package?

    Debug-Pause

    log "- init.ps1 completed - $packageName"
    log ""

    $archivedLog = "$([io.path]::GetFileNameWithoutExtension("$logFile")).$(Get-Date -Format FileDateTimeUniversal)$([io.path]::GetExtension("$logFile"))"
    Move-Item "$logFile" (Join-Path (Split-Path $logFile -Parent) "$archivedLog")

    if ($alwaysDebug -eq $true) {
        echo "    this logFile is archived as $archivedLog"
    }
}

function Count-PackageFiles() {
    $filesToInit = 0
    foreach ($dirEntry in Get-ChildItem (Join-Path $installPath $srcFolder) -Recurse -Force -File -Exclude *.meta) {
        $filesToInit += 1
    }
    return $filesToInit
}

function Move-DirContents($source, $destRoot, $packageName) {
    $srcCategory = (Split-Path $source -Leaf)
    $destCategory = (Split-Path $destRoot -Leaf)
    $shortSource = [IO.Path]::Combine($packageName, $srcFolder, $netVersionFolder, $srcCategory)
    $shortDest = [IO.Path]::Combine($nugetRootName, $destCategory, $packageName)

    # Are there any files to move?
    if (!(Test-Path $source) -or ((Get-ChildItem $source | Measure-Object).Count) -eq 0) {
        log "    - $shortSource is not present in this package" -Debug
        return
    }

    $destDir = (Join-Path $destRoot $packageName)

    log "    * copying $shortSource to $shortDest"
    log "    * $source" -Debug
    log "    --> $(Join-Path $destRoot $packageName)" -Debug

    Debug-Pause

    # Simple/Fast option: destDir does not exist at all.
    if (!(Test-Path $destDir)) {

        # Ensure parent directory exists
        if (!(Test-Path $destRoot)) {
            New-Item $destRoot -ItemType Directory | Out-Null
        }

        # Just copy the whole folder over into parent, and then rename it
        Move-Item -Path $source -Destination "$destRoot" -PassThru | Rename-Item -Force -NewName $packageName

    } else {
        # Hard-mode. We have to merge the contents of these directories. Don't allow *file* collisions:
        # we'll call those malformed packages.


        # For every file in all subdirectories of source: move it to where it's supposed to go.
        foreach ($dirEntry in Get-ChildItem $source -Force -Recurse -File) {

            # Why am I manipulating strings like this I hate everything ='(
            $destFile = ($dirEntry.FullName).substring($dirEntry.FullName.indexOf($source) + $source.Length + 1)

            # This is gross too =''(
            $finalDestination = Join-Path $destDir $destFile # fox only, no items
            $ultimateDir = Split-Path $finalDestination

            if (!(Test-Path $ultimateDir)) {
                New-Item $ultimateDir -ItemType Directory | Out-Null
            }

            Move-Item -Path $dirEntry.FullName -Destination $finalDestination
        }

        # In retrospect, it would've been nice to implement this in terms of the above when possible?
        # Or, at the very least, clean up all the folders we've left behind...
        $leftOvers = 0
        foreach ($dirEntry in Get-ChildItem $source -Force -Recurse -File) {
            $leftOvers += 1
        }
        if ($leftOvers -eq 0) {
            foreach ($dirEntry in Get-ChildItem $source -Force -Directory) {
                Remove-Item $($dirEntry.FullName) -Recurse -Force
            }
        }
    }
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
        log("!!! Unable to log this output to a file.")
    } else {
        log("Logging to file " + $(Resolve-Path $logFile))
        if ($fallBackIndex -gt 0) {
            log("    (Unable to write to " + $(Resolve-Path $orig) + " due to errors.")
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
    } elseif ($alwaysDebug -eq $true -or !$Debug.IsPresent) {
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
    if ($alwaysDebug -eq $true) {
        pause
    }
}


Main
