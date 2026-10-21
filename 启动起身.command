#!/bin/zsh
set -eu
cd "${0:A:h}"
if [[ ! -x "dist/起身 RiseUp.app/Contents/MacOS/RiseUp" ]]; then
    /bin/zsh scripts/build.sh
fi
open "dist/起身 RiseUp.app"
