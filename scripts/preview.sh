#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
# Compile the isolated preview directly. Never rebuild or copy the normal app.
exec scripts/build.sh --preview
