import Foundation
import CoreGraphics

/// Layout constants measured from BuhoLaunchpad 2.0.2 on a 1728 x 1117 point
/// display. Everything is expressed against that reference so the Classic
/// presentation can scale to other screens without scattering magic numbers
/// through the view tree.
enum ClassicMetrics {
    static let referenceWidth: CGFloat = 1728
    static let referenceHeight: CGFloat = 1117

    // Header
    static let searchWidth: CGFloat = 252
    static let searchHeight: CGFloat = 32
    static let searchTop: CGFloat = 64
    static let searchCornerRadius: CGFloat = 16

    // Grid
    static let iconSize: CGFloat = 128
    static let columnSpacing: CGFloat = 20
    static let rowSpacing: CGFloat = 14
    static let horizontalPaddingFraction: CGFloat = 0.11
    static let topPaddingFraction: CGFloat = 0.13
    static let bottomPaddingFraction: CGFloat = 0.06

    // App labels. Dock.app's ECSBEnvironment default is 13pt, but Classic uses
    // a larger override because 13pt reads too small on the reference display.
    static let labelFontSize: CGFloat = 18

    // Page indicator
    static let pageDotSize: CGFloat = 6
    static let pageDotHitWidth: CGFloat = 12
    static let pageDotRowHeight: CGFloat = 20

    // Folder panel
    static let folderWidthFactor: CGFloat = 0.80
    static let folderHeightFactor: CGFloat = 0.788
    static let folderCornerRadius: CGFloat = 30
    static let folderTitleFontSize: CGFloat = 22

    static func iconSize(for width: CGFloat) -> CGFloat {
        max(48, width / referenceWidth * iconSize)
    }

    static func scaled(_ value: CGFloat, for width: CGFloat) -> CGFloat {
        max(1, width / referenceWidth * value)
    }
}
