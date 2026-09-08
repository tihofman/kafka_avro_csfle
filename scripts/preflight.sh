#!/usr/bin/env bash
#
# Preflight-Check vor der Live-Demo - prueft .env, Vault-Key, Schema Registry
# und Kafka-Topic und sagt bei Problemen, wie sie zu beheben sind.
#
# Laeuft automatisch auch vor 'gradle runProducer' / 'gradle runConsumer';
# dieses Skript ist die bequeme Variante fuer den Check vor dem Vortrag.
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT/kotlin-demo"

exec gradle preflight --console=plain -q
