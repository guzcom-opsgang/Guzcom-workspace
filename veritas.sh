#!/bin/bash
# VeritasCore v1.1: Sovereign Execution Gatekeeper
set -euo pipefail

# 1. IMMUTABLE PATHING
readonly V_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly MOD_DIR="$V_DIR/modules.d"
readonly SEAL="$V_DIR/.ritual_seal"

echo "--- [VeritasCore Init] ---"

# 2. INTEGRITY GATEKEEPER (The "New Testament" Gate)
echo ">> [Integrity] Verifying Substrate Manifest..."

# A. Verify the PQC Signature on the manifest
if ! openssl pkeyutl -verify -pubin -inkey "$V_DIR/node_identity.pub" -sigfile "$V_DIR/veritas.manifest.sig" -in "$V_DIR/veritas.manifest" > /dev/null 2>&1; then
    echo "SECURITY ALERT: Manifest Signature Invalid! Substrate Compromised."
    exit 1
fi

# B. Verify the file hashes within the manifest
if ! sha256sum -c --quiet "$V_DIR/veritas.manifest"; then
    echo "CRITICAL: File Mismatch Detected! Possible code injection."
    exit 1
fi
echo ">> Integrity: VERIFIED (ML-DSA-65)."

# 3. FAIL-CLOSED ENVIRONMENT CHECK
if [[ ! -f "$V_DIR/core.env" ]]; then
    echo "ERROR: core.env missing. Substrate compromised."
    exit 1
fi
source "$V_DIR/core.env"

# 4. SECURE MODULE LOADER
if [[ -d "$MOD_DIR" ]]; then
    for module in $(ls "$MOD_DIR"/*.sh | sort); do
        if [[ "$(stat -c '%a' "$module")" != "600" ]]; then
            echo "SECURITY ALERT: Insecure module $module. Halt."
            exit 1
        fi
        source "$module"
    done
fi

echo ">> VERITASCORE ACTIVE: Chain of Trust Verified."
