#!/bin/bash
# アプリ内と同じ黒い b→p マークをアイコンにする。
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/icon-tools
SDK="${B2P_DIRECT_SDK:-$(xcrun --sdk macosx --show-sdk-path)}"
swiftc -sdk "$SDK" -module-cache-path build/icon-tools/module-cache -parse-as-library \
    Sources/B2P/BrandMark.swift scripts/make-icon.swift -o build/icon-tools/make-icon
build/icon-tools/make-icon
