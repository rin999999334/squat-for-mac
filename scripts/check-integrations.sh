#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/module-cache
xcrun swiftc -swift-version 5 -parse-as-library -module-cache-path .build/module-cache \
 Sources/SquatForMac/AIActivity.swift Sources/SquatForMac/UsageReminderInterval.swift \
 Sources/SquatForMac/AppSettings.swift Sources/SquatForMac/RefreshExternalLinks.swift \
 Sources/SquatForMac/RefreshPluginDiscovery.swift Tests/RefreshIntegrationChecks.swift \
 -o .build/RefreshIntegrationChecks
.build/RefreshIntegrationChecks
