# Kafka ohne Klartext: Client-Side Field-Level Encryption with Confluent CSFLE

A practical demonstration of **Confluent Client-Side Field-Level Encryption (CSFLE)** using Apache Kafka, Avro schemas, and HashiCorp Vault. This repository contains the code and infrastructure for a technical talk (~30 min) on securing sensitive data in Kafka event streams.

## 🎯 Overview

This project demonstrates how to encrypt sensitive fields at the **producer level** using Confluent's CSFLE, ensuring:
- **Selective field encryption**: Only sensitive data is encrypted, operational fields remain queryable
- **Schema-driven encryption**: Encryption rules are defined in the Schema Registry, not hardcoded in application logic
- **Client-side control**: Producers and consumers manage encryption/decryption independently
- **Multi-consumer compatibility**: Different consumer groups get different visibility based on their credentials

### The Core Message

**No encryption calls in application code.** Producers use standard `KafkaAvroSerializer` and consumers use `KafkaAvroDeserializer`. Whether and which fields are encrypted is determined **entirely by the Ruleset in the Schema Registry**. You can switch between demo scenarios without changing or rebuilding your application.

---

## 📋 Use Case: Financial Services Event Stream

The example scenario: A financial advisor closes an insurance/savings contract for a customer, publishing a `VertragAbschluss` (Contract Conclusion) event.

### Event Structure

**Non-sensitive fields** (used for reporting, commission tracking, monitoring):
- `vertragId`, `beraterId`, `produktTyp`, `abschlussDatum`, `status`

**Sensitive fields** (PII / special category data):
- `kundenIban` (account number)
- `geburtsdatum` (date of birth)
- `einkommen` (income)
- `gesundheitsangaben` (health information for disability insurance)

### Multiple Consumer Perspectives

Different consumers need different data visibility:
- **Commission accounting**: Needs `kundenIban`
- **Sales analytics**: Needs only `produktTyp`, `abschlussDatum` — no personal data
- **Compliance monitoring**: Needs only `status` — no financial or health details

This multi-consumer, multi-permission scenario is the classic use case for **field-level encryption**.

---

## 🚀 Quick Start

### Prerequisites

- **JDK 21** (for Kotlin demo)
- **Confluent Cloud Account** with **Stream Governance Advanced** package (required for CSFLE)
- **Docker & Docker Compose** (for HashiCorp Vault)
- **Node.js** (for presentation slides)

### Setup

1. **Clone and navigate to the repository:**
   ```bash
   git clone https://github.com/tihofman/kafka_avro_csfle.git
   cd kafka_avro_csfle
   ```

2. **Configure Confluent Cloud credentials:**
   ```bash
   cp .env.example .env
   # Edit .env with your Confluent Cloud API keys and Schema Registry endpoints
   ```
   
   Required credentials:
   - `CC_BOOTSTRAP_SERVERS`: Kafka broker endpoints
   - `CC_API_KEY` & `CC_API_SECRET`: Kafka cluster credentials
   - `CC_SCHEMA_REGISTRY_URL`: Schema Registry endpoint
   - `CC_SCHEMA_REGISTRY_API_KEY` & `CC_SCHEMA_REGISTRY_API_SECRET`: Schema Registry credentials

3. **Start HashiCorp Vault locally (KMS backend):**
   ```bash
   docker compose up -d vault
   ./scripts/setup-vault.sh
   ```
   
   This initializes Vault's Transit Engine with encryption keys.

---

## 🎬 Running the Demos

### Preflight Check

Verify that your environment is correctly configured:
```bash
./scripts/preflight.sh
```

### Demo Progression

#### Phase 1: Baseline (No Encryption)
See how Kafka publishes data without encryption:
```bash
./scripts/register-schema.sh plain
cd kotlin-demo && gradle runProducer && cd ..
./scripts/consume-raw.sh
```
**Result:** All fields visible in plaintext on the Kafka broker.

#### Phase 2: Full Message Encryption (Demo 1)
Encrypt the entire event payload:
```bash
./scripts/register-schema.sh demo1
cd kotlin-demo && gradle runProducer && cd ..
./scripts/consume-raw.sh
```
**Result:** Entire message is ciphertext on the broker.

#### Phase 3: Field-Level Encryption (Demo 2)
Encrypt only sensitive fields; keep operational fields in plaintext for indexing/filtering:
```bash
./scripts/register-schema.sh demo2
cd kotlin-demo && gradle runProducer && cd ..
./scripts/consume-raw.sh
```
**Result:** Operational fields (`vertragId`, `produktTyp`, etc.) remain plaintext; sensitive fields (`kundenIban`, `geburtsdatum`, etc.) are encrypted.

#### View Plaintext (With Vault Access)
Consumer with valid Vault credentials sees the decrypted data:
```bash
cd kotlin-demo && gradle runConsumer
```

---

## 📁 Project Structure

```
kafka_avro_csfle/
├── slides.md                 # Presentation slides (Slidev format)
├── spec.md                   # Detailed talk specification & narrative
├── docker-compose.yml        # HashiCorp Vault setup
├── .env.example              # Confluent Cloud credentials template
├── scripts/                  # Demo automation & setup
│   ├── setup-vault.sh        # Initialize Vault Transit Engine
│   ├── preflight.sh          # Environment validation
│   ├── register-schema.sh    # Apply schema with encryption rules
│   └── consume-raw.sh        # Read ciphertext directly from broker
├── kotlin-demo/              # Kafka producer/consumer application
│   ├── src/
│   │   ├── main/kotlin/      # Producer & Consumer
│   │   └── test/kotlin/      # Unit tests
│   ├── build.gradle.kts      # Gradle config with Confluent deps
│   └── README.md             # Kotlin demo documentation
├── schemas/                  # Avro schemas & Rulesets
│   ├── vertrag-events.avsc   # Base Avro schema
│   └── ruleset-*.json        # Encryption rulesets for each demo phase
└── examples/                 # Sample data files
    └── vertrag-events.json   # Example contract events
```

---

## 🔐 How CSFLE Works

### Key Components

1. **Avro Schema**: Defines the event structure and field types
2. **Ruleset**: JSON configuration specifying which fields to encrypt and how
3. **KMS (HashiCorp Vault)**: Stores and manages encryption keys
4. **Confluent Schema Registry**: Stores schemas + rulesets; orchestrates encryption

### Encryption Flow

1. **Producer creates an event** (Java/Kotlin object)
2. **`KafkaAvroSerializer` is invoked** (no changes to application code)
3. **Schema Registry fetches the schema + ruleset** for this subject
4. **Confluent serialization layer**:
   - Serializes to Avro
   - Identifies fields marked for encryption in the ruleset
   - Calls Vault to encrypt those fields
   - Returns ciphertext
5. **Producer publishes** the encrypted event to Kafka

### Decryption Flow (Consumer)

1. **Consumer receives message** from Kafka (ciphertext)
2. **`KafkaAvroDeserializer` is invoked**
3. **Schema Registry fetches the schema + ruleset**
4. **Confluent deserialization layer**:
   - Identifies encrypted fields
   - Calls Vault to decrypt (requires valid Vault token)
   - Returns plaintext object
5. **Application logic receives** the fully decrypted event

---

## 🛠️ Configuration Files

### `.env` (Confluent Cloud Credentials)

```bash
# Kafka Broker
CC_BOOTSTRAP_SERVERS=pkc-abc123.us-east-1.provider.confluent.cloud:9092
CC_API_KEY=YOUR_KAFKA_API_KEY
CC_API_SECRET=YOUR_KAFKA_API_SECRET

# Schema Registry
CC_SCHEMA_REGISTRY_URL=https://psrc-abc123.us-east-1.provider.confluent.cloud
CC_SCHEMA_REGISTRY_API_KEY=YOUR_SR_API_KEY
CC_SCHEMA_REGISTRY_API_SECRET=YOUR_SR_API_SECRET

# HashiCorp Vault (local)
VAULT_ADDR=http://127.0.0.1:8200
VAULT_TOKEN=root-token
```

### Rulesets (`schemas/ruleset-*.json`)

Example ruleset for Demo 2 (field-level encryption):

```json
{
  "version": 1,
  "ruleSet": [
    {
      "name": "SensitiveFields",
      "doc": "Encrypt PII and financial data",
      "type": "ENCRYPT",
      "mode": "ENCRYPT_ONLY",
      "onFailure": "ERROR",
      "tags": ["PII"],
      "conditions": [
        {
          "type": "SCHEMA_REGISTRY_REFERENCE",
          "metadata": {
            "encrypt": "PII"
          }
        }
      ],
      "actions": [
        {
          "type": "ENCRYPT",
          "params": {
            "kms.key.id": "http://127.0.0.1:8200/transit/keys/vortrag"
          }
        }
      ]
    }
  ]
}
```

---

## 🧪 Testing & Validation

### Preflight Checks
```bash
./scripts/preflight.sh
```
Validates:
- Confluent Cloud connectivity
- Schema Registry access
- Vault key availability
- Kafka topic existence

### Raw Message Inspection
```bash
./scripts/consume-raw.sh
```
Consumes messages **without deserialization**, showing encrypted data directly.

### Decrypted Consumer
```bash
cd kotlin-demo && gradle runConsumer
```
Runs a consumer with Vault credentials, demonstrating full message decryption.

---

## 📚 Presentation Materials

### Slides
```bash
npm run dev      # Live presentation with hot-reload
npm run build    # Build static presentation
npm run export   # Export as PDF
```

Slides cover:
1. Kafka & schema evolution primer
2. Problem: Sensitive data in event streams
3. Solution: Avro schemas & Schema Registry
4. Challenge: At-rest plaintext encryption
5. Demo 1: Full message encryption
6. Demo 2: Field-level encryption with selective access
7. Security & operational considerations

### Detailed Specification
See `spec.md` for the complete narrative, chapter-by-chapter breakdown, and design rationale.

---

## 🔑 Key Concepts

### Why Confluent Cloud + CSFLE?

- **Local Confluent Platform** requires an Enterprise license with the CSFLE add-on (not available self-service)
- **Confluent Cloud** with Stream Governance Advanced offers CSFLE out-of-the-box, charged against the **$400 free trial credit**
- **Client-side encryption** means Vault (the KMS) runs locally; Kafka brokers are never involved in cryptography

### Why HashiCorp Vault?

- **Portable KMS**: Works locally for demos, scales to production
- **Transit Engine**: Encryption as a service without key management burden
- **Audit trails**: Full logging of key operations for compliance
- **Dev mode**: Easy setup for testing (no persistence, suitable for ephemeral demos)

### Why Field-Level?

- **Operational flexibility**: Analytics and compliance teams can still query/filter on plaintext operational fields
- **Least privilege**: Consumers get only the encrypted data they need; secrets stay encrypted
- **Performance**: Plaintext fields can be indexed, compressed, or filtered at the broker level
- **Compliance**: Demonstrates GDPR/privacy-by-design principles (encrypt PII, leave audit trails readable)

---

## 🚧 Infrastructure Requirements (Confluent Cloud)

1. **Stream Governance Advanced package** (~$0.10 – $0.20/hour in free tier)
   - Enables Schema Registry with CSFLE support
   - Needed for rulesets and encryption orchestration

2. **Standard Kafka cluster** (included in $400 free trial)
   - Baseline throughput & storage

3. **Network access**:
   - Kafka brokers (via internet/VPC Peering)
   - Schema Registry API
   - HashiCorp Vault (local, reachable from your machine)

---

## 📖 Further Reading

- [Confluent CSFLE Documentation](https://docs.confluent.io/cloud/current/client-side-field-level-encryption/overview.html)
- [Avro Specification](https://avro.apache.org/docs/current/)
- [HashiCorp Vault Transit Secrets Engine](https://www.vaultproject.io/docs/secrets/transit)
- [Kafka Security Best Practices](https://kafka.apache.org/documentation/#security)

---

## 🤝 Contributing

This repository is primarily used for the "Kafka ohne Klartext" technical talk. Contributions, feedback, and questions are welcome!

- Report issues or suggest improvements via GitHub Issues
- Fork and submit pull requests for enhancements
- Questions about CSFLE, Kafka, or the demo setup? Open a discussion

---

## 📄 License

This project is provided as-is for educational and demonstration purposes.

---

## 👤 Author

Created for the **tech.evening** event series (compeople).

For questions or feedback, reach out via [GitHub Issues](https://github.com/tihofman/kafka_avro_csfle/issues).

---

**Last Updated:** September 2026
