#!/usr/bin/env bash
#
# Registriert das Avro-Schema zusammen mit einem CSFLE-Ruleset in der
# Confluent-Cloud-Schema-Registry.
#
# Umschalten zwischen den beiden Live-Demos = anderes Ruleset registrieren:
#   ./scripts/register-schema.sh demo1   # Ganznachricht  (Kapitel 5)
#   ./scripts/register-schema.sh demo2   # Feldverschluesselung (Kapitel 7)
#
set -euo pipefail

DEMO="${1:-}"
if [[ "$DEMO" != "plain" && "$DEMO" != "demo1" && "$DEMO" != "demo2" && "$DEMO" != "reset" ]]; then
  echo "Verwendung: $0 {plain|demo1|demo2|reset}" >&2
  echo "  plain = OHNE Ruleset -> Klartext auf dem Broker (Ausgangszustand Demo 1)" >&2
  echo "  demo1 = Ganznachricht-Verschluesselung (Tag ALL)" >&2
  echo "  demo2 = Feldverschluesselung (Tags PII/PCI/HEALTH)" >&2
  echo "  reset = alle Schema-Versionen loeschen (fuer die Generalprobe)" >&2
  exit 1
fi

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

SUBJECT="vertrag-abschluss-value"
SCHEMA_FILE="schemas/vertrags-abschluss-event.avsc"

SR_AUTH="${CC_SCHEMA_REGISTRY_API_KEY}:${CC_SCHEMA_REGISTRY_API_SECRET}"

# ACHTUNG (verifiziert): Die Schema Registry dedupliziert identische
# Schema+Ruleset-Kombinationen. Registriert man demo1 erneut, nachdem demo2
# aktiv war, bekommt man zwar die alte Version-ID zurueck - 'latest' bleibt
# aber auf demo2! Der Vortrag laeuft nur vorwaerts (demo1 -> demo2), fuer die
# Generalprobe braucht man deshalb 'reset'.
if [[ "$DEMO" == "reset" ]]; then
  echo "Loesche alle Versionen von $SUBJECT ..."
  curl -sS -u "$SR_AUTH" -X DELETE \
    "${CC_SCHEMA_REGISTRY_URL}/subjects/${SUBJECT}" >/dev/null || true
  # Soft-Delete allein reicht nicht - erst der Hard-Delete gibt das Subject frei.
  curl -sS -u "$SR_AUTH" -X DELETE \
    "${CC_SCHEMA_REGISTRY_URL}/subjects/${SUBJECT}?permanent=true" >/dev/null || true
  echo "✓ Subject zurueckgesetzt. Jetzt wieder mit '$0 demo1' starten."
  exit 0
fi

if [[ "$DEMO" == "demo1" ]]; then
  RULESET_FILE="schemas/ruleset-demo1-ganznachricht.json"
elif [[ "$DEMO" == "demo2" ]]; then
  RULESET_FILE="schemas/ruleset-demo2-feldverschluesselung.json"
else
  RULESET_FILE=""   # plain: bewusst ohne Ruleset
fi

command -v jq >/dev/null || { echo "jq wird benoetigt (brew install jq)" >&2; exit 1; }

# Die im Schema verwendeten Tags muessen im Stream Catalog existieren, bevor ein
# Schema mit 'confluent:tags' registriert werden darf - sonst:
#   42250 "The schema has embedded tags that do not exist"
# Der Aufruf ist idempotent: bereits vorhandene Tags fuehren zu HTTP 409, das
# hier bewusst ignoriert wird.
echo "Stelle sicher, dass die Tag-Definitionen existieren ..."
curl -sS -o /dev/null \
  -u "$SR_AUTH" \
  -H 'Content-Type: application/json' \
  -X POST "${CC_SCHEMA_REGISTRY_URL}/catalog/v1/types/tagdefs" \
  -d '[
        {"name":"ALL","description":"Demo 1: alle Felder","entityTypes":["cf_entity"]},
        {"name":"PII","description":"Personenbezogene Daten","entityTypes":["cf_entity"]},
        {"name":"PCI","description":"Zahlungsdaten","entityTypes":["cf_entity"]},
        {"name":"HEALTH","description":"Gesundheitsdaten","entityTypes":["cf_entity"]}
      ]' || true

# Die Schema-Registry-API erwartet das Avro-Schema als JSON-*String* im Feld
# "schema", das Ruleset danebenliegend als Objekt im Feld "ruleSet".
if [[ -n "$RULESET_FILE" ]]; then
  PAYLOAD="$(jq -n \
    --arg schema "$(jq -c . "$SCHEMA_FILE")" \
    --argjson ruleSet "$(jq -c '.ruleSet' "$RULESET_FILE")" \
    '{schemaType: "AVRO", schema: $schema, ruleSet: $ruleSet}')"
  echo "Registriere $SCHEMA_FILE + $RULESET_FILE"
else
  PAYLOAD="$(jq -n \
    --arg schema "$(jq -c . "$SCHEMA_FILE")" \
    '{schemaType: "AVRO", schema: $schema}')"
  echo "Registriere $SCHEMA_FILE OHNE Ruleset (Klartext auf dem Broker)"
fi

echo "  Subject: $SUBJECT"
echo "  Registry: $CC_SCHEMA_REGISTRY_URL"
echo

HTTP_CODE="$(curl -sS -o /tmp/register-response.json -w '%{http_code}' \
  -u "$SR_AUTH" \
  -H 'Content-Type: application/vnd.schemaregistry.v1+json' \
  -X POST "${CC_SCHEMA_REGISTRY_URL}/subjects/${SUBJECT}/versions" \
  -d "$PAYLOAD")"

if [[ "$HTTP_CODE" == "200" ]]; then
  echo "✓ Registriert als Version-ID: $(jq -r '.id' /tmp/register-response.json)"
else
  echo "✗ Fehler (HTTP $HTTP_CODE):" >&2
  cat /tmp/register-response.json >&2
  echo >&2
  exit 1
fi

echo
echo "Aktuell aktives Ruleset pruefen:"
echo "  curl -u \$CC_SCHEMA_REGISTRY_API_KEY:\$CC_SCHEMA_REGISTRY_API_SECRET \\"
echo "    $CC_SCHEMA_REGISTRY_URL/subjects/$SUBJECT/versions/latest | jq .ruleSet"
