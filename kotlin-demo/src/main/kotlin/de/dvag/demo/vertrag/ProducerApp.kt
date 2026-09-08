package de.dvag.demo.vertrag

import com.fasterxml.jackson.module.kotlin.jacksonObjectMapper
import com.fasterxml.jackson.module.kotlin.readValue
import io.confluent.kafka.serializers.KafkaAvroSerializer
import org.apache.avro.Schema
import org.apache.avro.generic.GenericData
import org.apache.avro.generic.GenericRecord
import org.apache.kafka.clients.producer.KafkaProducer
import org.apache.kafka.clients.producer.ProducerRecord
import java.io.File

/**
 * Producer fuer die Live-Demos.
 *
 * Kernaussage der Demo: In diesem Code steht KEIN Verschluesselungs-Aufruf.
 * Die Verschluesselung passiert automatisch durch das im Schema hinterlegte
 * CSFLE-Ruleset - welches Feld verschluesselt wird, entscheidet allein das
 * registrierte Ruleset (Demo 1: alle Felder, Demo 2: nur PII/PCI/HEALTH).
 */
fun main() {
    val schema = Schema.Parser().parse(
        File(DemoConfig.projectRoot, "schemas/vertrags-abschluss-event.avsc")
    )

    val events: List<Map<String, Any?>> = jacksonObjectMapper().readValue(
        File(DemoConfig.projectRoot, "examples/vertrag-events.json")
    )

    val props = DemoConfig.commonProperties().apply {
        put("key.serializer", "org.apache.kafka.common.serialization.StringSerializer")
        put("value.serializer", KafkaAvroSerializer::class.java.name)
    }

    println("Sende ${events.size} Events an Topic '${DemoConfig.TOPIC}' ...")

    KafkaProducer<String, GenericRecord>(props).use { producer ->
        events.forEach { event ->
            val record = event.toAvroRecord(schema)
            val vertragId = event["vertragId"] as String

            producer.send(ProducerRecord(DemoConfig.TOPIC, vertragId, record)) { metadata, error ->
                if (error != null) {
                    System.err.println("  ✗ $vertragId fehlgeschlagen: ${error.message}")
                } else {
                    println("  ✓ $vertragId -> partition ${metadata.partition()}, offset ${metadata.offset()}")
                }
            }
        }
        producer.flush()
    }

    println("Fertig. Rohen Topic-Inhalt jetzt mit scripts/consume-raw.sh ansehen.")
}

/** Wandelt eine JSON-Map in einen Avro-GenericRecord gemaess Schema um. */
private fun Map<String, Any?>.toAvroRecord(schema: Schema): GenericRecord =
    GenericData.Record(schema).also { record ->
        schema.fields.forEach { field ->
            record.put(field.name(), this[field.name()])
        }
    }
