#!/bin/bash


# FLUTTER_BUILD_MODEが未定義ならdebugを設定
if [ -z "$FLUTTER_BUILD_MODE" ]; then
  export FLUTTER_BUILD_MODE=debug
fi
