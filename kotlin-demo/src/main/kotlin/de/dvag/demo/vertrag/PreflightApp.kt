package de.dvag.demo.vertrag

import com.fasterxml.jackson.databind.JsonNode
import com.fasterxml.jackson.databind.ObjectMapper
import org.apache.kafka.clients.admin.Admin
import java.net.URI
import java.net.http.HttpClient
import java.net.http.HttpRequest
import java.net.http.HttpResponse
import java.time.Duration
import java.util.Base64
import java.util.Properties
import java.util.concurrent.TimeUnit

/**
 * Preflight-Check vor der Live-Demo.
 *
 * Prueft alle Abhaengigkeiten, die zwischen Aufbau und Vortrag kaputtgehen
 * koennen - allen voran der Vault-Container, der im Dev-Mode in-memory laeuft
 * und bei jedem Neustart seine Keys verliert.
 *
 * Laeuft automatisch vor 'gradle runProducer' und 'gradle runConsumer'.
 * Bricht mit Exit-Code 1 ab, wenn etwas nicht stimmt - inklusive Hinweis,
 * wie es zu beheben ist.
 */

private const val VAULT_KEY = "csfle-demo"

private val http: HttpClient = HttpClient.newBuilder()
    .connectTimeout(Duration.ofSeconds(5))
    .build()

private val mapper = ObjectMapper()

private val fehler = mutableListOf<String>()

fun main() {
    println("Preflight-Check für die Live-Demo")
    println("=".repeat(60))

    val configOk = pruefeKonfiguration()
    if (configOk) {
        pruefeVault()
        pruefeSchemaRegistry()
        pruefeKafka()
    }

    println("=".repeat(60))
    if (fehler.isEmpty()) {
        println("✓ Alles bereit. Viel Erfolg!")
    } else {
        println("✗ ${fehler.size} Problem(e) gefunden:\n")
        fehler.forEach { println("  - $it") }
        println()
        kotlin.system.exitProcess(1)
    }
}

private fun ok(text: String) = println("  ✓ $text")

private fun fehlt(text: String, hinweis: String) {
    println("  ✗ $text")
    fehler += "$text\n      → $hinweis"
}

private fun pruefeKonfiguration(): Boolean {
    println("\n[1/4] Konfiguration")
    val benoetigt = listOf(
        "CC_BOOTSTRAP_SERVERS", "CC_API_KEY", "CC_API_SECRET",
        "CC_SCHEMA_REGISTRY_URL", "CC_SCHEMA_REGISTRY_API_KEY",
        "CC_SCHEMA_REGISTRY_API_SECRET", "VAULT_ADDR", "VAULT_TOKEN"
    )
    val fehlende = benoetigt.filter { DemoConfig.get(it) == null }
    return if (fehlende.isEmpty()) {
        ok("Alle ${benoetigt.size} Konfigurationswerte vorhanden")
        true
    } else {
        fehlt(
            "Fehlende Werte in .env: ${fehlende.joinToString(", ")}",
            "cp .env.example .env und ausfüllen"
        )
        false
    }
}

private fun pruefeVault() {
    println("\n[2/4] Vault (KMS)")
    val addr = DemoConfig.require("VAULT_ADDR").trimEnd('/')

    val response = runCatching {
        http.send(
            HttpRequest.newBuilder(URI.create("$addr/v1/transit/keys/$VAULT_KEY"))
                .header("X-Vault-Token", DemoConfig.require("VAULT_TOKEN"))
                .timeout(Duration.ofSeconds(5))
                .GET().build(),
            HttpResponse.BodyHandlers.ofString()
        )
    }.getOrElse {
        fehlt(
            "Vault unter $addr nicht erreichbar (${it.javaClass.simpleName})",
            "docker compose up -d vault && ./scripts/setup-vault.sh"
        )
        return
    }

    when (response.statusCode()) {
        200 -> ok("Vault erreichbar, Transit-Key '$VAULT_KEY' vorhanden")
        404 -> fehlt(
            "Vault läuft, aber Transit-Key '$VAULT_KEY' fehlt " +
                "(typisch nach Container-Neustart – Dev-Mode ist in-memory)",
            "./scripts/setup-vault.sh"
        )
        403 -> fehlt("Vault-Token abgelehnt (HTTP 403)", "VAULT_TOKEN in .env prüfen")
        else -> fehlt("Vault antwortet mit HTTP ${response.statusCode()}", "Vault-Logs prüfen: docker compose logs vault")
    }
}

private fun pruefeSchemaRegistry() {
    println("\n[3/4] Schema Registry")
    val url = DemoConfig.require("CC_SCHEMA_REGISTRY_URL").trimEnd('/')
    val auth = Base64.getEncoder().encodeToString(
        ("${DemoConfig.require("CC_SCHEMA_REGISTRY_API_KEY")}:" +
            DemoConfig.require("CC_SCHEMA_REGISTRY_API_SECRET")).toByteArray()
    )

    val response = runCatching {
        http.send(
            HttpRequest.newBuilder(URI.create("$url/subjects/${DemoConfig.SUBJECT}/versions/latest"))
                .header("Authorization", "Basic $auth")
                .timeout(Duration.ofSeconds(10))
                .GET().build(),
            HttpResponse.BodyHandlers.ofString()
        )
    }.getOrElse {
        fehlt(
            "Schema Registry nicht erreichbar (${it.javaClass.simpleName})",
            "Internetverbindung und CC_SCHEMA_REGISTRY_URL prüfen"
        )
        return
    }

    when (response.statusCode()) {
        200 -> beschreibeAktivesRuleset(mapper.readTree(response.body()))
        401, 403 -> fehlt(
            "Schema-Registry-Zugangsdaten abgelehnt (HTTP ${response.statusCode()})",
            "CC_SCHEMA_REGISTRY_API_KEY/_SECRET in .env prüfen"
        )
        404 -> fehlt(
            "Subject '${DemoConfig.SUBJECT}' ist nicht registriert",
            "./scripts/register-schema.sh plain   (bzw. demo1 / demo2)"
        )
        else -> fehlt(
            "Schema Registry antwortet mit HTTP ${response.statusCode()}",
            response.body().take(200)
        )
    }
}

private fun beschreibeAktivesRuleset(node: JsonNode) {
    val version = node.path("version").asInt()
    val regeln = node.path("ruleSet").path("domainRules")

    if (regeln.isMissingNode || regeln.isEmpty) {
        ok("Subject registriert (Version $version) – KEIN Ruleset aktiv → Klartext ('plain')")
        return
    }

    val tags = regeln[0].path("tags").map { it.asText() }.toSet()
    val modus = when {
        tags == setOf("ALL") -> "demo1 – Ganznachricht verschlüsselt"
        tags.containsAll(setOf("PII", "PCI", "HEALTH")) -> "demo2 – nur sensible Felder verschlüsselt"
        else -> "unbekannt (Tags: ${tags.joinToString(", ")})"
    }
    ok("Subject registriert (Version $version) – aktiver Modus: $modus")
}

private fun pruefeKafka() {
    println("\n[4/4] Kafka-Cluster & Topic")
    val props = Properties().apply {
        put("bootstrap.servers", DemoConfig.require("CC_BOOTSTRAP_SERVERS"))
        put("security.protocol", "SASL_SSL")
        put("sasl.mechanism", "PLAIN")
        put(
            "sasl.jaas.config",
            "org.apache.kafka.common.security.plain.PlainLoginModule required " +
                "username=\"${DemoConfig.require("CC_API_KEY")}\" " +
                "password=\"${DemoConfig.require("CC_API_SECRET")}\";"
        )
        put("default.api.timeout.ms", "15000")
        put("request.timeout.ms", "15000")
    }

    runCatching {
        Admin.create(props).use { admin ->
            val topics = admin.listTopics().names().get(15, TimeUnit.SECONDS)
            if (DemoConfig.TOPIC in topics) {
                ok("Cluster erreichbar, Topic '${DemoConfig.TOPIC}' vorhanden")
            } else {
                fehlt(
                    "Topic '${DemoConfig.TOPIC}' existiert nicht",
                    "confluent kafka topic create ${DemoConfig.TOPIC} --partitions 1"
                )
            }
        }
    }.onFailure {
        fehlt(
            "Kafka-Cluster nicht erreichbar (${it.javaClass.simpleName}: ${it.message?.take(120)})",
            "Internetverbindung, CC_BOOTSTRAP_SERVERS und API-Keys prüfen"
        )
    }
}
