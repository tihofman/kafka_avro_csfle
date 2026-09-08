#!/usr/bin/env bash
# Kurzform fuer: ./scripts/demo.sh reset   (siehe demo.sh fuer Details)
exec "$(dirname "${BASH_SOURCE[0]}")/demo.sh" reset "$@"
