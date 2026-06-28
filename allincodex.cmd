@echo off
REM allincodex launcher - forwards to the PowerShell CLI
pwsh -NoProfile -ExecutionPolicy Bypass -File "%~dp0bin\allincodex.ps1" %*
