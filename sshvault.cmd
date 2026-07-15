@echo off
REM ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
REM sshvault.cmd  (Windows wrapper)
REM Allows running `sshvault` from anywhere if
REM this .cmd is in a folder on the PATH.
REM ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
setlocal
set "SCRIPT_DIR=%~dp0"
"%SCRIPT_DIR%sshvault.exe" %*
endlocal
