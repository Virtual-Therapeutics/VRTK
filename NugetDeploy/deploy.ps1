echo ". $PSScriptRoot\vt-deploy-utilities.ps1"

. $PSScriptRoot\vt-deploy-utilities.ps1 @args

trap{ VT-Deploy-Trap-Handler }

Set-Up

Deploy-Package "..\vrtk.nuspec"

Clean-Up

exit $exit
