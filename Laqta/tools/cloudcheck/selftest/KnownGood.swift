// cloudcheck self-test: idioms the iOS 27.0 SDK accepts without diagnostics at the iOS 26.0 deployment
// target (checked with `check.sh --selftest --sdk SDK_DIR`). Compiled by `check.sh --selftest` with the app
// settings; any diagnostic here is a stub (or harness) bug, not an app finding.
import SwiftUI
import WidgetKit
import UserNotifications

@Observable final class SelfTestModel { var count = 0; var name = ""; var on = false; var tab = 0 }

private enum SelfTestKey: EnvironmentKey { static let defaultValue = 3 }
extension EnvironmentValues {
    var selfTestValue: Int { get { self[SelfTestKey.self] } set { self[SelfTestKey.self] = newValue } }
}

struct SelfTestView: View {
    @Environment(SelfTestModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme
    @Environment(\.selfTestValue) private var value
    @State private var text = ""
    @State private var date = Date()
    @FocusState private var focused: Bool
    @State private var showSheet = false

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Hello").font(.title).bold().foregroundStyle(.secondary)
                    Text("a \(Text("b").italic())")
                    Text(verbatim: "x").font(.system(size: 12)).font(.system(.body, design: .rounded))
                    Text("Count \(model.count)")
                    Text(Date(), style: .time)
                    Image(systemName: "star").imageScale(.large).foregroundStyle(.red, .blue)
                    Label("Title", systemImage: "star")
                    Button("Tap") { model.count += 1 }
                    Button("Delete", role: .destructive) { dismiss() }
                    Button { showSheet = true } label: { Image(systemName: "plus") }.buttonStyle(.borderedProminent)
                    TextField("Name", text: $model.name).focused($focused).textFieldStyleFree()
                    Toggle("On", isOn: $model.on)
                    DatePicker("Date", selection: $date, displayedComponents: .date)
                    Picker("Tab", selection: $model.tab) { ForEach(0..<3) { Text("\($0)").tag($0) } }.pickerStyle(.segmented)
                    ForEach(["a", "b"], id: \.self) { Text($0) }
                    if model.on { Text("on") } else { Text("off") }
                    ProgressView(value: 0.5)
                    Divider()
                    Spacer()
                }
                .padding()
                .background(Color.red)
                .background(.ultraThinMaterial)
                .background(.blue, in: RoundedRectangle(cornerRadius: 8))
                .overlay(alignment: .topTrailing) { Circle().fill(.red).frame(width: 8, height: 8) }
                .overlay(Capsule().stroke(.gray, lineWidth: 1))
                .clipShape(.rect)
            }
            .navigationDestination(for: Int.self) { Text("\($0)") }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } }
            }
        }
        .sheet(isPresented: $showSheet) { Text("Sheet").presentationDetents([.medium]) }
        .task { await work() }
        .task(id: model.count) { await work() }
        .onChange(of: model.count) { old, new in print(old, new) }
        .onChange(of: model.count) { print("changed") }
        .animation(.spring, value: model.count)
        .transition(.opacity)
        .environment(\.selfTestValue, 4)
        .tint(.orange)
    }

    func work() async {}
}

private extension View {
    func textFieldStyleFree() -> some View { self }
}

extension Shape {
    func selfTestShapes() -> some View { self.fill(.blue).opacity(0.5) }
}

struct SelfTestLists: View {
    @State private var showAlert = false
    let items = ["a", "b"]
    var body: some View {
        NavigationStack {
            List {
                Section("One") { Text("1") }
                Section { Text("2") } header: { Text("H") } footer: { Text("F") }
                ForEach(items, id: \.self) { Text($0) }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Lists")
            .navigationBarTitleDisplayMode(.inline)
            .alert("Oops", isPresented: $showAlert) { Button("OK", role: .cancel) {} } message: { Text("m") }
            Form { Toggle("x", isOn: .constant(true)) }
            Menu("More") { Button("A") {} }
            List(items, id: \.self) { Text($0) }
        }
    }
}

struct SelfTestTabs: View {
    @State private var tab = 0
    @State private var text = ""
    var body: some View {
        TabView(selection: $tab) {
            Tab("One", systemImage: "1.circle", value: 0) { SelfTestLists() }
            Tab("Two", systemImage: "2.circle", value: 1) {
                TextField("Amount", text: $text)
                    .keyboardType(.decimalPad)
                    .toolbar {
                        ToolbarItemGroup(placement: .keyboard) {
                            Spacer()
                            Button("Done") { text = "" }
                        }
                    }
            }
        }
    }
}

struct SelfTestApp: App {
    @State private var model = SelfTestModel()
    var body: some Scene {
        WindowGroup { SelfTestView().environment(model) }
    }
}

nonisolated struct SelfTestEntry: TimelineEntry { let date: Date }

nonisolated struct SelfTestProvider: TimelineProvider {
    func placeholder(in context: Context) -> SelfTestEntry { SelfTestEntry(date: Date()) }
    func getSnapshot(in context: Context, completion: @escaping (SelfTestEntry) -> Void) {
        completion(SelfTestEntry(date: Date()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<SelfTestEntry>) -> Void) {
        completion(Timeline(entries: [SelfTestEntry(date: Date())], policy: .atEnd))
    }
}

struct SelfTestWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "SelfTest", provider: SelfTestProvider()) { entry in
            Text(entry.date, style: .time).containerBackground(for: .widget) { Color.clear }
        }
        .configurationDisplayName("Self test")
        .supportedFamilies([.systemSmall, .accessoryRectangular])
    }
}

func selfTestNotify() async {
    let center = UNUserNotificationCenter.current()
    _ = try? await center.requestAuthorization(options: [.alert, .sound])
    let content = UNMutableNotificationContent()
    content.title = "T"
    let trigger = UNCalendarNotificationTrigger(dateMatching: DateComponents(hour: 9), repeats: false)
    try? await center.add(UNNotificationRequest(identifier: "x", content: content, trigger: trigger))
    WidgetCenter.shared.reloadAllTimelines()
}

func selfTestSchedule(_ ids: [String]) {
    let center = UNUserNotificationCenter.current()
    center.removeAllPendingNotificationRequests()
    for id in ids {
        center.add(UNNotificationRequest(identifier: id, content: UNMutableNotificationContent(), trigger: nil), withCompletionHandler: nil)
    }
}
