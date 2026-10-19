import Foundation

/// Image-space goals for downward face movement, not a measurement of squat form.
struct FaceDepthLines {
    static let returnOffsetPoints = 40.0
    static let minimumOffsetPoints = 120.0
    // End to Challenge is half of the Start to End distance.
    static let challengeOffsetPoints = minimumOffsetPoints + (minimumOffsetPoints - returnOffsetPoints) / 2
    let baseline: Double
    let minimumDistance: Double
    private let challengeDistance: Double
    private let returnDistance: Double
    var minimumY: Double { baseline - minimumDistance }
    var challengeY: Double { baseline - challengeDistance }
    var returnY: Double { baseline - returnDistance }

    init(baseline: Double, imageHeight: Double = 720) {
        self.baseline = baseline
        let height = imageHeight.isFinite && imageHeight > 0 ? imageHeight : 720
        minimumDistance = Self.minimumOffsetPoints / height
        challengeDistance = Self.challengeOffsetPoints / height
        returnDistance = Self.returnOffsetPoints / height
    }
}
