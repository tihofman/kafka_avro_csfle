#!/usr/bin/env bash
#
# Erzeugt die Fallback-Aufzeichnungen fuer beide Live-Demos.
#
# Zweck: Falls beim Vortrag die Internetverbindung zu Confluent Cloud fehlt,
# koennen die Demos als Terminal-Video abgespielt werden - sieht aus wie live,
# ohne Live-Risiko.
#
# Ergebnis:
#   recordings/demo1.cast + demo1.gif   (Klartext -> Ganznachricht verschluesselt)
#   recordings/demo2.cast + demo2.gif   (Feldverschluesselung + Consumer)
#
# Voraussetzung: asciinema und agg (brew install asciinema agg),
# funktionierendes Setup (./scripts/preflight.sh muss gruen sein).
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

WELCHE="${1:-alle}"

command -v asciinema >/dev/null || { echo "asciinema fehlt: brew install asciinema" >&2; exit 1; }
command -v agg >/dev/null || { echo "agg fehlt: brew install agg" >&2; exit 1; }

mkdir -p recordings

# Wird innerhalb der Aufzeichnung ausgefuehrt (siehe --command unten).
if [[ "${1:-}" == "--inner-demo1" || "${1:-}" == "--inner-demo2" ]]; then

  # Simuliert Tippen, damit die Aufzeichnung nicht wie ein Log-Dump wirkt.
  tippe() {
    printf '\033[1;32m$\033[0m '
    local text="$1"
    for (( i=0; i<${#text}; i++ )); do
      printf '%s' "${text:$i:1}"
      sleep 0.02
    done
    printf '\n'
    sleep 0.4
  }

  kommentar() {
    printf '\033[1;36m# %s\033[0m\n' "$1"
    sleep 1.2
  }

  if [[ "$1" == "--inner-demo1" ]]; then
    kommentar "Ausgangslage: Schema OHNE Verschluesselungsregel"
    tippe "./scripts/register-schema.sh plain"
    ./scripts/register-schema.sh plain 2>&1 | grep -E "Registriere|✓"
    echo; sleep 1

    tippe "cd kotlin-demo && gradle runProducer"
    (cd kotlin-demo && gradle runProducer --console=plain -q 2>&1 | grep -E "✓ VA|Fertig")
    echo; sleep 1

    kommentar "Was liegt jetzt auf dem Broker?"
    tippe "./scripts/consume-raw.sh"
    ./scripts/consume-raw.sh vertrag-abschluss 12
    echo; sleep 2

    kommentar "IBAN, Geburtsdatum, Einkommen, Gesundheitsdaten - alles im Klartext!"
    sleep 2
    kommentar "Jetzt CSFLE aktivieren: alle Felder tragen den Tag ALL"
    tippe "./scripts/register-schema.sh demo1"
    ./scripts/register-schema.sh demo1 2>&1 | grep -E "Registriere|✓"
    echo; sleep 1

    tippe "cd kotlin-demo && gradle runProducer"
    (cd kotlin-demo && gradle runProducer --console=plain -q 2>&1 | grep -E "✓ VA|Fertig|Registered kek")
    echo; sleep 1

    kommentar "Gleicher Producer-Code, gleiche Daten - nochmal auf den Broker schauen"
    tippe "./scripts/consume-raw.sh"
    ./scripts/consume-raw.sh vertrag-abschluss 12
    echo; sleep 2
    kommentar "Komplett verschluesselt. Kein Feld mehr lesbar."
    sleep 2

  else
    kommentar "Problem: jetzt ist auch fuer Reporting/Monitoring nichts mehr lesbar"
    sleep 1
    kommentar "Loesung: nur die sensiblen Felder verschluesseln (Tags PII/PCI/HEALTH)"
    tippe "./scripts/register-schema.sh demo2"
    ./scripts/register-schema.sh demo2 2>&1 | grep -E "Registriere|✓"
    echo; sleep 1

    tippe "cd kotlin-demo && gradle runProducer"
    (cd kotlin-demo && gradle runProducer --console=plain -q 2>&1 | grep -E "✓ VA|Fertig|Registered kek")
    echo; sleep 1

    kommentar "Der Anwendungscode wurde NICHT angefasst - nur das Ruleset"
    tippe "./scripts/consume-raw.sh"
    ./scripts/consume-raw.sh vertrag-abschluss 12
    echo; sleep 2

    kommentar "vertragId, beraterId, produktTyp, status: lesbar"
    kommentar "IBAN, Geburtsdatum, Einkommen, Gesundheit: verschluesselt"
    sleep 2

    kommentar "Und ein Consumer MIT Vault-Zugriff?"
    tippe "cd kotlin-demo && gradle runConsumer"
    (cd kotlin-demo && gradle runConsumer --console=plain -q 2>&1 | grep -E "──|   [a-z]" | head -20)
    echo; sleep 2
    kommentar "Entschluesselt - ebenfalls ohne eine Zeile Krypto-Code."
    sleep 2
  fi
  exit 0
fi

aufnehmen() {
  local name="$1"
  echo
  echo "=== Nehme $name auf ==="
  rm -f "recordings/$name.cast"
  asciinema rec "recordings/$name.cast" \
    --headless \
    --window-size 120x32 \
    --idle-time-limit 2 \
    --title "Kafka ohne Klartext - $name" \
    --command "$ROOT/scripts/record-demos.sh --inner-$name" \
    --overwrite

  echo "Erzeuge recordings/$name.gif ..."
  agg --quiet --cols 120 --rows 32 --font-size 16 --speed 1.4 \
    "recordings/$name.cast" "recordings/$name.gif"
  echo "✓ recordings/$name.cast + recordings/$name.gif"

  # Slidev liefert nur Dateien aus public/ aus -> dorthin spiegeln.
  # Die Folien binden den asciinema-Player ein und brauchen den Cast im
  # v2-Format; asciinema zeichnet standardmaessig in v3 auf.
  mkdir -p public
  asciinema convert --output-format asciicast-v2 --overwrite \
    "recordings/$name.cast" "public/$name-v2.cast"
  cp "recordings/$name.gif" "public/$name.gif"
  echo "✓ public/$name-v2.cast (fuer den Player in den Folien)"
}

# Sauberer Ausgangszustand, damit die Aufzeichnung reproduzierbar ist.
vorbereiten() {
  echo "Setze Schema, Keys und Topic zurueck ..."
  ./scripts/register-schema.sh reset >/dev/null 2>&1 || true
  # Verwaiste DEKs entfernen, sonst schlaegt der Producer mit
  # "decryption failed" fehl, falls Vault zwischenzeitlich neu gestartet wurde.
  ./scripts/reset-keys.sh >/dev/null 2>&1 || true
  confluent kafka topic delete vertrag-abschluss --force >/dev/null 2>&1 || true
  sleep 3
  confluent kafka topic create vertrag-abschluss --partitions 1 >/dev/null 2>&1 || true
  sleep 2
}

case "$WELCHE" in
  demo1) vorbereiten; aufnehmen demo1 ;;
  demo2) aufnehmen demo2 ;;
  alle)  vorbereiten; aufnehmen demo1; aufnehmen demo2 ;;
  *) echo "Verwendung: $0 [demo1|demo2|alle]" >&2; exit 1 ;;
esac

echo
echo "Fertig. Abspielen mit:  asciinema play recordings/demo1.cast"
