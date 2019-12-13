@echo off

setlocal enableextensions enableDelayedExpansion
set version=2.0.1
set error=0;

REM Make sure PWD is _this_ directory.
pushd %~dp0

REM Argument Parsing adapted from https://stackoverflow.com/questions/3973824/windows-bat-file-optional-argument-parsing/8162578#8162578
set "options=-verbose: -interactive:"
for %%o in (%options%) do for /f "tokens=1,* delims=:" %%a in ("%%o") do set "%%a=%%~b"
:argParseLoop
if not "%~1"=="" (
  set "test=!options:*%~1:=! "
  if "!test!"=="!options! " (
    rem No substitution was made so this is an invalid option.
    echo Error: Invalid option %~1
    set error=3
    pause
    goto _exit;
  ) else if "!test:~0,1!"==" " (
    rem Set flags to their name
    set "%~1=%~1"
  ) else (
    rem Set the option value using the option as the name.
    rem and the next arg as the value
    set "%~3=%~4"
    shift
  )
  shift
  goto :argParseLoop
)

:intro
echo [38;5;202m-------------------------------------------------------------------------------[0m
echo [1;36m  Nuget Restore tool - VRTK[38;5;202m V%version%
echo [38;5;130m      Now with better package management for Unity 2018 and beyond [0m
echo.
echo [1;36m  This will almost certainly fail if Unity still has this project open.
echo [38;5;202m-------------------------------------------------------------------------------[0m
pause
echo.

REM NON-VTUE/VTCE PACKAGES CAN LEAVE THIS AS-IS:

REM     I couldn't find a more reliable way of doing this... nuget config doesn't return an errorLevel if the key exists, just puts it on stderr
REM Ask nuget where its extracting files:
nuget config repositoryPath 1>%TEMP%\std.out 2>%TEMP%\std.err
REM     Ideally I wouldn't create temp files, but I don't want to rely on the exact wording of the error message
REM Parse the results:
for /f "usebackq delims=" %%z in ('%TEMP%\std.err') do (
    if %%~zz gtr 0 (
        REM We got an error -- just assume the default, but also add a subdirectory because we whack that off below
        set NUGET_SRC_DIR=.\packages\source
        if defined -verbose type %%~z 1>&2
        echo Cauton: No repositoryPath specified in nuget.config.
        set nuget_msg=Assuming default nuget package directory
    ) else (
        set /P NUGET_SRC_DIR=<%TEMP%\std.out
        set nuget_msg=Nuget package directory is
    )
)

for /f "usebackq delims=" %%o in ( `powershell -command "(split-path %NUGET_SRC_DIR%)" ` ) do set NUGET_DIR=%%o
if defined -verbose echo %nuget_msg% %NUGET_DIR%
if defined -verbose echo.
set NUGET_CLEAN_DIRS= "%NUGET_DIR%" "%NUGET_DIR%\..\Runtime\nuget" "%NUGET_DIR%\..\Editor\nuget"

:cleanup
echo Deleting old packages...
for %%n in (%NUGET_CLEAN_DIRS%) do (
    if exist "%%n" (
        if defined -verbose echo   rd "%%~n" /S /Q
        set _newline=_newline
        rd "%%~n" /S /Q
    )
    if exist "%%~n" (
        echo.
        echo [1;93m-------------------------------------------------------------------------------[0m
        echo [91m  Restore failed - unable to delete old packages.[0m
        echo.
        echo [91m  This is usually caused by locked files. Unity, Windows Explorer and the Windows[0m
        echo [91m  Command Line are likely culprits. Close programs and try again.[0m
        echo [1;93m-------------------------------------------------------------------------------[0m
        pause
        set error=1
        goto _exit;
    )
)

REM Just some output prettying
if defined _newline (
    echo.
) else if defined -verbose (
    echo   Nothing to delete
)

:restore
set nugetArgs=-Verbosity quiet
if defined -verbose set nugetArgs=-Verbosity normal
echo Restoring NuGet sources...
nuget restore %nugetArgs%
set error=%ERRORLEVEL%
if %error% neq 0 (
    echo.
    echo [1;93m-------------------------------------------------------------------------------[0m
    echo [91m  Restore failed - NuGet Restore Error.[0m
    echo.
    echo [91m  NuGet was unable to restore your packages. Perhaps a repository or the [0m
    echo [91m  version of a configured package is not available.
    echo [91m
    echo [91m          This is not a "try-again" sort of error. Something is wrong.[0m
    echo [1;93m-------------------------------------------------------------------------------[0m
    pause
    goto _exit;
)


:install
echo Installing Dependencies...
REM this code invokes each init.ps1 file in %NUGET_DIR% and manipulates the arguments to match what VS would give.
REM Pretty much only installPath is used/important, but the rest are there for completeness' sake.

REM I'm sorry I can't explain how this actually works. type "HELP FOR" into CMD and weep.

for /f "usebackq delims=" %%x in (`dir "%NUGET_DIR%" /s/b ^| Find "init.ps1"`) do (
    echo   - invoking %%x
    for /f "delims=" %%y in ("%%~dpx..") do (
        PowerShell.exe -File "%%~x" ^
            -installPath "%%~fy" ^
            -toolsPath "%%~dpx/" ^
            -package NuGet.PackageManagement.VThera.ScriptPackage ^
            %-verbose% ^
            %-interactive%
    )
)

REM VS sends an object that sorta looks like "NuGet.PackageManagement.VisualStudio.ScriptPackage" for -package ...
REM ... We'll just send a string because we're not powershell, and another wrapper would be silly


:complete
echo.
echo [38;5;202m-------------------------------------------------------------------------------[0m
echo [1;36m  Restore Complete[0m
echo.
echo [0;36m  If you're working in Visual Studio, remember that your project file will be
echo [0;36m  out of date until Unity recreates it.
echo [38;5;202m-------------------------------------------------------------------------------[0m


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
popd
exit /b %error%
