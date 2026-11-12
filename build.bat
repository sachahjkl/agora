@echo off
rem Shortcut: build.bat [debug|release] is agoratool build.
rem Every other step: odin run tools/agoratool -collection:gt=ext/gui_toolkit/src -out:build/agoratool -- <command> (help lists them).
cd /d "%~dp0"
if not exist build mkdir build
odin run tools/agoratool -collection:gt=ext/gui_toolkit/src -out:build/agoratool -keep-executable -- build %*
