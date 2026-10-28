#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift test --disable-sandbox --cache-path /private/tmp/times-shot-swift-cache \
    -Xswiftc -module-cache-path -Xswiftc /private/tmp/times-shot-module-cache
