#!/usr/bin/env bash
# Richtet die HashiCorp Vault Transit Engine + den CSFLE-Demo-Key ein.
# Muss nach jedem Neustart des vault-Containers erneut ausgefuehrt werden,
# da Vault im Dev-Mode (--dev) alle Daten nur in-memory haelt.
#
# WICHTIG: Wird hier ein NEUER Transit-Key angelegt, sind die in der Confluent
# Cloud gespeicherten DEKs unbrauchbar (sie wurden mit dem alten Key
# verschluesselt) -> "GeneralSecurityException: decryption failed".
# Deshalb raeumt dieses Skript die DEK-Registry in dem Fall automatisch mit auf.
#
# Nutzung: ./scripts/setup-vault.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [[ -f "$ROOT/.env" ]]; then
  set -a
  # shellcheck disable=SC1091
  source "$ROOT/.env"
  set +a
fi

VAULT_ADDR="${VAULT_ADDR:-http://127.0.0.1:8200}"
VAULT_TOKEN="${VAULT_TOKEN:-root-token}"
KEY_NAME="csfle-demo"

echo "Warte auf Vault unter $VAULT_ADDR ..."
for i in $(seq 1 30); do
  if curl -s -o /dev/null -w "%{http_code}" "$VAULT_ADDR/v1/sys/health" | grep -q "200"; then
    break
  fi
  sleep 1
done

# Vorher pruefen, ob der Key schon existiert - daran haengt, ob die DEKs in der
# Cloud noch gueltig sind.
KEY_EXISTIERTE=$(curl -s -o /dev/null -w "%{http_code}" \
  -H "X-Vault-Token: $VAULT_TOKEN" "$VAULT_ADDR/v1/transit/keys/$KEY_NAME")

echo "Aktiviere Transit Secrets Engine ..."
curl -s -H "X-Vault-Token: $VAULT_TOKEN" -X POST -d '{"type":"transit"}' \
  "$VAULT_ADDR/v1/sys/mounts/transit" > /dev/null || true

echo "Lege Transit-Key '$KEY_NAME' an ..."
curl -s -H "X-Vault-Token: $VAULT_TOKEN" -X POST -d '{"type":"aes256-gcm96"}' \
  "$VAULT_ADDR/v1/transit/keys/$KEY_NAME" > /dev/null

if [[ "$KEY_EXISTIERTE" == "200" ]]; then
  echo "Key war bereits vorhanden - DEKs in der Cloud bleiben gueltig."
else
  echo
  echo "NEUER Transit-Key angelegt (Vault wurde offenbar neu gestartet)."
  echo "Die in Confluent Cloud gespeicherten DEKs sind damit unbrauchbar."
  if [[ -n "${CC_SCHEMA_REGISTRY_URL:-}" ]]; then
    "$ROOT/scripts/reset-keys.sh" || true
  else
    echo "  ! .env fehlt - bitte manuell ausfuehren: ./scripts/reset-keys.sh"
  fi
fi

echo
echo "Fertig. Vault Transit Key '$KEY_NAME' ist einsatzbereit."
