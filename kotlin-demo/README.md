# Kotlin-Demo: Kafka CSFLE mit Avro

Producer und Consumer für die beiden Live-Demos des Vortrags "Kafka ohne Klartext".

## Die zentrale Botschaft

**In diesem Code steht kein einziger Verschlüsselungs-Aufruf.**

Producer und Consumer benutzen ganz normal den `KafkaAvroSerializer` bzw.
`KafkaAvroDeserializer`. Ob und welche Felder verschlüsselt werden, entscheidet
allein das **Ruleset am Schema in der Schema Registry**. Der Wechsel zwischen
Demo 1 (ganze Nachricht) und Demo 2 (nur sensible Felder) ist deshalb reine
Konfiguration – die Anwendung wird nicht angefasst und nicht neu gebaut.

## Voraussetzungen

- JDK 21
- Confluent Cloud Account mit **Stream Governance Advanced** (nötig für CSFLE)
- Lokales Vault (`docker compose up -d vault` + `./scripts/setup-vault.sh`)
- `.env` im Projekt-Root (Vorlage: `.env.example`)

## Ablauf einer Demo

```bash
# 1. Vault starten und Transit-Key anlegen (Vault ist in-memory -> jedes Mal nötig)
docker compose up -d vault
./scripts/setup-vault.sh

# 2. Preflight: prüft .env, Vault-Key, Schema Registry und Topic
./scripts/preflight.sh

# 3. Ausgangszustand zeigen: OHNE Ruleset -> alles im Klartext auf dem Broker
./scripts/register-schema.sh plain
cd kotlin-demo && gradle runProducer && cd ..
./scripts/consume-raw.sh

# 4. Demo 1 (Kapitel 5): ganze Nachricht verschlüsseln
./scripts/register-schema.sh demo1
cd kotlin-demo && gradle runProducer && cd ..
./scripts/consume-raw.sh

# 5. Demo 2 (Kapitel 7): nur sensible Felder verschlüsseln
./scripts/register-schema.sh demo2
cd kotlin-demo && gradle runProducer && cd ..
./scripts/consume-raw.sh

# 6. Kontrast: Consumer mit Vault-Zugriff sieht wieder Klartext
cd kotlin-demo && gradle runConsumer
```

Vor der Generalprobe zurücksetzen:

```bash
./scripts/register-schema.sh reset
confluent kafka topic delete vertrag-abschluss --force
confluent kafka topic create vertrag-abschluss --partitions 1
```

## Preflight-Check

`gradle runProducer` und `gradle runConsumer` führen automatisch vorher den Task
`preflight` aus und brechen ab, wenn etwas nicht stimmt. Geprüft wird:

1. Alle 8 Konfigurationswerte in `.env` vorhanden
2. Vault erreichbar **und** Transit-Key `csfle-demo` vorhanden
3. Schema Registry erreichbar, Subject registriert – inkl. Anzeige, welcher Modus
   gerade aktiv ist (`plain` / `demo1` / `demo2`)
4. Kafka-Cluster erreichbar und Topic vorhanden

Jeder Fehler nennt direkt den Befehl zur Behebung. Der häufigste Fall ist ein
Vault-Neustart – dann fehlt der Transit-Key, weil der Dev-Mode in-memory läuft.

## Wichtige Konfigurationsdetails

Diese Einstellungen in `DemoConfig.kt` sind für CSFLE entscheidend:

| Property | Wert | Warum |
|---|---|---|
| `auto.register.schemas` | `false` | Sonst überschreibt der Client das serverseitig gepflegte Ruleset |
| `use.latest.version` | `true` | Der Client muss die registrierte Version **mit** Ruleset benutzen |
| `rule.executors._default_.param.token.id` | Vault-Token | Zugangsdaten für den Vault-KMS-Driver |

Der Encryption-Executor und der Vault-KMS-Driver registrieren sich per
`ServiceLoader` selbst – es ist keine manuelle Registrierung im Code nötig.

## Stolperfallen

- **`encrypt.kms.key.id` darf kein `/v1/` enthalten.** Richtig ist
  `http://127.0.0.1:8200/transit/keys/csfle-demo`. Das Präfix `hcvault://`
  setzt der Client anhand von `encrypt.kms.type` selbst davor.
- **`127.0.0.1` statt `vault`**: Der Kotlin-Client läuft auf dem Host, nicht im
  Docker-Netz – der Container-Hostname wäre dort nicht auflösbar.
- **CSFLE verschlüsselt nur `string`/`bytes`.** Deshalb sind im Schema bewusst
  alle Felder als `string` modelliert (siehe `spec.md`).
