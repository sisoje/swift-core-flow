#!/bin/sh
# Regenerates this example's Swift sources from SPEC.md via the claude CLI —
# the sources are deliberately not checked in; SPEC.md is their source of
# truth. project.yml, test.sh, and this script are the spec's executable
# half, kept verbatim. Verify a regeneration with `sh test.sh`.
set -eu
cd "$(dirname "$0")"

claude -p \
    --permission-mode acceptEdits \
    --allowedTools "Read,Write,Edit,Glob,Grep" \
    "Regenerate this example's Swift sources from SPEC.md in the current \
directory. SPEC.md is the complete contract; the repo root's CLAUDE.md \
documents the macro semantics it assumes. Create every Swift file at the \
paths in SPEC.md's Layout section — code blocks verbatim, prose contracts \
faithfully, nothing beyond what the spec calls for. Do not modify \
project.yml, test.sh, generate.sh, or SPEC.md, and do not build or run \
tests — verification is a separate \`sh test.sh\`."

echo "Sources regenerated — verify with: sh test.sh"
