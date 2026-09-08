#!/usr/bin/env bash
#
# Zeigt den ROHEN Inhalt des Topics - also genau das, was auf dem Broker liegt,
# ohne CSFLE-Entschluesselung. Das ist der zentrale Moment beider Live-Demos:
#
#   Demo 1 (Kapitel 5): komplette Nachricht chiffriert
#   Demo 2 (Kapitel 7): nur die sensiblen Felder chiffriert, Rest lesbar
#
# Bewusst OHNE Schema-Registry-Konfiguration, damit keine Entschluesselung
# stattfindet - genau so wuerde ein fremdes Team die Daten sehen.
#
# Voraussetzung: confluent CLI, eingeloggt und auf das Demo-Environment gesetzt.
#
set -euo pipefail

TOPIC="${1:-vertrag-abschluss}"
DAUER="${2:-}"

command -v confluent >/dev/null || {
  echo "confluent CLI fehlt: brew install confluentinc/tap/cli" >&2
  exit 1
}

echo "Roher Broker-Inhalt von Topic '$TOPIC':"
echo

# Kein --value-format avro => keine Deserialisierung, keine Entschluesselung.
# Verschluesselte Felder erscheinen als Base64-Zeichensalat, Klartextfelder
# bleiben im Avro-Binaerstrom als lesbarer Text erkennbar.
#
# Ohne zweites Argument laeuft der Consumer bis Strg+C (Live-Demo). Mit einer
# Dauer in Sekunden beendet er sich selbst - das wird fuer die Fallback-
# Aufzeichnungen gebraucht, da die Confluent CLI keinen Timeout-Flag kennt.
if [[ -n "$DAUER" ]]; then
  confluent kafka topic consume "$TOPIC" \
    --from-beginning \
    --print-key \
    --delimiter ' | ' 2>/dev/null &
  CONSUMER_PID=$!
  sleep "$DAUER"
  kill "$CONSUMER_PID" 2>/dev/null || true
  wait "$CONSUMER_PID" 2>/dev/null || true
else
  echo "(Abbruch mit Strg+C)"
  echo
  confluent kafka topic consume "$TOPIC" \
    --from-beginning \
    --print-key \
    --delimiter ' | '
fi
