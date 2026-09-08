#!/usr/bin/env bash
#
# Loescht KEK und DEKs aus der Confluent-Cloud-DEK-Registry.
#
# WARUM DAS NOETIG IST:
# CSFLE nutzt Envelope Encryption. Der DEK (Data Encryption Key) wird in der
# Cloud gespeichert - verschluesselt mit dem KEK, der in Vault liegt.
# Vault laeuft im Dev-Mode und verliert bei jedem Neustart seine Keys.
# ./scripts/setup-vault.sh legt dann einen NEUEN Transit-Key an - der alte,
# in der Cloud gespeicherte DEK laesst sich damit nicht mehr entschluesseln:
#
#   java.security.GeneralSecurityException: decryption failed
#
# Dieses Skript raeumt die verwaisten Keys ab, damit beim naechsten Producer-Lauf
# ein frischer DEK erzeugt wird.
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

if [[ -f .env ]]; then
  set -a
  # shellcheck disable=SC1091
  source .env
  set +a
fi

: "${CC_SCHEMA_REGISTRY_URL:?CC_SCHEMA_REGISTRY_URL fehlt (siehe .env.example)}"
: "${CC_SCHEMA_REGISTRY_API_KEY:?CC_SCHEMA_REGISTRY_API_KEY fehlt}"
: "${CC_SCHEMA_REGISTRY_API_SECRET:?CC_SCHEMA_REGISTRY_API_SECRET fehlt}"

KEK="${1:-vertrag-demo-kek}"
SR="${CC_SCHEMA_REGISTRY_URL%/}"
AUTH="${CC_SCHEMA_REGISTRY_API_KEY}:${CC_SCHEMA_REGISTRY_API_SECRET}"

sr_delete() {
  curl -sS -o /dev/null -u "$AUTH" -X DELETE "$SR/$1" || true
}

echo "Raeume DEK-Registry auf (KEK: $KEK) ..."

DEKS="$(curl -sS -u "$AUTH" "$SR/dek-registry/v1/keks/$KEK/deks" 2>/dev/null || echo '[]')"

if command -v jq >/dev/null && [[ "$DEKS" == \[* ]]; then
  echo "$DEKS" | jq -r '.[]?' | while read -r subject; do
    [[ -n "$subject" ]] || continue
    echo "  - DEK $subject"
    # Erst Soft-, dann Hard-Delete: nur der Hard-Delete gibt den Namen frei.
    sr_delete "dek-registry/v1/keks/$KEK/deks/$subject"
    sr_delete "dek-registry/v1/keks/$KEK/deks/$subject?permanent=true"
  done
fi

echo "  - KEK $KEK"
sr_delete "dek-registry/v1/keks/$KEK"
sr_delete "dek-registry/v1/keks/$KEK?permanent=true"

echo "✓ Fertig. Beim naechsten Producer-Lauf wird ein frischer DEK erzeugt."
