#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
TASK_TEST_DIR=$(mktemp -d "${TMPDIR:-/tmp}/jini-tests.XXXXXX")
trap 'rm -rf "$TASK_TEST_DIR"' EXIT
swiftc -parse-as-library -module-cache-path "$TASK_TEST_DIR/cache" Sources/Core.swift Tests/Tests.swift -o "$TASK_TEST_DIR/core-tests"
"$TASK_TEST_DIR/core-tests"
swiftc -parse-as-library -module-cache-path "$TASK_TEST_DIR/cache" Sources/Core.swift Sources/Engine.swift Tests/EngineTests.swift -o "$TASK_TEST_DIR/engine-tests"
"$TASK_TEST_DIR/engine-tests"
