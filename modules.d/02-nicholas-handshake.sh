#!/bin/bash
# S.O.U.L. Unit 02: Nicholas Protocol Handshake
set -euo pipefail

echo ">> [Nicholas Protocol] Initializing Session Handshake..."

# Generate a high-entropy session key for the current boot
# This acts as the "glue" for the S.O.U.L. units
HANDSHAKE_KEY=$(openssl rand -hex 64)
echo "$HANDSHAKE_KEY" > "$V_DIR/.nicholas_session"

echo ">> Session token generated and sealed."
echo "S.O.U.L. Unit 02 ACTIVE."
