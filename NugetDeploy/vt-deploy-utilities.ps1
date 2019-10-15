param(
    [Switch]$NoCleanup
)

### Configuration
$alwaysDebug = $false
$logFile = ".\vtnuget.deploy.log"      # this is fine. Could include packageName, parsed at build-time (e.g. from name of directory?)


### State
$exit = 1 # assume things broke until we get to the end...
$millis = "temp"


function Log-Output()
{
    param(
        [string[]]$captured
    )

    # Teeing directly to a file is total garbage because it writes in UTF16 and you can't change it ='(
    # This could be slightly less awful in PowerShell 6!
    $utf8NoBOM = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::AppendAllLines($logFile, $captured, $utf8NoBOM)
}

function log()
{
    param(
        [string]$msg,   # the message to log
        [switch]$Debug  # flag indicating that this is debug-level info, only log to screen if $alwaysDebug is on (always log to file)
    )

    $msgs = $msg -split "[`r`n]+"

    if (!$Silent.IsPresent -and ($alwaysDebug -eq $true -or !$Debug.IsPresent))
    {
        echo "$msgs"
    }

    # send to log file
    Log-Output $msgs
}

<#
.SYNOPSIS
Handles terminating errors cleaanly. Designed to be called from within a trap {} statement in code that sources this file
#>
function VT-Deploy-Trap-Handler
{
    $exit = $LASTEXITCODE;
    if ((!$exit) -or ($exit -eq 0)) { $exit = 1 }

    # save this because Clean-Up will reset it
    $trueExitCode = $exit

    Write-StdErr "Exception!$([Environment]::NewLine)$_"
    Clean-Up

    exit $trueExitCode
}

<#
.SYNOPSIS
Sets up the deploy environment before deploying packages
#>
function Set-Up()
{
    # milliseconds since Unix Epoch (Jan 1 1970 12:00:00 AM UTC)
    Set-Variable -Name millis -Scope Global -Value ([Math]::Round((Get-Date).ToFileTime() / 10000000 - 11644473600))
    mkdir "$millis" | Out-Null
}

<#
.SYNOPSIS
Cleans up the deploy environment after deploying packages
#>
function Clean-Up
{
    if ($NoCleanup.IsPresent)
    {
        log "-NoCleanup is present; Deployment Clean-Up is disabled."
        log "Don't forget to delete $millis"
    }
    else
    {
        log "Cleaning Up Deployment..."
        Remove-Item -Recurse -Force -Path "$millis"
    }
    $exit = 0

    $archivedLog = "$([io.path]::GetFileNameWithoutExtension("$logFile")).$(Get-Date -Format FileDateTimeUniversal)$([io.path]::GetExtension("$logFile"))"
    Move-Item "$logFile" "$archivedLog"

    if ($alwaysDebug -eq $true)
    {
        echo "    this logFile is archived as $archivedLog"
    }
}

<#
.SYNOPSIS
Deploys a package specified by a nuspec file to our internal NuGet repository, prompting for confirmation
 before uploading.

.DESCRIPTION
This will pass along the first line of a version file as $version to the nuspec file, as well as the
$millis unique value of the current deployment. The nuspec file may ignore these values.
#>
function Deploy-Package($nuspecFilePath, $versionFilepath)
{
    $packageName = [io.path]::GetFileNameWithoutExtension($nuspecFilepath)
    $packageDir = Join-Path "$millis" "$packageName"
    mkdir "$packageDir" | Out-Null

    # Create package
    $version = "no-version-provided"
    if ($versionFilepath)
    {
        $version = Get-Content $versionFilepath -First 1
    }

    # TODO: This doesn't work perfectly. Newlines in the output aren't preserved. =\
    nuget pack $nuspecFilePath -Properties "time=$millis;ver=$version" -OutputDirectory "$packageDir" 2>&1 | Tee -Variable captured
    Log-Output $captured

    # Confirm Upload...
    ($filename = Get-ChildItem -Path "$packageDir" -File | Select-Object -First 1 -Property Name) | Out-Null

    if ($filename.Name -match "[0-9]+\.[0-9]+\.[0-9]-?[a-zA-Z0-9\-\.]*.nupkg")
    {
        $parsed_version = [io.path]::GetFileNameWithoutExtension($Matches[0]);

        echo ""
        $msg = "Are you sure you want to publish $([io.path]::GetFileNameWithoutExtension($nuspecFilePath)) as version $parsed_version (y)"
        $verify = Read-Host -Prompt $msg
        Log-Output $msg,"> $verify"

        if ($verify.ToLower().StartsWith("y") -or $verify.Length -eq 0)
        {
            nuget add "$packageDir\$($filename.Name)" -source \\VT-REDDCFILE01\vt-nuget | Tee -Variable captured
            Log-Output $captured
            $exit = $LASTEXITCODE
        }
    }
}

## https://stackoverflow.com/questions/4998173/how-do-i-write-to-standard-error-in-powershell

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
