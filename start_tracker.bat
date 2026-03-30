@echo off
echo ToN 統計トラッカーを起動するわ...
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File ".\ton_tracker.ps1"
pause