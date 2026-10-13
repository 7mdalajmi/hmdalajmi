import SwiftUI

/// One square cell of the library grid: the photo's edited thumbnail (rendered from the original
/// through its recipe), with badges for RAW, HDR and high bit depth, and a dot when it has edits.
///
/// The thumbnail comes from `LibraryStore.thumbnail(for:)`, which observes only this project's slot,
/// so a thumbnail finishing elsewhere never redraws this cell.
@MainActor
struct LibraryCell: View {
    let project: PhotoProject

    @Environment(AppModel.self) private var app

    var body: some View {
        let thumbnail = app.library.thumbnail(for: project)
        let failed = thumbnail == nil && app.library.thumbnailFailed(for: project)

        Theme.surface2
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if let thumbnail {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .scaledToFill()
                        .transition(.opacity)
                } else if failed {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.title3)
                        .foregroundStyle(Theme.textTertiary)
                }
                // Otherwise the plain grey tile: thumbnails usually arrive within a fraction of a second.
            }
            .animation(.easeOut(duration: 0.2), value: thumbnail != nil)
            .clipped()
            .overlay(alignment: .bottomLeading) {
                badges
            }
            .overlay(alignment: .topTrailing) {
                if project.isEdited {
                    editedDot
                }
            }
            .contentShape(Rectangle())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: project.displayName))
            .accessibilityValue(Text(verbatim: accessibilityDetails(failed: failed)))
            .accessibilityAddTraits(.isImage)
    }

    // MARK: Badges

    /// Bit depth is shown for high-bit bitmaps; a RAW badge already implies 12-14 bits.
    private var showsBitDepth: Bool {
        !project.isRAW && project.bitsPerComponent > 8
    }

    @ViewBuilder
    private var badges: some View {
        if project.isRAW || project.isHDR || showsBitDepth {
            HStack(spacing: 3) {
                if project.isRAW {
                    LibraryBadge(text: Text("RAW"))
                }
                if project.isHDR {
                    LibraryBadge(text: Text("HDR"))
                }
                if showsBitDepth {
                    LibraryBadge(text: Text("\(project.bitsPerComponent)-bit"))
                }
            }
            .padding(Theme.Space.xs)
        }
    }

    private var editedDot: some View {
        Circle()
            .fill(Theme.accent)
            .frame(width: 8, height: 8)
            .overlay(Circle().stroke(Theme.scrim, lineWidth: 1))
            .padding(6)
    }

    // MARK: Accessibility

    /// "RAW, HDR and Edited" (localized list).
    private func accessibilityDetails(failed: Bool) -> String {
        var parts: [String] = []
        if project.isRAW { parts.append(String(localized: "RAW")) }
        if project.isHDR { parts.append(String(localized: "HDR")) }
        if showsBitDepth { parts.append(String(localized: "\(project.bitsPerComponent)-bit")) }
        if project.isEdited { parts.append(String(localized: "Edited")) }
        if failed { parts.append(String(localized: "Preview unavailable")) }
        return parts.formatted(.list(type: .and))
    }
}

// MARK: - Badge

/// A small label drawn over the photo on a black scrim.
private struct LibraryBadge: View {
    let text: Text

    var body: some View {
        text
            .font(.caption2.weight(.semibold))
            .foregroundStyle(Theme.textPrimary)
            .lineLimit(1)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(Theme.scrim, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
            .dynamicTypeSize(...DynamicTypeSize.large)
    }
}
