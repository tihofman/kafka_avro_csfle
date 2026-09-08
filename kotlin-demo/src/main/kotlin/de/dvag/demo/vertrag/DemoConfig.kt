package de.dvag.demo.vertrag

import java.io.File
import java.util.Properties

/**
 * Zentrale Konfiguration fuer Producer und Consumer.
 *
 * Alle Zugangsdaten kommen aus Umgebungsvariablen bzw. aus der .env-Datei im
 * Projekt-Root (siehe .env.example). Es stehen bewusst keine Secrets im Code.
 */
object DemoConfig {

    const val TOPIC = "vertrag-abschluss"
    const val SUBJECT = "$TOPIC-value"

    private val dotenv: Map<String, String> by lazy { loadDotenv() }

    /** Projekt-Root (eine Ebene ueber kotlin-demo/). */
    val projectRoot: File by lazy {
        generateSequence(File(".").absoluteFile) { it.parentFile }
            .firstOrNull { File(it, "schemas/vertrags-abschluss-event.avsc").isFile }
            ?: error("Projekt-Root nicht gefunden (erwartet schemas/vertrags-abschluss-event.avsc)")
    }

    private fun loadDotenv(): Map<String, String> {
        val candidates = generateSequence(File(".").absoluteFile) { it.parentFile }
            .map { File(it, ".env") }
            .filter { it.isFile }
        val envFile = candidates.firstOrNull() ?: return emptyMap()
        return envFile.readLines()
            .map { it.trim() }
            .filter { it.isNotEmpty() && !it.startsWith("#") && it.contains("=") }
            .associate { line ->
                val key = line.substringBefore("=").trim()
                val value = line.substringAfter("=").trim().trim('"', '\'')
                key to value
            }
    }

    /** Env-Variable hat Vorrang vor .env-Datei. */
    fun get(key: String): String? = System.getenv(key)?.takeIf { it.isNotBlank() }
        ?: dotenv[key]?.takeIf { it.isNotBlank() }

    fun require(key: String): String = get(key)
        ?: error("Konfigurationswert '$key' fehlt. Bitte .env anlegen (Vorlage: .env.example).")

    /**
     * Gemeinsame Properties fuer Producer und Consumer:
     * Confluent-Cloud-Verbindung, Schema Registry und CSFLE/Vault.
     */
    fun commonProperties(): Properties = Properties().apply {
        // --- Confluent Cloud: Kafka-Cluster ---
        put("bootstrap.servers", require("CC_BOOTSTRAP_SERVERS"))
        put("security.protocol", "SASL_SSL")
        put("sasl.mechanism", "PLAIN")
        put(
            "sasl.jaas.config",
            "org.apache.kafka.common.security.plain.PlainLoginModule required " +
                "username=\"${require("CC_API_KEY")}\" " +
                "password=\"${require("CC_API_SECRET")}\";"
        )

        // --- Confluent Cloud: Schema Registry ---
        put("schema.registry.url", require("CC_SCHEMA_REGISTRY_URL"))
        put("basic.auth.credentials.source", "USER_INFO")
        put(
            "basic.auth.user.info",
            "${require("CC_SCHEMA_REGISTRY_API_KEY")}:${require("CC_SCHEMA_REGISTRY_API_SECRET")}"
        )

        // --- CSFLE ---
        // Das Schema inkl. Ruleset wird ausserhalb der Anwendung registriert
        // (scripts/register-schema.sh). Der Client darf es NICHT selbst registrieren,
        // sonst wuerde das serverseitig gepflegte Ruleset ueberschrieben werden.
        put("auto.register.schemas", "false")
        put("use.latest.version", "true")
        put("latest.compatibility.strict", "false")

        // Zugangsdaten fuer den Vault-KMS-Driver. Der Parametername 'token.id'
        // stammt aus HcVaultKmsDriver; das Praefix 'rule.executors._default_.param.'
        // gilt fuer alle Rule-Executors.
        put("rule.executors._default_.param.token.id", require("VAULT_TOKEN"))
    }
}
