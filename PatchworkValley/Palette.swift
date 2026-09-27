import SwiftUI
import UIKit
import ValleyCore

enum Palette {
    static let board = UIColor(red: 0.18, green: 0.24, blue: 0.21, alpha: 1)
    static let rim = UIColor.black.withAlphaComponent(0.18)
    static let slot = UIColor.white
    static let legal = UIColor(red: 0.55, green: 0.95, blue: 0.55, alpha: 1)
    static let illegal = UIColor(red: 1.0, green: 0.42, blue: 0.38, alpha: 1)
    static let clash = UIColor(white: 0.55, alpha: 1)
    static let houseWall = UIColor(red: 0.97, green: 0.93, blue: 0.85, alpha: 1)
}

extension Terrain {
    /// The terrain's own color. Water is the river color.
    var uiColor: UIColor {
        switch self {
        case .meadow: UIColor(red: 0.61, green: 0.80, blue: 0.42, alpha: 1)
        case .forest: UIColor(red: 0.31, green: 0.54, blue: 0.29, alpha: 1)
        case .field: UIColor(red: 0.91, green: 0.79, blue: 0.35, alpha: 1)
        case .village: UIColor(red: 0.85, green: 0.62, blue: 0.47, alpha: 1)
        case .water: UIColor(red: 0.30, green: 0.61, blue: 0.84, alpha: 1)
        }
    }

    /// Color for the small details drawn on top: trees, crop rows, roofs.
    var detailColor: UIColor {
        switch self {
        case .meadow: UIColor(red: 0.50, green: 0.70, blue: 0.33, alpha: 1)
        case .forest: UIColor(red: 0.18, green: 0.37, blue: 0.20, alpha: 1)
        case .field: UIColor(red: 0.72, green: 0.58, blue: 0.18, alpha: 1)
        case .village: UIColor(red: 0.66, green: 0.26, blue: 0.18, alpha: 1)
        case .water: UIColor(red: 0.62, green: 0.82, blue: 0.95, alpha: 1)
        }
    }

    var color: Color { Color(uiColor: uiColor) }

    var symbolName: String {
        switch self {
        case .meadow: "leaf.fill"
        case .forest: "tree.fill"
        case .field: "carrot.fill"
        case .village: "house.fill"
        case .water: "drop.fill"
        }
    }

    var displayName: String {
        switch self {
        case .meadow: "Meadow"
        case .forest: "Forest"
        case .field: "Field"
        case .village: "Village"
        case .water: "River"
        }
    }
}
