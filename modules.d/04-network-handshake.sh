#!/bin/bash
# S.O.U.L. Unit 04: PQC-Authenticated Mesh Handshake
set -euo pipefail

echo ">> [Nicholas Protocol] Initiating PQC Handshake..."

# 1. Generate an Ephemeral Session Nonce
NONCE=$(openssl rand -hex 32)

# 2. Sign the Nonce with the Node's ML-DSA Identity
# This proves the node is the owner of the hardware-rooted key
echo "$NONCE" > .session_nonce
openssl pkeyutl -sign -inkey "$V_DIR/node_identity.key" -in .session_nonce -out .session_sig

# 3. Simulate Gateway Verification
if openssl pkeyutl -verify -pubin -inkey "$V_DIR/node_identity.pub" -sigfile .session_sig -in .session_nonce > /dev/null 2>&1; then
    echo ">> HANDSHAKE SUCCESS: Node verified as SANCTIONED."
    echo ">> Substrate Link: SECURE."
else
    echo "CRITICAL: Handshake Signature Failure. Isolating Node."
    exit 1
fi

rm .session_nonce .session_sig
