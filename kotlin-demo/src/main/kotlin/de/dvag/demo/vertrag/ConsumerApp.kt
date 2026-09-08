package de.dvag.demo.vertrag

import io.confluent.kafka.serializers.KafkaAvroDeserializer
import org.apache.avro.generic.GenericRecord
import org.apache.kafka.clients.consumer.KafkaConsumer
import java.time.Duration
import java.util.UUID

/**
 * Consumer fuer die Live-Demos.
 *
 * Zeigt den Kontrast zum rohen Broker-Inhalt: Ein Client mit gueltigem
 * Vault-Zugriff bekommt die Felder automatisch entschluesselt zurueck -
 * ebenfalls ohne eine einzige Zeile Krypto-Code in der Anwendung.
 *
 * Ohne Vault-Zugriff (falsches/fehlendes Token) schlaegt die Entschluesselung
 * fehl - genau das ist die Schutzwirkung, die wir zeigen wollen.
 */
fun main() {
    val props = DemoConfig.commonProperties().apply {
        put("key.deserializer", "org.apache.kafka.common.serialization.StringDeserializer")
        put("value.deserializer", KafkaAvroDeserializer::class.java.name)
        put("specific.avro.reader", "false")
        put("group.id", "csfle-demo-consumer-" + UUID.randomUUID())
        put("auto.offset.reset", "earliest")
    }

    println("Lese Topic '${DemoConfig.TOPIC}' (Abbruch mit Strg+C) ...\n")

    KafkaConsumer<String, GenericRecord>(props).use { consumer ->
        consumer.subscribe(listOf(DemoConfig.TOPIC))

        var leereDurchlaeufe = 0
        while (leereDurchlaeufe < 5) {
            val records = consumer.poll(Duration.ofSeconds(2))
            if (records.isEmpty) {
                leereDurchlaeufe++
                continue
            }
            leereDurchlaeufe = 0

            records.forEach { record ->
                val value = record.value()
                println("── ${record.key()} (offset ${record.offset()}) ──")
                value.schema.fields.forEach { field ->
                    println("   ${field.name().padEnd(20)} = ${value.get(field.name())}")
                }
                println()
            }
        }
    }

    println("Keine weiteren Nachrichten.")
}
