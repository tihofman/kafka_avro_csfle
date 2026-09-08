#!/usr/bin/env bash
#
# Sammelskript fuer den Vortrag - fuehrt einen kompletten Demo-Schritt aus,
# damit man sich waehrend der Praesentation keine Befehle merken muss.
#
# Verwendung:
#   ./scripts/demo.sh plain     Ausgangszustand: alles im Klartext auf dem Broker
#   ./scripts/demo.sh demo1     Kapitel 5: ganze Nachricht verschluesselt
#   ./scripts/demo.sh demo2     Kapitel 7: nur die sensiblen Felder verschluesselt
#   ./scripts/demo.sh consumer  Consumer MIT Vault-Zugriff (entschluesselt alles)
#   ./scripts/demo.sh reset     Generalprobe: Schema, Keys und Topic zuruecksetzen
#   ./scripts/demo.sh status    Preflight-Check (was ist gerade aktiv?)
#   ./scripts/demo.sh teardown  Cloud-Ressourcen loeschen (beendet die Kosten!)
#
# Fuer jeden Schritt gibt es auch einen kurzen Wrapper, z.B. ./scripts/demo1.sh
#
# Optionen:
#   -y   nicht auf ENTER warten (laeuft komplett durch)
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

AUTO=0
ARGS=()
for a in "$@"; do
  case "$a" in
    -y|--yes) AUTO=1 ;;
    *) ARGS+=("$a") ;;
  esac
done
SCHRITT="${ARGS[0]:-}"

TOPIC="vertrag-abschluss"

blau()  { printf '\033[1;36m%s\033[0m\n' "$*"; }
gruen() { printf '\033[1;32m%s\033[0m\n' "$*"; }
grau()  { printf '\033[0;90m%s\033[0m\n' "$*"; }

titel() {
  echo
  blau "════════════════════════════════════════════════════════════════"
  blau "  $*"
  blau "════════════════════════════════════════════════════════════════"
}

# Haelt vor dem "Aha-Moment" an, damit man die Folie erklaeren kann,
# bevor der Broker-Inhalt erscheint.
weiter() {
  [[ "$AUTO" == "1" ]] && return 0
  echo
  read -r -p "$(printf '\033[0;90m%s\033[0m' "[ENTER] $*")" _ || true
  echo
}

produzieren() {
  titel "Producer laeuft (unveraenderter Anwendungscode!)"
  (cd kotlin-demo && gradle runProducer --console=plain -q)
}

roh_ansehen() {
  titel "Roher Broker-Inhalt - das sieht ein fremdes Team"
  ./scripts/consume-raw.sh "$TOPIC" "${1:-8}"
}

case "$SCHRITT" in
  plain)
    titel "Ausgangslage: Schema OHNE Verschluesselungsregel"
    ./scripts/register-schema.sh plain
    produzieren
    weiter "Broker-Inhalt anzeigen ..."
    roh_ansehen
    echo
    gruen "IBAN, Geburtsdatum, Einkommen und Gesundheitsangaben liegen im KLARTEXT."
    grau  "Weiter mit: ./scripts/demo1.sh"
    ;;

  demo1)
    titel "CSFLE aktivieren - alle Felder tragen den Tag ALL"
    ./scripts/register-schema.sh demo1
    produzieren
    weiter "Broker-Inhalt anzeigen ..."
    roh_ansehen
    echo
    gruen "Komplett verschluesselt - kein Feld mehr lesbar."
    grau  "Im Producer-Log steht 'Registered kek vertrag-demo-kek' = Vault wurde benutzt."
    grau  "Weiter mit: ./scripts/demo2.sh"
    ;;

  demo2)
    titel "Nur die sensiblen Felder verschluesseln (Tags PII/PCI/HEALTH)"
    ./scripts/register-schema.sh demo2
    produzieren
    weiter "Broker-Inhalt anzeigen ..."
    roh_ansehen
    echo
    gruen "vertragId, beraterId, produktTyp, status: LESBAR"
    gruen "IBAN, Geburtsdatum, Einkommen, Gesundheit: verschluesselt"
    grau  "Der Anwendungscode wurde NICHT angefasst - nur das Ruleset."
    grau  "Kontrast zeigen mit: ./scripts/consumer.sh"
    ;;

  consumer)
    titel "Consumer MIT Vault-Zugriff"
    (cd kotlin-demo && gradle runConsumer --console=plain -q)
    echo
    gruen "Entschluesselt - ebenfalls ohne eine Zeile Krypto-Code."
    ;;

  reset)
    titel "Zuruecksetzen fuer den naechsten Durchlauf"

    echo "1/4  Schema-Versionen loeschen ..."
    ./scripts/register-schema.sh reset >/dev/null 2>&1 || true

    echo "2/4  Verwaiste DEKs/KEK aus der Registry loeschen ..."
    ./scripts/reset-keys.sh >/dev/null 2>&1 || true

    echo "3/4  Topic neu anlegen (alte Nachrichten wegwerfen) ..."
    confluent kafka topic delete "$TOPIC" --force >/dev/null 2>&1 || true
    sleep 3
    confluent kafka topic create "$TOPIC" --partitions 1 >/dev/null 2>&1 || true
    sleep 2

    echo "4/4  Ausgangszustand 'plain' registrieren ..."
    ./scripts/register-schema.sh plain >/dev/null
    echo
    gruen "Alles zurueckgesetzt. Start mit: ./scripts/plain.sh"
    ;;

  status)
    ./scripts/preflight.sh
    ;;

  teardown)
    # Fragt selbst nach Bestaetigung und beendet die laufenden Cloud-Kosten.
    ./scripts/teardown.sh
    ;;

  *)
    echo "Verwendung: $0 {plain|demo1|demo2|consumer|reset|status|teardown} [-y]" >&2
    echo >&2
    echo "  plain     Ausgangszustand: alles im Klartext auf dem Broker" >&2
    echo "  demo1     Kapitel 5: ganze Nachricht verschluesselt" >&2
    echo "  demo2     Kapitel 7: nur die sensiblen Felder verschluesselt" >&2
    echo "  consumer  Consumer MIT Vault-Zugriff (entschluesselt alles)" >&2
    echo "  reset     Schema, Keys und Topic zuruecksetzen" >&2
    echo "  status    Preflight-Check (was ist gerade aktiv?)" >&2
    echo "  teardown  Cloud-Ressourcen loeschen (beendet die Kosten!)" >&2
    echo >&2
    echo "  -y        nicht auf ENTER warten" >&2
    exit 1
    ;;
esac
