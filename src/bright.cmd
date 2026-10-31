@echo off
rem Brightness CLI wrapper - delegates everything to bright.ps1
rem Usage: bright            (show brightness)
rem        bright 40         (set all monitors to 40%)
rem        bright +10 / -10  (adjust all monitors)
rem        bright set 40 2   (set monitor #2 to 40%)
rem        bright list       (list monitors)
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0bright.ps1" %*
