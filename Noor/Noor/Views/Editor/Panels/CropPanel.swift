import SwiftUI

// MARK: - Crop panel

/// The Crop tool's panel (the photo area shows `CropWorkspace` meanwhile):
///   * aspect chips – Original · Free · 1:1 · 4:5 · 3:2 · 16:9, each shown in the crop's current
///     orientation, plus an orientation-swap button;
///   * the straighten ruler (−45°…45°);
///   * Rotate left / right (exact 90° turns), Flip horizontal / vertical;
///   * Reset (in the header).
///
/// Geometry is stored as numbers (`EditRecipe.geometry`), so all of this is lossless until export,
/// which re-renders the original. Turns and flips move the crop with the picture, so the framing
/// the user chose is kept. One-shot buttons use `model.apply`; the ruler writes
/// `model.binding(\EditRecipe.geometry)` between `beginInteraction()` / `endInteraction(_:)`.
@MainActor
struct CropPanel: View {
    let model: EditorModel

    /// The crop when the current straighten gesture began (nil when not straightening).
    @State private var straightenBaseline: StraightenBaseline?

    private var geometry: Geometry { model.recipe.geometry }

    var body: some View {
        VStack(spacing: 0) {
            PanelHeader("Crop") { resetGeometry() }
                .disabled(geometry == Geometry())

            ScrollView(.vertical) {
                VStack(spacing: 16) {
                    aspectRow

                    StraightenRuler(value: geometry.straighten,
                                    onChange: { setStraighten($0) },
                                    onEditingChanged: { straightenEditingChanged($0) })
                        .padding(.horizontal, 16)

                    actionRow
                        .padding(.horizontal, 16)
                }
                .padding(.top, 4)
                .padding(.bottom, 16)
            }
            .scrollIndicators(.hidden)
            .scrollBounceBehavior(.basedOnSize)
        }
    }

    // MARK: Aspect ratio

    private var aspectRow: some View {
        let g = geometry
        let portrait = CropAspectChoice.prefersPortrait(crop: g.crop, frameSize: model.frameSize)
        return HStack(spacing: 0) {
            ChipPicker(CropAspectChoice.allCases, selection: aspectSelection, fillsWidth: false) { choice in
                choice.label(for: choice.aspect(current: g.aspect, portrait: portrait))
            }
            swapButton
                .padding(.trailing, 8)
        }
    }

    /// The chip that contains the recipe's aspect; choosing a chip applies its variant for the
    /// crop's current orientation.
    private var aspectSelection: Binding<CropAspectChoice> {
        Binding(
            get: { @MainActor in CropAspectChoice.containing(model.recipe.geometry.aspect) },
            set: { @MainActor choice in selectAspect(choice) }
        )
    }

    private var swapButton: some View {
        let canSwap = canSwapOrientation
        return Button {
            swapOrientation()
        } label: {
            Image(systemName: "rectangle.portrait.rotate")
                .font(.system(size: 17, weight: .medium))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(canSwap ? Theme.textPrimary : Theme.textTertiary)
        .disabled(!canSwap)
        .accessibilityLabel(Text("Swap Orientation"))
    }

    /// Fixed ratios swap (4:5 ↔ 5:4 …); a free crop swaps its own width and height.
    private var canSwapOrientation: Bool {
        let g = geometry
        if g.aspect == .free {
            let aspect = CropEditMath.pixelAspect(g.crop, frameSize: model.frameSize)
            return aspect > 0 && abs(aspect - 1) > 0.01
        }
        return g.aspect.swapped != g.aspect
    }

    private func selectAspect(_ choice: CropAspectChoice) {
        let frameSize = model.frameSize
        let g = geometry
        let portrait = CropAspectChoice.prefersPortrait(crop: g.crop, frameSize: frameSize)
        let aspect = choice.aspect(current: g.aspect, portrait: portrait)
        guard aspect != g.aspect else { return }
        model.apply(String(localized: "Aspect Ratio")) { recipe in
            recipe.geometry.aspect = aspect
            // Free keeps the current crop; a ratio starts from its largest centred crop.
            if let ratio = aspect.ratio(frameSize: frameSize) {
                recipe.geometry.crop = Geometry.maximalCrop(frameSize: frameSize,
                                                            straighten: recipe.geometry.straighten,
                                                            aspect: ratio)
            }
        }
    }

    private func swapOrientation() {
        let frameSize = model.frameSize
        model.apply(String(localized: "Aspect Ratio")) { recipe in
            let g = recipe.geometry
            let ratio: Double
            if g.aspect == .free {
                let current = CropEditMath.pixelAspect(g.crop, frameSize: frameSize)
                guard current > 0 else { return }
                ratio = 1 / current
            } else {
                let swapped = g.aspect.swapped
                guard swapped != g.aspect, let swappedRatio = swapped.ratio(frameSize: frameSize) else { return }
                recipe.geometry.aspect = swapped
                ratio = swappedRatio
            }
            recipe.geometry.crop = CropEditMath.swappedOrientation(g.crop, ratio: ratio,
                                                                   frameSize: frameSize,
                                                                   straighten: g.straighten)
        }
    }

    // MARK: Straighten

    private func straightenEditingChanged(_ isEditing: Bool) {
        if isEditing {
            straightenBaseline = StraightenBaseline(geometry: geometry, frameSize: model.frameSize)
            model.beginInteraction()
        } else {
            model.endInteraction(String(localized: "Straighten"))
            straightenBaseline = nil
        }
    }

    /// New angle; the crop stays valid (shrunk about its centre) or, if it was the largest
    /// possible crop, stays the largest possible crop for the new angle.
    private func setStraighten(_ degrees: Double) {
        let frameSize = model.frameSize
        let current = geometry
        let baseline = straightenBaseline ?? StraightenBaseline(geometry: current, frameSize: frameSize)
        var next = current
        next.straighten = EditRecipe.Limits.straighten.clamp(degrees)
        next.crop = baseline.adjustedCrop(forStraighten: next.straighten, frameSize: frameSize)
        guard next != current else { return }
        model.binding(\EditRecipe.geometry).wrappedValue = next
    }

    // MARK: Rotate / flip / reset

    private var actionRow: some View {
        HStack(spacing: 4) {
            actionButton("Rotate Left", systemImage: "rotate.left") { rotate(clockwise: false) }
            actionButton("Rotate Right", systemImage: "rotate.right") { rotate(clockwise: true) }
            actionButton("Flip Horizontal",
                         systemImage: "arrow.left.and.right.righttriangle.left.righttriangle.right") {
                flip(horizontal: true)
            }
            actionButton("Flip Vertical",
                         systemImage: "arrow.up.and.down.righttriangle.up.righttriangle.down") {
                flip(horizontal: false)
            }
        }
        // Physical directions: never mirrored.
        .environment(\.layoutDirection, .leftToRight)
    }

    private func actionButton(_ title: LocalizedStringKey, systemImage: String,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.system(size: 19, weight: .regular))
                    .frame(height: 24)
                Text(title)
                    .font(.caption2)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(Theme.textPrimary)
            .frame(maxWidth: .infinity, minHeight: 52)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Turns the picture 90° on screen. With exactly one flip active, a clockwise turn on screen
    /// is a counter-clockwise quarter turn of the source (turns are applied before flips).
    /// The crop turns with the picture, and a fixed ratio swaps orientation (4:5 → 5:4).
    private func rotate(clockwise: Bool) {
        let newFrameSize = CGSize(width: model.frameSize.height, height: model.frameSize.width)
        model.apply(String(localized: "Rotate")) { recipe in
            var g = recipe.geometry
            let oneFlip = g.flipHorizontal != g.flipVertical
            let delta = clockwise != oneFlip ? 1 : -1
            g.quarterTurns = (((g.quarterTurns + delta) % 4) + 4) % 4
            g.aspect = g.aspect.swapped
            g.crop = Geometry.constrained(CropEditMath.rotatedQuarter(g.crop, clockwise: clockwise),
                                          frameSize: newFrameSize, straighten: g.straighten)
            recipe.geometry = g
        }
    }

    /// Mirrors the result on screen. Flips are applied before straightening, so the angle changes
    /// sign and the crop mirrors too: the output is an exact mirror image of what was there.
    private func flip(horizontal: Bool) {
        let frameSize = model.frameSize
        let label = horizontal ? String(localized: "Flip Horizontal") : String(localized: "Flip Vertical")
        model.apply(label) { recipe in
            var g = recipe.geometry
            if horizontal {
                g.flipHorizontal.toggle()
                g.crop = CropEditMath.mirroredHorizontally(g.crop)
            } else {
                g.flipVertical.toggle()
                g.crop = CropEditMath.mirroredVertically(g.crop)
            }
            g.straighten = g.straighten == 0 ? 0 : -g.straighten
            g.crop = Geometry.constrained(g.crop, frameSize: frameSize, straighten: g.straighten)
            recipe.geometry = g
        }
    }

    private func resetGeometry() {
        model.apply(String(localized: "Reset Crop")) { $0.geometry = Geometry() }
    }
}

// MARK: - Straighten baseline

/// The crop at the start of a straighten gesture. Each new angle is applied to this baseline (not
/// to the previous frame's result), so turning the ruler back restores the original size.
private struct StraightenBaseline {
    let crop: NormalizedRect
    let ratio: Double
    let wasMaximal: Bool

    init(geometry g: Geometry, frameSize: CGSize) {
        let valid = Geometry.constrained(g.crop, frameSize: frameSize, straighten: g.straighten)
        let measured = g.aspect.ratio(frameSize: frameSize) ?? CropEditMath.pixelAspect(valid, frameSize: frameSize)
        let lockedRatio = measured > 0 ? measured : 1
        crop = valid
        ratio = lockedRatio
        wasMaximal = CropEditMath.isMaximal(g.crop, ratio: lockedRatio, frameSize: frameSize,
                                            straighten: g.straighten)
    }

    func adjustedCrop(forStraighten degrees: Double, frameSize: CGSize) -> NormalizedRect {
        if wasMaximal {
            return Geometry.maximalCrop(frameSize: frameSize, straighten: degrees, aspect: ratio)
        }
        return Geometry.constrained(self.crop, frameSize: frameSize, straighten: degrees)
    }
}

// MARK: - Aspect chips

/// One aspect chip. Ratio chips stand for both orientations (4:5 and 5:4, …).
private enum CropAspectChoice: String, CaseIterable, Identifiable {
    case original, free, square, fourFive, threeTwo, sixteenNine

    var id: String { rawValue }

    /// The chip that contains `aspect`.
    static func containing(_ aspect: CropAspect) -> CropAspectChoice {
        switch aspect {
        case .original: return .original
        case .free: return .free
        case .square: return .square
        case .r4x5, .r5x4: return .fourFive
        case .r3x2, .r2x3: return .threeTwo
        case .r16x9, .r9x16: return .sixteenNine
        }
    }

    /// The concrete aspect this chip applies: the current one if it already belongs to the chip,
    /// otherwise the variant in the crop's orientation.
    func aspect(current: CropAspect, portrait: Bool) -> CropAspect {
        if CropAspectChoice.containing(current) == self { return current }
        switch self {
        case .original: return .original
        case .free: return .free
        case .square: return .square
        case .fourFive: return portrait ? .r4x5 : .r5x4
        case .threeTwo: return portrait ? .r2x3 : .r3x2
        case .sixteenNine: return portrait ? .r9x16 : .r16x9
        }
    }

    func label(for aspect: CropAspect) -> Text {
        switch self {
        case .original: return Text("Original")
        case .free: return Text("Free")
        default: return Text(verbatim: aspect.ratioLabel ?? "")
        }
    }

    /// Whether the crop (in pixels) is portrait; a square crop follows the frame.
    static func prefersPortrait(crop: NormalizedRect, frameSize: CGSize) -> Bool {
        let w = crop.width * Double(frameSize.width)
        let h = crop.height * Double(frameSize.height)
        if abs(w - h) <= 0.5 { return frameSize.height > frameSize.width }
        return h > w
    }
}
