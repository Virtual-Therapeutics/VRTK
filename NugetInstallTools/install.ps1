param($installPath, $toolsPath, $package, $project)

$alwaysDebug = $false # change to $true for more logging

function log()
{
    param([string]$msg, [switch]$Debug)
    if ($alwaysDebug -eq $true -or !$Debug.IsPresent)
    {
        echo "$msg"
    }

    # Tee exists, but it's total garbage because it defaults to UTF16 and you can't change it ='(
    # This could be slightly less awful in PowerShell 6!
    $utf8NoBOM = New-Object System.Text.UTF8Encoding $False
    [System.IO.File]::AppendAllLines(".\vtnuget.install.log", [string[]]$msg, $utf8NoBOM)
}

log "% install.ps1 started at $(Get-Date -Format o)"
log "  Parameters Received:" -Debug
log "    `$installPath $installPath" -Debug
log "    `$toolspath $toolsPath" -Debug
log "    `$package $package" -Debug
log "    `$project ($project.ToString)" -Debug

$initScript = Join-Path $PSScriptRoot "init.ps1"

log "* executing $initScript"

& "$initScript" $installPath $toolsPath $package

log "% install.ps1 completed"
log ""
