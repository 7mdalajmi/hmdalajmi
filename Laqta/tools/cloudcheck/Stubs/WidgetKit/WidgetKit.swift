// cloudcheck stub: WidgetKit with the declaration headers of the iOS 27.0 SDK's WidgetKit.swiftinterface
// (copied by the stub audit). The Widget, WidgetBundle and WidgetConfiguration protocols live in the
// SwiftUI stub (SwiftUI declares them); WidgetKit adds timelines, StaticConfiguration and the configuration
// modifiers (@MainActor @preconcurrency), `EnvironmentValues.widgetFamily`, `ContainerBackgroundPlacement
// .widget`, widgetURL/widgetAccentable (@MainActor @preconcurrency) and WidgetCenter (not Sendable).
// TimelineProvider is not actor-isolated; its completion handlers are @Sendable (@preconcurrency).
@_exported import Foundation
import SwiftUI

public struct TimelineEntryRelevance : Codable, Hashable {
    public var score: Float
    public var duration: TimeInterval
    public init(score: Float) { self.score = score; self.duration = 0 }
    public init (score: Float, duration: TimeInterval = 0.0) { self.score = score; self.duration = duration }
}

public protocol TimelineEntry {
    var date: Date { get }
    var relevance: TimelineEntryRelevance? { get }
}
extension TimelineEntry {
    public var relevance: TimelineEntryRelevance? { nil }
}

public struct TimelineReloadPolicy : Equatable {
    private let id: Int
    private init(id: Int) { self.id = id }
    public static let atEnd: TimelineReloadPolicy = TimelineReloadPolicy(id: 0)
    public static let never: TimelineReloadPolicy = TimelineReloadPolicy(id: 1)
    public static func after(_ date: Date) -> TimelineReloadPolicy { TimelineReloadPolicy(id: 2) }
}

public struct Timeline<EntryType> where EntryType : TimelineEntry {
    public let entries: [EntryType]
    public let policy: TimelineReloadPolicy
    public init (entries: [EntryType], policy: TimelineReloadPolicy) {
        self.entries = entries
        self.policy = policy
    }
}

@preconcurrency public enum WidgetFamily : Int, RawRepresentable, CustomDebugStringConvertible, CustomStringConvertible, Sendable {
    case systemSmall
    case systemMedium
    case systemLarge
    case systemExtraLarge
    case accessoryCircular
    case accessoryRectangular
    case accessoryInline
    public var description: String { "\(rawValue)" }
    public var debugDescription: String { description }
}

public struct TimelineProviderContext {
    public var family: WidgetFamily { fatalError() }
    public var isPreview: Bool { fatalError() }
    public var displaySize: CGSize { fatalError() }
}

public protocol TimelineProvider {
    associatedtype Entry: TimelineEntry
    typealias Context = TimelineProviderContext
    func placeholder(in context: Self.Context) -> Self.Entry
    @preconcurrency func getSnapshot(in context: Self.Context, completion: @escaping @Sendable (Self.Entry) -> Void)
    @preconcurrency func getTimeline(in context: Self.Context, completion: @escaping @Sendable (Timeline<Self.Entry>) -> Void)
}

@MainActor @preconcurrency public struct StaticConfiguration<Content> : WidgetConfiguration where Content : View {
    public typealias Body = Never
    @MainActor @preconcurrency public init <Provider>(kind: String, provider: Provider, @ViewBuilder content: @escaping (Provider.Entry) -> Content) where Provider : TimelineProvider {}
}

extension WidgetConfiguration {
    @MainActor @preconcurrency public func configurationDisplayName(_ displayName: Text) -> some WidgetConfiguration { self }
    @MainActor @preconcurrency public func configurationDisplayName(_ displayNameKey: LocalizedStringKey) -> some WidgetConfiguration { self }
    @_disfavoredOverload @MainActor @preconcurrency public func configurationDisplayName<S>(_ displayName: S) -> some WidgetConfiguration where S : StringProtocol { self }
    @MainActor @preconcurrency public func description(_ description: Text) -> some WidgetConfiguration { self }
    @MainActor @preconcurrency public func description(_ descriptionKey: LocalizedStringKey) -> some WidgetConfiguration { self }
    @_disfavoredOverload @MainActor @preconcurrency public func description<S>(_ description: S) -> some WidgetConfiguration where S : StringProtocol { self }
    @MainActor @preconcurrency public func supportedFamilies(_ families: [WidgetFamily]) -> some WidgetConfiguration { self }
    @MainActor @preconcurrency public func contentMarginsDisabled() -> some WidgetConfiguration { self }
    @MainActor @preconcurrency public func containerBackgroundRemovable(_ isRemovable: Bool = true) -> some WidgetConfiguration { self }
}

extension EnvironmentValues {
    public var widgetFamily: WidgetFamily { fatalError() }
    public var showsWidgetContainerBackground: Bool { fatalError() }
    public var widgetContentMargins: EdgeInsets { fatalError() }
}

extension ContainerBackgroundPlacement {
    public static let widget = ContainerBackgroundPlacement(__harnessID: 100)
}

extension View {
    @MainActor @preconcurrency public func widgetURL(_ url: URL?) -> some View { self }
    @MainActor @preconcurrency public func widgetAccentable(_ accentable: Bool = true) -> some View { self }
}

@preconcurrency public struct WidgetInfo : Sendable {
    public var kind: String { fatalError() }
    public var family: WidgetFamily { fatalError() }
}

public class WidgetCenter {
    public static let shared: WidgetCenter = WidgetCenter()
    private init() {}
    public func reloadTimelines(ofKind kind: String) {}
    public func reloadAllTimelines() {}
    @preconcurrency public func getCurrentConfigurations(_ completion: @escaping @Sendable (Result<[WidgetInfo], any Error>) -> Void) {}
    public func currentConfigurations() async throws -> [WidgetInfo] { [] }
    public func invalidateConfigurationRecommendations() {}
}


// MARK: - Conformances the SDK declares in extensions (generated by the stub audit)
extension StaticConfiguration: Sendable {}
extension WidgetFamily: Hashable {}
extension WidgetInfo: Equatable {}
extension WidgetInfo: Hashable {}