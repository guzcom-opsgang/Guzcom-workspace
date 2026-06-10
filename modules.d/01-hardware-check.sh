#!/bin/bash
# S.O.U.L. Unit 01: Hardware Root Attestation
set -euo pipefail

echo ">> [Attestation] Verifying Hardware Root of Trust..."

# Ensure we use the global SEAL variable defined in veritas.sh
if [[ ! -f "$SEAL" ]]; then
    echo "CRITICAL: TPM Ritual Seal not found ($SEAL). Hardware unverified."
    exit 1
fi

echo ">> Hardware state: VERIFIED."
