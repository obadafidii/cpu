#!/usr/bin/env bash
# Build script for Vercel. The Vercel build image has no Zig, so this
# installs Zig 0.16.0 (from PyPI, falling back to ziglang.org) and runs
# `zig build web`, which writes the site to zig-out/web.
set -euo pipefail

ZIG_VERSION=0.16.0
TOOLS="$PWD/.zig-toolchain"
mkdir -p "$TOOLS"

zig() {
  if [ -x "$TOOLS/zig/zig" ]; then
    "$TOOLS/zig/zig" "$@"
  else
    PYTHONPATH="$TOOLS/py" "$PY" -m ziglang "$@"
  fi
}

PY="$(command -v python3.12 || command -v python3 || true)"
if [ -n "$PY" ] && "$PY" -m pip install --quiet --disable-pip-version-check --target "$TOOLS/py" "ziglang==$ZIG_VERSION"; then
  echo "Installed Zig $ZIG_VERSION from PyPI"
else
  ARCH="$(uname -m)"
  echo "PyPI install failed, downloading Zig $ZIG_VERSION for $ARCH from ziglang.org"
  curl -fsSL "https://ziglang.org/download/$ZIG_VERSION/zig-$ARCH-linux-$ZIG_VERSION.tar.xz" -o "$TOOLS/zig.tar.xz"
  mkdir -p "$TOOLS/zig"
  tar -xJf "$TOOLS/zig.tar.xz" -C "$TOOLS/zig" --strip-components=1
fi

zig version
zig build web
ls -la zig-out/web
