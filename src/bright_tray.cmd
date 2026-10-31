@echo off
rem Launches the bright_tray tray app without a console window flash.
powershell -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "%~dp0bright_tray.ps1"
