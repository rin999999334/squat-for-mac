import AVFoundation
import Vision
import ImageIO

final class Camera: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "SquatForMac.camera")
    private var configured = false
    private var lastFrame = 0.0
    private var preferredSide: String?
    private var runID = UUID()
    private let runLock = NSLock()
    var useFace = true
    var onFace: ((Double?, Double?, CGRect?, Double, Double, UUID, RecognitionIssue?) -> Void)?
    var onSample: ((Double?, String?, UUID, Double) -> Void)?
    var onError: ((RecognitionIssue, UUID) -> Void)?
    private var observers: [NSObjectProtocol] = []

    override init() {
        super.init()
        for name in [AVCaptureSession.runtimeErrorNotification, AVCaptureSession.wasInterruptedNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: session, queue: nil) { [weak self] _ in
                guard let self else { return }
                self.runLock.lock(); let id = self.runID; self.runLock.unlock()
                DispatchQueue.main.async { self.onError?(.cameraInterrupted, id) }
            })
        }
    }
    deinit { observers.forEach(NotificationCenter.default.removeObserver) }

    func start(useFace: Bool = true, runID: UUID, completion: @escaping (RecognitionIssue?) -> Void) {
        queue.async {
            self.useFace = useFace
            self.runLock.lock(); self.runID = runID; self.runLock.unlock()
            do {
                if !self.configured {
                    guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .unspecified) ?? AVCaptureDevice.default(for: .video) else {
                        throw CameraError.unavailable
                    }
                    let input = try AVCaptureDeviceInput(device: device)
                    self.session.beginConfiguration()
                    defer { self.session.commitConfiguration() }
                    self.session.sessionPreset = self.session.canSetSessionPreset(.vga640x480) ? .vga640x480 : .medium
                    guard self.session.canAddInput(input) else { throw CameraError.unavailable }
                    self.session.addInput(input)
                    let output = AVCaptureVideoDataOutput()
                    output.alwaysDiscardsLateVideoFrames = true
                    output.setSampleBufferDelegate(self, queue: self.queue)
                    guard self.session.canAddOutput(output) else {
                        self.session.removeInput(input)
                        throw CameraError.unavailable
                    }
                    self.session.addOutput(output)
                    self.configured = true
                }
                self.lastFrame = 0
                self.preferredSide = nil
                self.session.startRunning()
                let error: RecognitionIssue? = self.session.isRunning ? nil : .cameraStartFailed
                DispatchQueue.main.async { completion(error) }
            } catch {
                DispatchQueue.main.async { completion(.cameraUnavailable) }
            }
        }
    }
    func stop(completion: (() -> Void)? = nil) {
        queue.async {
            self.runLock.lock(); self.runID = UUID(); self.runLock.unlock()
            self.session.stopRunning()
            if let completion { DispatchQueue.main.async(execute: completion) }
        }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastFrame >= 0.05, let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        lastFrame = now
        let id = runID
        let aspect = Double(CVPixelBufferGetWidth(buffer)) / Double(CVPixelBufferGetHeight(buffer))
        if useFace {
            let faceRequest = VNDetectFaceRectanglesRequest()
            do {
                try VNImageRequestHandler(cvPixelBuffer: buffer, orientation: .up).perform([faceRequest])
                let faces = faceRequest.results ?? []
                let face = faces.count == 1 ? faces.first : nil
                let box = face.flatMap { $0.confidence >= 0.5 ? $0.boundingBox : nil }
                let reason: RecognitionIssue = faces.count > 1 ? .multipleFaces : .noFace
                DispatchQueue.main.async { self.onFace?(box.map { Double($0.midY) }, box.map { Double($0.height) }, box, aspect, now, id, box == nil ? reason : nil) }
            } catch {
                DispatchQueue.main.async { self.onFace?(nil, nil, nil, aspect, now, id, .unreadableFace) }
            }
            return
        }
        let request = VNDetectHumanBodyPoseRequest()
        do {
            try VNImageRequestHandler(cvPixelBuffer: buffer, orientation: .up).perform([request])
            // Ambiguous multiple-person frames are rejected.
            guard let results = request.results, results.count == 1 else { publish(nil, nil); return }
            let points = try results[0].recognizedPoints(.all)
            let width = Double(CVPixelBufferGetWidth(buffer))
            let height = Double(CVPixelBufferGetHeight(buffer))
            let sides: [(String, VNHumanBodyPoseObservation.JointName, VNHumanBodyPoseObservation.JointName, VNHumanBodyPoseObservation.JointName)] = [
                ("左", .leftHip, .leftKnee, .leftAnkle), ("右", .rightHip, .rightKnee, .rightAnkle)
            ]
            var best: (Double, String, Float)?
            for (side, hip, knee, ankle) in sides {
                guard let h = points[hip], let k = points[knee], let a = points[ankle] else { continue }
                let confidence = min(h.confidence, k.confidence, a.confidence)
                guard confidence >= 0.5 else { continue }
                let ux = Double(h.x - k.x) * width, uy = Double(h.y - k.y) * height
                let vx = Double(a.x - k.x) * width, vy = Double(a.y - k.y) * height
                let length = hypot(ux, uy) * hypot(vx, vy)
                guard length > 1 else { continue }
                let angle = acos(max(-1, min(1, (ux * vx + uy * vy) / length))) * 180 / .pi
                // Keep one leg throughout a movement instead of switching on tiny confidence changes.
                if side == preferredSide { best = (angle, side, confidence); break }
                if best == nil || confidence > best!.2 { best = (angle, side, confidence) }
            }
            preferredSide = best?.1
            publish(best?.0, best?.1)
        } catch { publish(nil, nil) }
    }
    private func publish(_ angle: Double?, _ side: String?) {
        let id = runID; let time = ProcessInfo.processInfo.systemUptime
        DispatchQueue.main.async { self.onSample?(angle, side, id, time) }
    }
    enum CameraError: Error { case unavailable }
}
