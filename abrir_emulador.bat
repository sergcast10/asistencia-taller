@echo off
title Iniciando Emulador Android (Arranque Limpio)
echo ===================================================
echo     INICIANDO EMULADOR ANDROID (COLD BOOT LIMPIO)
echo ===================================================
start "" "C:\src\android-sdk\emulator\emulator.exe" -avd test_emulator -no-snapshot-load
exit
