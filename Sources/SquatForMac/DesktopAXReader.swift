import ApplicationServices
import Foundation

struct DesktopAXReadRequest {
    let processID: Int32
    let provider: AIProvider
    let application: DesktopAIApplicationIdentity
}

enum DesktopAXReadFailure {
    case permission, noWindow, minimized, incomplete
}

enum DesktopAXReadResult {
    case observation(DesktopAIControlObservation)
    case unavailable(DesktopAXReadFailure)
}

/// AX calls run on a serial background queue. Only structural attributes and
/// short public control labels are processed. Window titles, body text, input
/// values and events are never read. Unknown labels are discarded, never logged.
final class DesktopAXReader {
    private let queue = DispatchQueue(label: "Squat.desktopAX", qos: .utility)
    private var previousWindow: AXUIElement?
    private var previousApplication: DesktopAIApplicationIdentity?
    private var previousPID: Int32?
    private var windowID = UUID()
    private let maximumNodes = 512
    private let maximumDepth = 24
    private let timeBudget = 0.22
    private let messagingTimeout: Float = 0.025

    func read(_ request: DesktopAXReadRequest, completion: @escaping (DesktopAXReadResult) -> Void) {
        queue.async {
            let result = self.readSynchronously(request)
            DispatchQueue.main.async { completion(result) }
        }
    }
    func reset() {
        queue.async { self.retireWindow() }
    }
    private func retireWindow() {
        previousWindow = nil; previousApplication = nil; previousPID = nil; windowID = UUID()
    }
    private func readSynchronously(_ request: DesktopAXReadRequest) -> DesktopAXReadResult {
        guard AXIsProcessTrusted(), request.application.isSupported(for: request.provider) else {
            retireWindow(); return .unavailable(.permission)
        }
        let started = ProcessInfo.processInfo.systemUptime
        let deadline = started + timeBudget
        let application = AXUIElementCreateApplication(request.processID)
        AXUIElementSetMessagingTimeout(application, messagingTimeout)
        func copy(_ element: AXUIElement, _ attribute: CFString) -> (AXError, CFTypeRef?) {
            guard ProcessInfo.processInfo.systemUptime < deadline else { return (.cannotComplete, nil) }
            var result: CFTypeRef?
            return (AXUIElementCopyAttributeValue(element, attribute, &result), result)
        }
        let (windowError, rawWindow) = copy(application, kAXFocusedWindowAttribute as CFString)
        guard windowError == .success, let rawWindow, CFGetTypeID(rawWindow) == AXUIElementGetTypeID() else {
            retireWindow(); return .unavailable(.noWindow)
        }
        let window = unsafeBitCast(rawWindow, to: AXUIElement.self)
        AXUIElementSetMessagingTimeout(window, messagingTimeout)
        let (minimizedError, minimizedValue) = copy(window, kAXMinimizedAttribute as CFString)
        guard minimizedError == .success, let minimized = minimizedValue as? Bool else {
            retireWindow(); return .unavailable(.incomplete)
        }
        guard !minimized else { retireWindow(); return .unavailable(.minimized) }
        if previousPID != request.processID || previousApplication != request.application || previousWindow.map({ !CFEqual($0, window) }) ?? true {
            previousWindow = window; previousApplication = request.application; previousPID = request.processID; windowID = UUID()
        }
        var stack: [(AXUIElement, Int)] = [(window, 0)]
        var visited: [AXUIElement] = []
        var controls: [DesktopAIStopControl] = []
        var ambiguous = false
        var modeEvidence = DesktopAIChatModeEvidence()
        var complete = true
        let leafRoles: Set<String> = ["AXStaticText", "AXTextField", "AXTextArea", "AXImage", "AXLink"]
        while let (element, depth) = stack.popLast() {
            guard ProcessInfo.processInfo.systemUptime < deadline, visited.count < maximumNodes else { complete = false; break }
            if visited.contains(where: { CFEqual($0, element) }) { continue }
            visited.append(element)
            AXUIElementSetMessagingTimeout(element, messagingTimeout)
            let (roleError, roleValue) = copy(element, kAXRoleAttribute as CFString)
            guard roleError == .success, let role = roleValue as? String else { complete = false; break }
            if ["AXButton", "AXRadioButton", "AXTab"].contains(role) {
                let (enabledError, enabledValue) = copy(element, kAXEnabledAttribute as CFString)
                guard enabledError == .success, let enabled = enabledValue as? Bool else { complete = false; break }
                // Public control labels may be exposed as Description or Title.
                // This Title fallback is restricted to Button/RadioButton/Tab;
                // window/text/input titles and every Value remain unread.
                let (labelError, labelValue) = copy(element, kAXDescriptionAttribute as CFString)
                guard labelError == .success || labelError == .attributeUnsupported || labelError == .noValue else { complete = false; break }
                var publicLabel = labelValue as? String
                if publicLabel?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
                    let (titleError, titleValue) = copy(element, kAXTitleAttribute as CFString)
                    guard titleError == .success || titleError == .attributeUnsupported || titleError == .noValue else { complete = false; break }
                    publicLabel = titleValue as? String
                }
                if let label = publicLabel, label.utf8.count <= 256 {
                    let normalized = DesktopAIStopControl.normalizedLabel(label)
                    if DesktopAIChatModeEvidence.recognizes(normalized) {
                        let (selectedError, selectedValue) = copy(element, kAXSelectedAttribute as CFString)
                        let selected = selectedError == .success ? selectedValue as? Bool : nil
                        let (identifierError, identifierValue) = copy(element, kAXIdentifierAttribute as CFString)
                        guard identifierError == .success || identifierError == .attributeUnsupported || identifierError == .noValue else { complete = false; break }
                        modeEvidence.observe(label: normalized, selected: selected, role: role, identifier: identifierValue as? String)
                    }
                    if DesktopAIStopControl.ambiguousLabels.contains(normalized) { ambiguous = true }
                    if role == "AXButton", DesktopAIStopControl.generationLabels.contains(normalized) {
                        guard enabled else { ambiguous = true; continue }
                        let (idError, idValue) = copy(element, kAXIdentifierAttribute as CFString)
                        guard idError == .success || idError == .attributeUnsupported || idError == .noValue else { complete = false; break }
                        let control = DesktopAIStopControl(role: role, identifier: DesktopAIStopControl.safeIdentifier(idValue as? String), label: label)
                        if control.isStrictGenerationControl { controls.append(control) } else { ambiguous = true }
                    }
                }
                continue
            }
            if leafRoles.contains(role) { continue }
            guard depth < maximumDepth else { complete = false; break }
            let (childrenError, childrenValue) = copy(element, kAXChildrenAttribute as CFString)
            if childrenError == .attributeUnsupported || childrenError == .noValue { continue }
            guard childrenError == .success else { complete = false; break }
            guard let children = childrenValue as? [AXUIElement] else {
                if childrenValue == nil { continue }
                complete = false; break
            }
            guard children.count <= maximumNodes, stack.count + children.count + visited.count <= maximumNodes else { complete = false; break }
            for child in children.reversed() { stack.append((child, depth + 1)) }
        }
        guard complete else { retireWindow(); return .unavailable(.incomplete) }
        return .observation(DesktopAIControlObservation(application: request.application, windowID: windowID,
                                                        controls: controls, hasAmbiguousControl: ambiguous,
                                                        complete: true, observedAt: ProcessInfo.processInfo.systemUptime,
                                                        ordinaryChatModeVerified: modeEvidence.verifiedOrdinaryChat,
                                                        hasConflictingMode: modeEvidence.hasConflictingOrUnknownMode))
    }
}
