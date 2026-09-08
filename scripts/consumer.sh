#!/usr/bin/env bash
# Kurzform fuer: ./scripts/demo.sh consumer   (siehe demo.sh fuer Details)
exec "$(dirname "${BASH_SOURCE[0]}")/demo.sh" consumer "$@"
