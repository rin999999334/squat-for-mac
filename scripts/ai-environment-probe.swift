#!/usr/bin/env swift
import AppKit
import ApplicationServices
import Foundation

// Inspect only fixed application-bundle metadata and this probe's AX trust.
// No windows, accessibility trees, AXValue, chat content, screenshots, or network.
let roots = [URL(fileURLWithPath: "/Applications", isDirectory: true),
             FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications", isDirectory: true)]
var applications: [[String: String]] = []
var missingPaths: [String] = []
for root in roots {
    for name in ["ChatGPT.app", "Claude.app"] {
        let path = root.appendingPathComponent(name, isDirectory: true)
        guard let bundle = Bundle(url: path), let identifier = bundle.bundleIdentifier else {
            missingPaths.append(path.path)
            continue
        }
        applications.append(["path": path.path, "bundle_id": identifier,
                             "version": bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown",
                             "build": bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "unknown"])
    }
}
let result: [String: Any] = [
    "checked_at": ISO8601DateFormatter().string(from: Date()),
    "os": ProcessInfo.processInfo.operatingSystemVersionString,
    "probe_accessibility_trusted": AXIsProcessTrusted(),
    "permission_requested": false,
    "applications": applications,
    "not_found_at_fixed_paths": missingPaths,
    "generation_detection": "unverified",
    "content_read": false
]
let encoded = try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
print(String(decoding: encoded, as: UTF8.self))
