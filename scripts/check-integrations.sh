#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/module-cache
xcrun swiftc -swift-version 5 -parse-as-library -module-cache-path .build/module-cache \
 Sources/ThinkAndMove/AIActivity.swift Sources/ThinkAndMove/UsageReminderInterval.swift \
 Sources/ThinkAndMove/AppSettings.swift Sources/ThinkAndMove/RefreshExternalLinks.swift \
 Sources/ThinkAndMove/RefreshPluginDiscovery.swift Tests/RefreshIntegrationChecks.swift \
 -o .build/RefreshIntegrationChecks
.build/RefreshIntegrationChecks
