#!/usr/bin/env bash
#
# Raeumt das komplette Demo-Setup wieder ab.
#
# WICHTIG: Das Stream-Governance-Advanced-Paket kostet ca. $1/Stunde, solange
# das Environment existiert. Dieses Skript nach dem Vortrag ausfuehren!
#
set -euo pipefail

ENVIRONMENT="${1:-env-g2k6wn}"

echo "Folgendes wird UNWIDERRUFLICH geloescht:"
echo "  - Confluent Cloud Environment: $ENVIRONMENT"
echo "    (inkl. Kafka-Cluster, Schema Registry, Schemas, Topics und API-Keys)"
echo "  - Lokaler Vault-Container inkl. Transit-Key"
echo
read -r -p "Wirklich loeschen? (tippe 'ja'): " ANTWORT
[[ "$ANTWORT" == "ja" ]] || { echo "Abgebrochen."; exit 0; }

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

echo
echo "Stoppe Vault ..."
docker compose down -v || true

echo
echo "Loesche Confluent Cloud Environment $ENVIRONMENT ..."
confluent environment delete "$ENVIRONMENT" --force

echo
echo "Fertig. Es entstehen keine weiteren Kosten."
echo "Nicht vergessen: .env enthaelt jetzt ungueltige Zugangsdaten."
