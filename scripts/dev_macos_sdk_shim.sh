#!/usr/bin/env bash
# Local dev only — lets `flutter test` build package:sodium on a Mac that has
# the Command Line Tools but not a licensed, selected Xcode. Needs no sudo and
# changes nothing about the machine.
#
# Why: package:sodium's build hook looks for the macOS SDK at
#   <xcode-select -p>/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk
# which only exists under a full Xcode. Under the Command Line Tools the SDK
# lives at /Library/Developer/CommandLineTools/SDKs/MacOSX.sdk instead, so the
# native build fails with "C compiler cannot create executables".
#
# This builds a throwaway developer dir with the layout the hook expects,
# backed by the CLT SDK, plus an `xcode-select` shim that reports it.
#
# Usage:   eval "$(scripts/dev_macos_sdk_shim.sh)" && flutter test
#
# CI runners carry a full Xcode and never need this.
set -euo pipefail

CLT_SDK=/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk
DEV="${TMPDIR:-/tmp}/rukka-dev-sdk"

if [ "$(uname -s)" != "Darwin" ]; then echo "echo 'not macOS — shim not needed'"; exit 0; fi

# A properly selected, licensed Xcode needs no shim.
real="$(/usr/bin/xcode-select -p 2>/dev/null || true)"
if [ -d "$real/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk" ] && /usr/bin/xcrun --find clang >/dev/null 2>&1; then
  echo "echo 'Xcode is selected and licensed — shim not needed'"; exit 0
fi

[ -d "$CLT_SDK" ] || { echo "echo 'no Command Line Tools SDK at $CLT_SDK — run: xcode-select --install' >&2; false" ; exit 1; }

mkdir -p "$DEV/Platforms/MacOSX.platform/Developer/SDKs" "$DEV/bin"
ln -sfn "$CLT_SDK" "$DEV/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk"
ln -sfn /Library/Developer/CommandLineTools/usr "$DEV/usr"
cat > "$DEV/bin/xcode-select" <<EOF
#!/bin/bash
if [ "\$1" = "-p" ] || [ "\$1" = "--print-path" ]; then echo "$DEV"; exit 0; fi
exec /usr/bin/xcode-select "\$@"
EOF
chmod +x "$DEV/bin/xcode-select"

echo "export PATH=\"$DEV/bin:\$PATH\""
