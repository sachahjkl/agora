#!/usr/bin/env bash
# Shortcut: ./build.sh [debug|release] is agoratool build.
# Every other step: odin run tools/agoratool -collection:gt=ext/gui_toolkit/src -out:build/agoratool -- <command> (help lists them).
cd "$(dirname "$0")" && mkdir -p build && exec odin run tools/agoratool -collection:gt=ext/gui_toolkit/src -out:build/agoratool -keep-executable -- build "$@"
