plugins {
    kotlin("jvm") version "2.0.21"
    application
}

group = "de.dvag.demo"
version = "1.0.0"

kotlin {
    jvmToolchain(21)
}

val confluentVersion = "8.3.1"

dependencies {
    implementation("org.apache.kafka:kafka-clients:3.9.0")
    implementation("org.apache.avro:avro:1.11.4")

    // Avro (De-)Serializer inkl. Schema-Registry-Client
    implementation("io.confluent:kafka-avro-serializer:$confluentVersion")

    // CSFLE: zieht transitiv client-encryption (EncryptionExecutor/FieldEncryptionExecutor),
    // client-encryption-tink, Google Tink und den Vault-Java-Driver mit.
    // Die Executors/KMS-Driver registrieren sich per ServiceLoader selbst -
    // es ist KEINE manuelle Registrierung im Code noetig.
    implementation("io.confluent:kafka-schema-registry-client-encryption-hcvault:$confluentVersion")

    implementation("com.fasterxml.jackson.module:jackson-module-kotlin:2.17.2")
    runtimeOnly("org.slf4j:slf4j-simple:2.0.16")
}

application {
    mainClass.set("de.dvag.demo.vertrag.ProducerAppKt")
}

tasks.register<JavaExec>("preflight") {
    group = "demo"
    description = "Prüft vor der Demo: .env, Vault-Key, Schema Registry, Kafka-Topic."
    mainClass.set("de.dvag.demo.vertrag.PreflightAppKt")
    classpath = sourceSets["main"].runtimeClasspath
    standardOutput = System.out
    errorOutput = System.err
    // Immer ausführen, auch wenn sich nichts geändert hat - der geprüfte
    // Zustand liegt ausserhalb des Build-Verzeichnisses.
    outputs.upToDateWhen { false }
}

tasks.register<JavaExec>("runProducer") {
    group = "demo"
    description = "Produziert die Beispiel-VertragsAbschlussEvents nach Confluent Cloud."
    dependsOn("preflight")
    mainClass.set("de.dvag.demo.vertrag.ProducerAppKt")
    classpath = sourceSets["main"].runtimeClasspath
    // Damit die Konsolenausgabe waehrend der Live-Demo sofort sichtbar ist
    standardOutput = System.out
    errorOutput = System.err
}

tasks.register<JavaExec>("runConsumer") {
    group = "demo"
    description = "Konsumiert die Events und gibt sie (entschluesselt) aus."
    dependsOn("preflight")
    mainClass.set("de.dvag.demo.vertrag.ConsumerAppKt")
    classpath = sourceSets["main"].runtimeClasspath
    standardOutput = System.out
    errorOutput = System.err
}
