# Spec: Vortrag "Kafka ohne Klartext" (~30 Min)

## Ziel & Format
- Dauer: ca. 30 Minuten
- Aufbau: Problem → Lösung → neues Problem → Lösung (Kettenprinzip, kein Nebeneinander von Themen)
- Technische Basis für Verschlüsselungs-Demos: Confluent Cloud CSFLE (Client-Side Field Level Encryption) + Avro/Schema Registry
- Tool: Slidev (bestehendes Projekt, slides.md wird überarbeitet/ersetzt)

## Durchgängiges Beispiel: VertragsAbschluss-Event

Szenario aus dem Finanz-/Versicherungsberatungs-Umfeld (DVAG-Kontext): Ein Berater schließt für einen Kunden einen Vorsorge-/Versicherungsvertrag ab, das Event wird auf Kafka publiziert.

**Unkritische Felder** (für Reporting, Provisionsstatistik, Monitoring):
- `vertragId`, `beraterId`, `produktTyp` (z. B. "Altersvorsorge", "Berufsunfähigkeit", "Bausparvertrag"), `abschlussDatum`, `status`

**Sensible Felder** (PII / besondere Kategorien):
- `kundenIban`, `geburtsdatum`, `einkommen`, ggf. `gesundheitsangaben` (bei Berufsunfähigkeitsversicherung)

**Mehrere Consumer mit unterschiedlichem Bedarf** (wichtig als Begründung für Feldverschlüsselung in Kapitel 6/7):
- **Provisionsabrechnung** braucht `kundenIban`
- **Vertriebs-Reporting/Analytics** braucht nur `produktTyp`/`abschlussDatum`, keine Personendaten
- **Compliance-Monitoring** braucht nur `status`, keine Finanz-/Gesundheitsdetails

## Kapitel-/Argumentationskette

> Nummerierung entspricht 1:1 den Kapitelüberschriften in `slides.md`. Das ursprünglich eigenständige Kapitel "In-Transit/TLS" wurde beim Feintuning in Kapitel 4 integriert, ebenso wurden die beiden Folien von Kapitel 1 zusammengelegt (Zeitbudget).

### 0. Kurze Kafka-Auffrischung (bewusst sehr knapp)
- Publikum hat bereits Kafka-Vorwissen → kein Deep-Dive, nur kurze Erinnerung nach dem Motto "wissen wir eigentlich schon, aber trotzdem kurz"
- 1-2 Folien max.: Topics, Producer/Consumer, Broker, Pub/Sub-Entkopplung
- Zweck: gemeinsame Begriffsbasis für den Rest des Vortrags, keine Grundlagenschulung

### 1. Problem: Ein Kafka-taugliches Szenario mit kritischen Daten
- Einführung des VertragsAbschluss-Events als Beispiel
- Zeigen, warum Kafka als Streaming-Plattform hier die richtige Wahl ist (viele Consumer, Entkopplung, Skalierung)
- Aber: Event enthält sensible Felder → Risiko, sobald mehrere Consumer-Gruppen/Teams mitlesen

### 2. Zwischenschritt: Daten sehen nicht immer gleich aus
- Kurzer Blick darauf, dass Producer unterschiedliche Strukturen/Formate schicken können (Feldnamen, Typen, fehlende/zusätzliche Felder)
- Konsequenz: Consumer müssen robust parsen, Verträge zwischen Teams sind unklar ohne Schema

### 3. Lösung: Avro sorgt für einheitliches, parsebares Schema
- Avro-Schema als Vertrag zwischen Producer und Consumer
- Schema Registry sorgt für Kompatibilität/Evolution
- Ergebnis: Daten haben verlässliche Struktur, können typsicher geparst werden
- (Datenschutz-Frage ist an dieser Stelle noch offen)

### 4. Problem: At-Rest liegt der Klartext weiterhin offen
*(inkl. kurzem Recap: In-Transit ist bereits durch TLS/HTTPS zwischen Client und Broker abgesichert – das ist der Ausgangspunkt, nicht das Problem)*
- Auf dem Broker/Topic liegen die Avro-Daten unverschlüsselt vor
- Jeder mit Zugriff auf das Topic (Consumer, Tools, Admins, Fehlkonfigurationen) sieht sensible Felder im Klartext
- Das ist das eigentliche Kernproblem des Vortrags

### 5. Lösung: Verschlüsselung der kompletten Avro-Nachricht (CSFLE, ganze Message)
- Zeigen, wie mit CSFLE die gesamte Nachricht clientseitig vor dem Schreiben verschlüsselt wird
- Vorteil: Klartext verschwindet komplett vom Broker
- **Live-Demo 1**: Blick auf den Broker-Inhalt vorher (Klartext) vs. nachher (Ganznachricht verschlüsselt)

### 6. Neues Problem: Volltext-Verschlüsselung ist zu grobgranular
- Consumer, Monitoring/Observability, Schema Registry-basiertes Routing und Filterung können nicht mehr auf unkritische Felder zugreifen
- Nicht alle Felder sind schützenswert – Analytik/Aggregation auf unkritischen Feldern wird unnötig blockiert

### 7. Lösung: Feldverschlüsselung (Field-Level CSFLE)
- Nur getaggte/sensible Felder (z. B. `kundenIban`, `geburtsdatum`, `einkommen`) werden verschlüsselt
- Nicht-sensitive Felder bleiben im Klartext lesbar für Routing/Filter/Aggregation
- Schema mit `confluent:tags` (z. B. PII/PCI) als Steuerungsmechanismus zeigen
- **Live-Demo 2**: Blick auf den Broker-Inhalt – nur sensible Felder verschlüsselt, Rest bleibt lesbar (Kontrast zu Demo 1)

### 8. Neues Problem: Wer verwaltet die Schlüssel für die Feldverschlüsselung?
- Feldverschlüsselung braucht Data Encryption Keys (DEK) – aber wo werden die sicher erzeugt, gespeichert, rotiert?
- Ohne zentrale Verwaltung: Schlüssel verstreut, keine Rotation, kein Audit, Compliance-Risiko bleibt bestehen

### 9. Lösung: Zentrales Key-Management mit KMS & Envelope Encryption
*(Zeitbudget: Kapitel 8+9 zusammen ca. 5-6 Minuten, inkl. eigener Folie für Rotations-Ablauf)*
- Root of Trust im externen KMS (z. B. AWS KMS / Azure Key Vault / GCP KMS; in der Demo HashiCorp Vault)
- Envelope Encryption: DEK verschlüsselt Daten, KEK (im KMS) verschlüsselt DEK
- Klare IAM-Policies: Producer/Consumer erhalten nur die Rechte, die sie brauchen
- Eigene Folie – Rotation & Betrieb:
  1. Neue Schlüsselversion im KMS aktivieren
  2. Producer verschlüsseln neue Events mit neuer Version
  3. Consumer unterstützen mehrere Versionen für Übergangszeit
  4. Optionales Re-Encryption von Bestandsdaten nach Risiko-/Kostenbewertung

### Fazit
- Avro = verlässliches Schema, CSFLE = gezielte Feldverschlüsselung, KMS + Rotation = betreibbar

## Avro-Schema: VertragsAbschlussEvent

Datei: `schemas/vertrags-abschluss-event.avsc`

**Wichtige Design-Entscheidung**: CSFLE kann nur Felder vom Typ `string` oder `bytes` verschlüsseln (keine `int`, `enum`, logischen Typen wie `date`/`decimal`). Damit in Kapitel 5 wirklich *alle* Felder verschlüsselbar sind, sind bewusst **alle Felder als `string` modelliert** (auch `abschlussDatum` als ISO-8601-String, `produktTyp`/`status` als String statt Avro-Enum, `einkommen` als String-Repräsentation einer Zahl). Das ist eine didaktische Vereinfachung, keine Produktionsempfehlung.

Ein einziges Schema wird für beide Demos genutzt – gesteuert wird nur über **zwei unterschiedliche Encryption-Rulesets (Tags)**:

- Jedes Feld trägt den Tag `ALL`
- Zusätzlich tragen die sensiblen Felder eigene Tags: `kundenIban` → `PCI`; `geburtsdatum`, `einkommen`, `gesundheitsangaben` → `PII` (und `gesundheitsangaben` zusätzlich `HEALTH`)

**Demo 1 (Kapitel 5, Ganznachricht)**: `schemas/ruleset-demo1-ganznachricht.json` – Encryption-Rule greift auf Tag `ALL` → jedes Feld wird verschlüsselt, Ergebnis wirkt wie eine komplett verschlüsselte Nachricht.

**Demo 2 (Kapitel 7, Feldverschlüsselung)**: `schemas/ruleset-demo2-feldverschluesselung.json` – Encryption-Rule greift nur auf Tags `PII`/`PCI`/`HEALTH` → nur `kundenIban`, `geburtsdatum`, `einkommen`, `gesundheitsangaben` werden verschlüsselt, Rest bleibt lesbar.

Beide Rulesets nutzen denselben Vault-Transit-Key (`encrypt.kms.type: hcvault`, KEK-Name `vertrag-demo-kek`, Key-Pfad `http://vault:8200/v1/transit/keys/csfle-demo`) – der Transit-Key `csfle-demo` muss vor der Demo in Vault angelegt werden.

Registrierung erfolgt über die Schema-Registry-REST-API: zuerst das Schema unter `<TOPIC>-value` registrieren, danach für Demo 1 bzw. Demo 2 das jeweilige Ruleset als neue Version mit demselben Schema hochladen (Umschalten zwischen den Demos = Ruleset austauschen).

## Beispieldaten

Datei: `examples/vertrag-events.json` – drei realistische, aber komplett fiktive VertragsAbschlussEvents (gegen das Avro-Schema mit `fastavro` erfolgreich validiert/rundgetestet):

1. **Berufsunfähigkeitsversicherung** (`status: AKTIV`) – einziges Beispiel mit befülltem `gesundheitsangaben`-Feld, zeigt den Fall mit allen vier sensiblen Feldern gleichzeitig
2. **Altersvorsorge** (`status: EINGEREICHT`) – `gesundheitsangaben: null`, zeigt den Normalfall ohne Gesundheitsdaten
3. **Bausparvertrag** (`status: ENTWURF`) – zweites Beispiel ohne Gesundheitsdaten, anderer Berater/Kunde für Abwechslung in der Demo

Alle IBANs sind fiktive/Test-IBANs (u. a. die bekannte Bundesbank-Beispiel-IBAN), keine echten Kontodaten.

## Live-Demo-Konzept
- Kein durchgängiges Live-Setup; 2 gezielte Live-Demos an Schlüsselstellen
- Tool: Confluent CLI (`confluent kafka topic consume`) bzw. `kafka-console-consumer` mit Confluent-Cloud-Verbindungsdaten, um den rohen Topic-Inhalt anzuzeigen
- **Demo 1** (bei Kapitel 5): Topic-Inhalt vorher (Klartext) vs. nachher (komplette Nachricht verschlüsselt)
- **Demo 2** (bei Kapitel 7): Topic-Inhalt mit Feldverschlüsselung – nur sensible Felder chiffriert, Rest bleibt lesbar
- Restliche Folien: konzeptionell mit Code-Snippets/Schema-Beispielen/Diagrammen
- **Fallback**: Beide Demos vorab mit `asciinema` (oder vergleichbarem Terminal-Recorder) aufzeichnen und als abspielbares GIF/Video einbetten, falls die Live-Demo während des Vortrags nicht funktioniert (z. B. keine Internetverbindung zu Confluent Cloud vor Ort) – wirkt wie live, ohne Live-Risiko

## Demo-Setup: Confluent Cloud + lokales Vault

Die Live-Demos laufen **hybrid**: Kafka-Broker und Schema Registry laufen gehostet in **Confluent Cloud** (nicht mehr lokal via Confluent Platform), HashiCorp Vault (KMS) läuft weiterhin lokal via docker-compose.

**Grund für den Wechsel**: Lokales CSFLE auf Confluent Platform benötigt eine Enterprise-Lizenz inkl. CSFLE-Add-on, die nicht per Self-Service erhältlich ist (Support/Sales-Kontakt mit Vorlaufzeit nötig). Confluent Cloud bietet CSFLE direkt gegen Verbrauch des kostenlosen Trial-Guthabens, ohne Sales-Kontakt.

**Kostenmodell Confluent Cloud (Stand der Recherche)**:
- Neue Accounts erhalten **$400 Startguthaben**, gültig 30 Tage, **keine Kreditkarte nötig** um zu starten
- CSFLE erfordert das **"Stream Governance Advanced"**-Paket (nicht das kostenlose "Essentials") – **ab $1/Stunde** pro Environment
- Zusätzlich normale Kafka-Cluster-Kosten (Basic-Tier, sehr gering) und ggf. Kosten pro aktiver Encryption-Regel
- Für die kurze Vorbereitungs-/Demo-Zeit bleibt der Verbrauch voraussichtlich weit unter dem Guthaben – Environment nach der Demo löschen/pausieren, um Kosten zu vermeiden

**Komponenten:**
- **Confluent Cloud**: Kafka-Cluster (Basic) + Schema Registry mit Stream Governance **Advanced**-Paket
- **HashiCorp Vault** (Transit Engine, lokal via `docker-compose.yml`) als KMS für Envelope Encryption/DEK-Verwaltung – unterstützt von Confluent Cloud CSFLE nativ (`encrypt.kms.type: hcvault`), da die Ver-/Entschlüsselung clientseitig im Producer/Consumer passiert und Vault von dort erreichbar sein muss
- **Kotlin**-Producer/Consumer-Beispielapplikationen (VertragsAbschluss-Event), die gegen Confluent Cloud (Kafka + Schema Registry) und lokales Vault sprechen
- **`kafka-console-consumer`** (oder Confluent CLI gegen Confluent Cloud) zum Anzeigen des rohen Topic-Inhalts in den Live-Demos

**Offene Detailfragen für die Umsetzung:**
- Confluent Cloud Account anlegen, Cluster + Environment mit Stream Governance Advanced erstellen
- API-Keys für Kafka-Cluster und Schema Registry erzeugen, in `.env` eintragen (siehe `.env.example`)
- ~~Vault Transit Engine + Key `csfle-demo` in Vault anlegen~~ **erledigt**: `scripts/setup-vault.sh` aktiviert die Transit Engine und legt den Key `csfle-demo` (AES256-GCM96) an; Encrypt/Decrypt-Roundtrip über die Vault-API verifiziert. Da Vault im Dev-Mode in-memory läuft, muss das Skript nach jedem `docker compose up vault` erneut ausgeführt werden.
- Vault muss von Confluent Cloud CSFLE-Clients aus erreichbar sein (lokal ist das ok, da CSFLE-Verschlüsselung im Kotlin-Client passiert, nicht im Cloud-Cluster selbst)

## Stand der Umsetzung

**Erledigt:**
- [x] Spec/Argumentationskette final abgestimmt
- [x] Avro-Schema `schemas/vertrags-abschluss-event.avsc` + beide Rulesets entworfen und JSON-validiert
- [x] Beispieldaten `examples/vertrag-events.json` erstellt und gegen das Schema validiert
- [x] Vault Transit Engine + Key `csfle-demo` via `scripts/setup-vault.sh` (Encrypt/Decrypt-Roundtrip verifiziert). Vault läuft im Dev-Mode in-memory → Skript nach jedem `docker compose up vault` erneut ausführen
- [x] `docker-compose.yml` auf die Hybrid-Architektur reduziert (nur noch `vault`)
- [x] `slides.md` vollständig ausgearbeitet: Kapitelkette 0-9, Speaker Notes mit Zeitbudget je Folie, Gesamtzeit ca. 30 Min, Build via `npx slidev build` validiert
- [x] Kotlin-Producer/Consumer in `kotlin-demo/` implementiert, Gradle-Build erfolgreich, CSFLE-Abhängigkeiten aufgelöst und Vault-Parameternamen gegen die JARs verifiziert
- [x] Skripte `scripts/register-schema.sh` (Ruleset-Umschaltung), `scripts/consume-raw.sh` (roher Broker-Inhalt) und `scripts/teardown.sh` erstellt
- [x] Confluent Cloud Environment `env-g2k6wn` mit Stream Governance Advanced, Cluster, Schema Registry, API-Keys und Topic eingerichtet
- [x] **Beide Demos vollständig gegen Confluent Cloud verifiziert** – Verschlüsselung auf dem Broker und Entschlüsselung im Consumer funktionieren
- [x] Preflight-Check (`PreflightApp.kt` + Gradle-Task, automatisch vor jedem Producer-/Consumer-Lauf); Gut- und Fehlerfall real getestet
- [x] `scripts/reset-keys.sh` gegen den Envelope-Encryption-Bruch nach Vault-Neustart; automatisch an `setup-vault.sh` gekoppelt und durch echten Vault-Neustart verifiziert
- [x] Fallback-Aufzeichnungen für beide Demos (asciinema), als steuerbarer asciinema-Player hinter einem `v-click` auf den Demo-Folien eingebunden; in Build **und** Dev-Server im Browser verifiziert

**Noch offen (in Bearbeitungsreihenfolge):**
1. Generalprobe mit Zeitmessung gegen das 30-Minuten-Budget
2. Nach dem Vortrag: `./scripts/teardown.sh` ausführen (beendet die laufenden Kosten!)

## Kotlin-Demo-Applikationen

Verzeichnis: `kotlin-demo/` – Gradle-Projekt (Kotlin JVM 21), siehe auch `kotlin-demo/README.md`.

**Kernaussage der Demo**: Im Anwendungscode steht **kein einziger Verschlüsselungs-Aufruf**. Producer und Consumer nutzen den normalen `KafkaAvroSerializer`/`-Deserializer`. Ob und welche Felder verschlüsselt werden, entscheidet allein das Ruleset am Schema in der Registry – der Wechsel von Demo 1 auf Demo 2 ist reine Konfiguration, die Anwendung wird nicht neu gebaut.

- **Producer** (`ProducerApp.kt`): liest `examples/vertrag-events.json`, baut daraus Avro-`GenericRecord`s und schreibt sie ins Topic `vertrag-abschluss`.
- **Consumer** (`ConsumerApp.kt`): liest die Events zurück und gibt sie feldweise entschlüsselt aus – Kontrast zum rohen Broker-Inhalt.
- **`DemoConfig.kt`**: zentrale Konfiguration, liest ausschließlich aus Umgebungsvariablen bzw. `.env` (keine Secrets im Code).

**Verifizierte Abhängigkeiten** (Confluent 8.3.1, Build erfolgreich getestet):
- Confluent-Artefakte liegen **nicht** auf Maven Central → Repository `https://packages.confluent.io/maven/` nötig
- `io.confluent:kafka-avro-serializer`
- `io.confluent:kafka-schema-registry-client-encryption-hcvault` – zieht transitiv `client-encryption` (Encryption-Executor), `client-encryption-tink`, Google Tink und den Vault-Java-Driver mit
- **Nicht** `kafka-schema-rules` – das enthält nur CEL/JSONata-Regeln, nicht die Verschlüsselung
- Executor und KMS-Driver registrieren sich per `ServiceLoader` selbst, keine manuelle Registrierung im Code

**Für CSFLE entscheidende Client-Properties:**
- `auto.register.schemas=false` – sonst überschreibt der Client das serverseitig gepflegte Ruleset
- `use.latest.version=true` – der Client muss die registrierte Version *mit* Ruleset verwenden
- `rule.executors._default_.param.token.id` – Vault-Token für den KMS-Driver (Parametername aus `HcVaultKmsDriver` verifiziert)

**Verifizierte Stolperfallen:**
- `encrypt.kms.key.id` darf **kein `/v1/`** enthalten: korrekt ist `http://127.0.0.1:8200/transit/keys/csfle-demo`. Das Präfix `hcvault://` ergänzt der Client anhand von `encrypt.kms.type` selbst.
- `127.0.0.1` statt Container-Hostname `vault`, da der Kotlin-Client auf dem Host läuft und nicht im Docker-Netz.

## Confluent Cloud: eingerichtete Ressourcen

Am 2026-08-31 in der Org **compeople** (kein privater Trial – Kosten laufen auf den Firmenaccount!) angelegt:

| Ressource | ID / Wert |
|---|---|
| Environment | `env-g2k6wn` (`csfle-demo`), Stream Governance **ADVANCED** |
| Kafka-Cluster | `lkc-38wq7r0` (`csfle-demo-cluster`), Basic, AWS `eu-central-1` |
| Bootstrap | `pkc-7xoy1.eu-central-1.aws.confluent.cloud:9092` |
| Schema Registry | `lsrc-nvxdkw6`, `https://psrc-do01d.eu-central-1.aws.confluent.cloud` |
| Topic | `vertrag-abschluss` (1 Partition) |

Zugangsdaten stehen in `.env` (nicht im Repo). Ein bewusst separates Environment wurde gewählt, weil ein Downgrade von `advanced` auf `essentials` nach dem Provisionieren der Schema Registry **nicht mehr möglich** ist – Aufräumen geht nur durch Löschen des ganzen Environments.

> ⚠️ **Kosten**: Stream Governance Advanced kostet ca. $1/Stunde, solange das Environment existiert. Nach dem Vortrag zwingend `./scripts/teardown.sh` ausführen.

**Benötigte Tooling-Installation**: `brew install confluentinc/tap/cli` (v4.74 getestet). Die Confluent CLI ersetzt auch `kafka-console-consumer`, eine komplette Kafka-Distribution ist nicht nötig.

## Verifizierter Ende-zu-Ende-Durchlauf

Beide Demos wurden am 2026-08-31 vollständig gegen Confluent Cloud getestet und funktionieren. Alle drei Zustände sind reproduzierbar:

**Ausgangszustand `plain`** (ohne Ruleset) – der Schock-Moment für Kapitel 4, alles im Klartext:
```
VA-2024-100532 | VA-2024-100532 B-4471 BERUFSUNFAEHIGKEIT 2024-05-14
AKTIV DE89370400440532013000 1987-03-22 3850.00 Keine Vorerkrankungen, Nichtraucher
```

**Demo 1 (Ganznachricht)** – roher Broker-Inhalt, kein einziges Feld lesbar:
```
VA-2024-100532 | ...pWTRrAYr+vDF3RzrbXnbQHmcLSEHs97ie3tZzR60Ap4W/rB3mb8KvDlwi...
```

**Demo 2 (Feldverschlüsselung)** – Kontrast perfekt sichtbar:
```
VA-2024-100532 | VA-2024-100532  B-4471  BERUFSUNFAEHIGKEIT  2024-05-14
AKTIV  TeR7O20h5/2vptcbr6gSYB23I/SYWMy4Cvqtj/nzR42xlN2K6FtSivEd46gHv8ltRKE=...
```
Unkritische Felder im Klartext, IBAN/Geburtsdatum/Einkommen/Gesundheitsangaben chiffriert.

Der Consumer mit Vault-Zugriff bekommt in beiden Fällen alle Felder entschlüsselt zurück.

## Verifizierte Stolperfallen (wichtig für die Generalprobe)

1. **Tags müssen vorher im Stream Catalog existieren.** Ein Schema mit `confluent:tags` lässt sich sonst nicht registrieren:
   `42250 "The schema has embedded tags that do not exist"`.
   `scripts/register-schema.sh` legt `ALL`/`PII`/`PCI`/`HEALTH` deshalb idempotent per Catalog-API an (`POST /catalog/v1/types/tagdefs`).
2. **Zurückschalten von demo2 auf demo1 funktioniert nicht.** Die Registry dedupliziert identische Schema+Ruleset-Kombinationen: man bekommt die alte Version-ID zurück, `latest` bleibt aber auf demo2. Der Vortrag läuft nur vorwärts (demo1 → demo2); für die Generalprobe gibt es `./scripts/register-schema.sh reset` (Soft- **und** Hard-Delete des Subjects).
3. **Die Confluent CLI braucht einen aktiv gesetzten API-Key**, sonst schlägt `confluent kafka topic consume` fehl:
   `confluent api-key store <KEY> <SECRET> --resource <CLUSTER>` + `confluent api-key use <KEY> --resource <CLUSTER>`.
4. **Log-Rauschen**: Der Kafka-Client dumpt beim Start seine komplette Konfiguration. `kotlin-demo/src/main/resources/simplelogger.properties` setzt das auf `warn` – lässt aber `EncryptionExecutor` auf `info`, damit während der Demo die Zeile `Registered kek vertrag-demo-kek` sichtbar bleibt (beweist den Vault-Zugriff).
5. **Topic vor der Generalprobe leeren**, sonst mischen sich Nachrichten aus früheren Durchläufen mit unterschiedlichen Rulesets:
   `confluent kafka topic delete vertrag-abschluss --force && confluent kafka topic create vertrag-abschluss --partitions 1`
6. **Der gefährlichste Fall – Vault-Neustart bricht die Envelope Encryption.** Vault läuft im Dev-Mode und hält alles nur im RAM. Nach einem Neustart legt `setup-vault.sh` einen **neuen** Transit-Key an. Der in der Confluent Cloud gespeicherte DEK ist aber noch mit dem **alten** KEK verschlüsselt – der Producer stirbt dann mit `java.security.GeneralSecurityException: decryption failed` in `EncryptionExecutor.getOrCreateDek`. Der Schema-Reset allein hilft **nicht**, weil die DEK-Registry davon unberührt bleibt.
   Behebung: `./scripts/reset-keys.sh` (löscht DEKs + KEK, jeweils Soft- und Hard-Delete). `setup-vault.sh` erkennt einen neu angelegten Key inzwischen selbst und ruft das Cleanup **automatisch** auf – der Fehler sollte also nicht mehr auftreten.

## Skripte

**Für den Vortrag (das sind die einzigen Befehle, die man sich merken muss):**

| Befehl | Wirkung |
| --- | --- |
| `./scripts/plain.sh` | Ausgangszustand: Schema ohne Ruleset, Producer, roher Broker-Inhalt → alles Klartext |
| `./scripts/demo1.sh` | Kapitel 5: Ruleset `ALL`, Producer, roher Broker-Inhalt → komplett verschlüsselt |
| `./scripts/demo2.sh` | Kapitel 7: Ruleset `PII/PCI/HEALTH`, Producer, roher Broker-Inhalt → nur sensible Felder chiffriert |
| `./scripts/consumer.sh` | Consumer mit Vault-Zugriff → alles wieder lesbar |
| `./scripts/reset.sh` | Schema + DEKs + Topic zurücksetzen und `plain` registrieren (für die Generalprobe) |
| `./scripts/status.sh` | Preflight-Check: was ist gerade aktiv? |
| `./scripts/teardown.sh` | Cloud-Ressourcen löschen (**beendet die laufenden Kosten**) |

Alle Schritte sind dünne Wrapper um `scripts/demo.sh <schritt>`; die eigentliche Logik steht nur dort. Jeder Schritt hält vor dem Anzeigen des Broker-Inhalts kurz an (ENTER), damit man die Folie erklären kann, bevor der Aha-Moment kommt – mit `-y` läuft er ohne Unterbrechung durch. Am Ende nennt jeder Schritt den jeweils nächsten Befehl.

**Bausteine (werden von den obigen aufgerufen):**

- `scripts/setup-vault.sh` – Transit Engine aktivieren + Key `csfle-demo` anlegen (nach jedem Vault-Start nötig, da Dev-Mode in-memory). Erkennt, ob der Key **neu** entstanden ist, und räumt in dem Fall automatisch die verwaisten DEKs auf (siehe Stolperfalle 6).
- `scripts/reset-keys.sh` – löscht KEK `vertrag-demo-kek` und die zugehörigen DEKs aus der DEK-Registry. Nötig, wenn der KEK in Vault ausgetauscht wurde; wird von `setup-vault.sh` mit aufgerufen.
- `scripts/register-schema.sh plain|demo1|demo2|reset` – registriert das Schema mit dem jeweiligen Ruleset (inkl. Tag-Definitionen); das Umschalten zwischen den Live-Demos passiert ausschließlich hierüber. `plain` registriert **ohne** Ruleset und erzeugt damit den Klartext-Ausgangszustand für Demo 1.
- `scripts/consume-raw.sh` – zeigt den **rohen** Topic-Inhalt via `confluent kafka topic consume` (bewusst ohne `--value-format avro`, damit keine Entschlüsselung stattfindet). Das ist der Aha-Moment beider Demos. Optionales zweites Argument: Zeitlimit in Sekunden.
- `scripts/record-demos.sh demo1|demo2|alle` – nimmt beide Demos mit asciinema auf und rendert GIFs (`recordings/` + Kopie nach `public/` für Slidev).
- `scripts/teardown.sh` – löscht Environment + Vault-Container, beendet die laufenden Kosten
- `scripts/preflight.sh` – prüft vor dem Vortrag `.env`, Vault-Key, Schema Registry (inkl. aktivem Modus) und Kafka-Topic; nennt bei jedem Fehler den Befehl zur Behebung. Läuft über den Gradle-Task `preflight` **automatisch auch vor jedem `runProducer`/`runConsumer`** und bricht den Lauf ab, wenn etwas fehlt. Wichtigster Fall: nach einem Vault-Neustart ist der Transit-Key weg (Dev-Mode ist in-memory).

## Demo-Aufzeichnungen (Fallback)

Falls die Live-Verbindung im Vortrag streikt, liegen beide Demos als Terminal-Aufzeichnung bereit:

| Datei | Dauer | Inhalt |
| --- | --- | --- |
| `recordings/demo1.cast` / `public/demo1-v2.cast` | ~62 s | Klartext auf dem Broker → Ganznachricht verschlüsselt |
| `recordings/demo2.cast` / `public/demo2-v2.cast` | ~58 s | Feldverschlüsselung im Kontrast + Consumer entschlüsselt alles |

Auf beiden Demo-Folien steckt hinter einem `v-click` ein **echter asciinema-Player** (Komponente `components/AsciinemaPlayer.vue`, npm-Paket `asciinema-player`). Läuft die Live-Demo, klickt man einfach nicht weiter.

Vorteile gegenüber einem GIF: Der Text bleibt gestochen scharf (echte Schrift statt Pixel), die Wiedergabe lässt sich **pausieren und spulen** – wichtig, um beim Broker-Output stehenzubleiben – und pro Demo sind es nur ~8 KB statt ~1 MB.

Zu beachten:
- asciinema zeichnet in **v3** auf, der Player erwartet **v2** → `record-demos.sh` konvertiert automatisch nach `public/*-v2.cast` (`asciinema convert --output-format asciicast-v2 --overwrite`).
- Die Komponente setzt `preload: true`. Ohne das lädt der Player den Cast erst beim Klick auf Play und das Terminal hätte bis dahin die falsche Größe (80×24 statt 120×32).
- Der Import von `asciinema-player` erfolgt dynamisch in `onMounted`, weil das Paket auf `window` zugreift und der statische Build sonst bricht. `onBeforeUnmount` ruft `dispose()`, sonst läuft die Wiedergabe beim Folienwechsel weiter.
- Verifiziert: Slidev-Build **und** Dev-Server, beide Player rendern und spielen ab.

Neu aufnehmen mit `./scripts/record-demos.sh alle` (setzt Schema, Keys und Topic vorher selbst zurück). Die GIFs entstehen weiterhin als zusätzliches Format in `recordings/`.
- `scripts/preflight.sh` – prüft vor dem Vortrag `.env`, Vault-Key, Schema Registry (inkl. aktivem Modus) und Kafka-Topic; nennt bei jedem Fehler den Befehl zur Behebung. Läuft über den Gradle-Task `preflight` **automatisch auch vor jedem `runProducer`/`runConsumer`** und bricht den Lauf ab, wenn etwas fehlt. Wichtigster Fall: nach einem Vault-Neustart ist der Transit-Key weg (Dev-Mode ist in-memory).

## Demo-Runbook

Einmalig vor dem Vortrag:

```bash
docker compose up -d vault && ./scripts/setup-vault.sh
./scripts/status.sh            # Preflight: ist alles bereit?
./scripts/reset.sh             # sauberer Ausgangszustand
```

Während des Vortrags – ein Befehl pro Demo-Schritt, jeder nennt am Ende den nächsten:

```bash
./scripts/plain.sh      # Kapitel 4: alles im Klartext auf dem Broker
./scripts/demo1.sh      # Kapitel 5: ganze Nachricht verschlüsselt
./scripts/demo2.sh      # Kapitel 7: nur die sensiblen Felder
./scripts/consumer.sh   # Kontrast: Consumer mit Vault-Zugriff sieht alles
```

Jeder Schritt hält vor dem Broker-Inhalt kurz an (ENTER), damit man die Folie erklären kann. Mit `-y` läuft er ohne Unterbrechung durch.

Vor jedem weiteren Durchlauf (Schema **und** Topic, sonst mischen sich alte Nachrichten):

```bash
./scripts/reset.sh
```

Nach dem Vortrag – **beendet die laufenden Kosten**:

```bash
./scripts/teardown.sh
```


