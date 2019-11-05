@echo off

pushd %~dp0

REM Invoke ps1 file in same location as this batch file:
powershell -File "%~dp0deploy.ps1" %*

popd

:pauseIfRunByExplorerDoubleClick

REM first check for being invoked by powershell, because that gives a false positive below
echo %PSModulepath% | findstr %USERPROFILE% >NUL
if %ERRORLEVEL% EQU 0 goto _exit

REM then check some command line voodoo to see if we were invoked by not-cmd
setlocal enabledelayedexpansion
set testl=%cmdcmdline:"=%
set testr=!testl:%~nx0=!
if not "%testl%" == "%testr%" pause

:_exit
@REM if we put something here, then it'll add an extra line to the CLI running it. Weird.
