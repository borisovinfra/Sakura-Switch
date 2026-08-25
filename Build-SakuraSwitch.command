#!/bin/bash
set -e

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"

cd "$ROOT_DIR"

./scripts/build-app.sh --version=1.0.0

open "$ROOT_DIR/build/Sakura Switch.app"
