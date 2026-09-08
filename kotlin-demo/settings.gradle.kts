rootProject.name = "kafka-csfle-demo"

dependencyResolutionManagement {
    repositories {
        mavenCentral()
        // Confluent-Artefakte (kafka-avro-serializer, client-encryption-*) liegen NICHT
        // auf Maven Central, sondern ausschliesslich in diesem Repository.
        maven("https://packages.confluent.io/maven/")
    }
}
