@echo off & goto DOC_END

rem   Based on:
rem     `Uniform variant of a command line as a single argument for the mshta.exe executable and other cases` :
rem     https://github.com/andry81/contools/discussions/11

rem CAUTION:
rem   The environment variables is NOT used by the shell code to workaround
rem   the `mshta.exe` command line length limitation (see the link).

rem CAUTION:
rem   The `mshta.exe` does expand all the %-escape placeholders (`%NN`).
rem   The script does not use `%` character in the shell code. In case of a
rem   change in the future you must prevent the expansion by replacing all the
rem   `%` by `%25` to avoid the command line breakage.
rem   All the `"` does process for the same reason.

rem NOTE:
rem   The `ExecuteGlobal` is used as a workaround, because the `mshta.exe`
rem   first argument must not be used with the surrounded quotes.

rem CAUTION:
rem   The `ShellExecute` does not wait a child process close.

rem CAUTION:
rem   The `cmd.exe` does expand the %-variables in the context of an elevated
rem   process. You must properly escape these to avoid the expansion before the
rem   elevation!

rem CAUTION:
rem   `\""`, `\""""`, etc expressions only has meaning inside a `.bat` script.
rem   Any attempt to use it outside of a script (including a terminal command
rem   line) will lead into incorrect expansion because a terminal command
rem   line or an `.exe` command line has their own different expansion rules
rem   including command line of the `cmd.exe` executable.

rem CAUTION:
rem   Avoid a back slash before the double quote in an executable (`.exe`)
rem   command line, otherwise a command line parse will be broken:
rem     >
rem     some.exe "... ... \"
rem                        ^ - escaped
rem     >
rem     some.exe "... ... \""
rem                        ^ - escaped
rem   To workaround:
rem     >
rem     some.exe "... ... \\"
rem                        ^ - escaped
rem     >
rem     some.exe "... ... \\""
rem                        ^ - escaped
rem
rem   A trailing double quote will be escaped in some command line parse code
rem   runtimes. But not everywhere, for example, `cmd.exe` has different rules:
rem
rem     >
rem     cmd.exe /c @echo "... ... \"
rem                               ^ - prints as is
:DOC_END

setlocal DISABLEDELAYEDEXPANSION

rem script names call stack, disabled due to self call and partial inheritance (process elevation does not inherit a parent process variables by default)
rem if defined ?~ ( set "?~=%?~%-^>%~nx0" ) else if defined ?~nx0 ( set "?~=%?~nx0%-^>%~nx0" ) else set "?~=%~nx0"
set "?~=%~nx0"

set /A ELEVATED+=0

if %IMPL_MODE%0 NEQ 0 goto IMPL
call :IS_ADMIN_ELEVATED && goto ELEVATED

goto ELEVATE

rem CAUTIOM:
rem   Windows 7 has an issue around the `find.exe` utility and code page 65001.
rem   We use `findstr.exe` instead of `find.exe` to workaround it.
rem
rem   Based on: https://superuser.com/questions/557387/pipe-not-working-in-cmd-exe-on-windows-7/1869422#1869422

rem CAUTION:
rem   In Windows XP an elevated call under data protection flag will block the wmic tool, so we have to use `ver` command instead!

:IS_ADMIN_ELEVATED
set "WINDOWS_VER_STR=" & set "WINDOWS_MAJOR_VER=0" & for /F "usebackq tokens=1,2,* delims=[]" %%i in (`@ver 2^>nul`) do set "WINDOWS_VER_STR=%%j"
if not defined WINDOWS_VER_STR goto SKIP_VER
setlocal ENABLEDELAYEDEXPANSION & for /F "usebackq tokens=* delims="eol^= %%i in ('"!WINDOWS_VER_STR:* =!"') do endlocal & set "WINDOWS_VER_STR=%%~i"
for /F "tokens=1,2,* delims=."eol^= %%i in ("%WINDOWS_VER_STR%") do set "WINDOWS_MAJOR_VER=%%i"
:SKIP_VER
if %WINDOWS_MAJOR_VER% GEQ 6 (
  if exist "%SystemRoot%\System32\where.exe" "%SystemRoot%\System32\whoami.exe" /groups | "%SystemRoot%\System32\findstr.exe" /L "S-1-16-12288" >nul 2>nul & exit /b
) else if exist "%SystemRoot%\System32\fltmc.exe" "%SystemRoot%\System32\fltmc.exe" >nul 2>nul & exit /b
exit /b 255

:ELEVATE
rem Windows Batch compatible command line with escapes
set ?.=set "IMPL_MODE=1" ^& "%~f0" %* ^& pause

(
  setlocal ENABLEDELAYEDEXPANSION

  rem escape %-escapes
  set "?.=!?.:%%=%%25!"

  rem translate Windows Batch compatible escapes into escape placeholders
  set "?.=!?.:$=$0!"
  set "?.=!?.:\""""""""=$4!"
  set "?.=!?.:\""""=$3!"
  set "?.=!?.:\""=$2!"
  set "?.=!?.:"^=$1!"

  rem translate escape placeholders into `mshta.exe` (vbs) escapes
  set "?.=!?.:$4=""""""""""""""""""""""""""""""""!"
  set "?.=!?.:$3=""""""""""""""""!"
  set "?.=!?.:$2=""""""""!"
  set "?.=!?.:$1=""""!"
  for /F "tokens=* delims="eol^= %%i in ("!?.:$0=$!") do endlocal & set "?.=%%i"
)

if "%PROCESSOR_ARCHITECTURE%" == "x86" goto X86

if not exist "%SystemRoot%\SysWOW64\*" (
  echo;%?~%: error: not x86 system without SysWOW64 system directory.
  exit /b 255
) >&2

start "" /B /WAIT "%SystemRoot%\System32\mshta.exe" vbscript:ExecuteGlobal("Close(CreateObject(""Shell.Application"").ShellExecute(""%SystemRoot%\SysWOW64\cmd.exe"", ""/c @%?.%"", """", ""runas"", 1))")
exit /b

:X86
start "" /B /WAIT "%SystemRoot%\System32\mshta.exe" vbscript:ExecuteGlobal("Close(CreateObject(""Shell.Application"").ShellExecute(""%COMSPEC%"", ""/c @%?.%"", """", ""runas"", 1))")
exit /b

:ELEVATED
set ELEVATED=1

:IMPL
if %ELEVATED% EQU 0 call :IS_ADMIN_ELEVATED || (
  echo;%?~%: error: process must be elevated before continue.
  exit /b 255
) >&2

rem NOTE: recheck, just in case
if "%PROCESSOR_ARCHITECTURE%" == "x86" goto X86

if not exist "%SystemRoot%\SysWOW64\*" (
  echo;%?~%: error: not x86 system without SysWOW64 system directory.
  exit /b 255
) >&2

rem CAUTION: ShellExecute does not wait a child process close!
"%SystemRoot%\SysWOW64\cmd.exe" /c @"%~f0" %*
exit /b

:X86
echo;^>"%SystemRoot%\System32\regsvr32.exe" /u "%~dp0jcb.ocx"
"%SystemRoot%\System32\regsvr32.exe" /u "%~dp0jcb.ocx"
