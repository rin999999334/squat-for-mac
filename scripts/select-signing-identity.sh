#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
IDENTITY="${1:-}"
if [ "$#" -ne 1 ] || ! [[ "$IDENTITY" =~ ^[[:xdigit:]]{40}$ ]]; then
    printf 'Usage: %s <40-character certificate SHA-1>\n' "$0" >&2
    exit 2
fi
IDENTITY=$(printf '%s' "$IDENTITY" | tr '[:lower:]' '[:upper:]')
if ! security find-identity -v -p codesigning | /usr/bin/grep -Fq "$IDENTITY"; then
    printf 'No available code-signing identity matches. Nothing changed.\n' >&2
    exit 1
fi
mkdir -p .build
if { [ -e .build/local-signing-identity ] || [ -L .build/local-signing-identity ]; } \
    && { [ ! -f .build/local-signing-identity ] || [ -L .build/local-signing-identity ]; }; then
    printf 'Invalid signing configuration path; nothing changed.\n' >&2
    exit 1
fi
umask 077
IDENTITY_FILE=$(mktemp .build/local-signing-identity.XXXXXX)
trap 'rm -f "$IDENTITY_FILE"' EXIT
printf '%s\n' "$IDENTITY" > "$IDENTITY_FILE"
mv "$IDENTITY_FILE" .build/local-signing-identity
printf 'Selected local signing identity. Next build will use this certificate.\n'
