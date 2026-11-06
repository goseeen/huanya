#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
REPO=$(dirname "$ROOT")
DOTNET=${HUANYA_DOTNET:-dotnet}
RID=${1:-win-x64}
case "$RID" in win-x64|win-arm64|win-x86) ;; *) echo 'Expected win-x64, win-arm64 or win-x86' >&2; exit 1;; esac
OUT="$REPO/dist/windows/huanya-2.0.0-preview.1-$RID"
"$DOTNET" run --project "$ROOT/Huanya.Tests" -c Release
"$DOTNET" publish "$ROOT/Huanya.Desktop" -c Release -r "$RID" --self-contained true -p:PublishSingleFile=false -p:PublishTrimmed=false -o "$OUT"
find "$OUT" -name "*.pdb" -delete
cp "$REPO/LICENSE" "$ROOT/THIRD_PARTY_NOTICES.md" "$OUT/"
cp "$ROOT/README.md" "$OUT/README.md"
(cd "$OUT" && zip -qr "../huanya-2.0.0-preview.1-$RID.zip" .)
(cd "$(dirname "$OUT")" && shasum -a 256 "huanya-2.0.0-preview.1-$RID.zip" > "huanya-2.0.0-preview.1-$RID.sha256")
