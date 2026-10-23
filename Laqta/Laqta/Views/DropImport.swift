//
//  DropImport.swift
//  Laqta
//
//  Dropping photos, videos, PDFs or links onto a folder (iPad and multitasking)
//  opens Save to Laqta for that folder. Items dragged inside Laqta move instead.
//

import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// Save to Laqta for dropped items, presented as a sheet.
@Observable
final class DropImportModel {
    struct Request: Identifiable {
        let id = UUID()
        let session: SaveSession
    }

    var request: Request?

    static let acceptedTypes: [UTType] = [.image, .movie, .pdf, .url, .plainText]

    func start(providers: [NSItemProvider], folderID: UUID?, onDone: @escaping () -> Void) {
        // After the thirty days a drop moves nothing in; the paywall answers instead.
        guard AppObjects.registered(PurchaseCenter.self)?.allowAdding(.saving) ?? true else { return }
        let inputs = providers
            .filter { ItemProviderLoader.kind(of: $0) != nil }
            .prefix(SaveSession.itemLimit)
            .map { SaveInput.provider(ProviderBox(provider: $0)) }
        guard !inputs.isEmpty else { return }
        let session = SaveSession(
            inputs: Array(inputs),
            fixedFolderID: folderID,
            onFinish: { [weak self] in
                self?.request = nil
                onDone()
            },
            onCancel: { [weak self] in
                self?.request = nil
            }
        )
        request = Request(session: session)
    }
}

/// Carries the model context into main-actor work started from a drop callback.
private final class ContextBox {
    let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }
}

private struct DropImportSheetModifier: ViewModifier {
    @Bindable var model: DropImportModel

    func body(content: Content) -> some View {
        content.sheet(item: $model.request) { request in
            SaveSheet(session: request.session)
                .laqtaThemed()
                .presentationDetents([.large])
                .interactiveDismissDisabled(request.session.isBusy)
        }
    }
}

private struct FolderDropModifier: ViewModifier {
    let folderID: UUID
    let model: DropImportModel
    @Binding var isTargeted: Bool

    @AppObject(LibraryModel.self) private var library
    @AppObject(IntelligenceCenter.self) private var intelligence
    @Environment(\.modelContext) private var modelContext

    func body(content: Content) -> some View {
        content.onDrop(of: [.laqtaItem] + DropImportModel.acceptedTypes, isTargeted: $isTargeted) { providers in
            handle(providers)
        }
    }

    private func handle(_ providers: [NSItemProvider]) -> Bool {
        let ownItems = providers.filter { $0.hasItemConformingToTypeIdentifier(UTType.laqtaItem.identifier) }
        if !ownItems.isEmpty {
            moveInternal(ownItems)
            return true
        }
        guard providers.contains(where: { ItemProviderLoader.kind(of: $0) != nil }) else { return false }
        model.start(providers: providers, folderID: folderID) {
            library.noteLocalSave(to: folderID)
            intelligence.processPending(context: modelContext)
        }
        return true
    }

    private func moveInternal(_ providers: [NSItemProvider]) {
        let target = folderID
        let box = ContextBox(context: modelContext)
        let library = library
        for provider in providers {
            _ = provider.loadTransferable(type: ItemTransfer.self) { result in
                guard case let .success(transfer) = result else { return }
                let itemID = transfer.id
                Task { @MainActor in
                    let context = box.context
                    guard let folder = LaqtaStore.folder(with: target, context: context),
                          let item = LaqtaStore.item(with: itemID, context: context),
                          item.folderID != target else { return }
                    withAnimation(.snappy) {
                        library.move([item], to: folder, context: context)
                    }
                }
            }
        }
    }
}

extension View {
    /// Presents Save to Laqta for items dropped with `acceptsDrops`.
    func dropImportSheet(_ model: DropImportModel) -> some View {
        modifier(DropImportSheetModifier(model: model))
    }

    /// Accepts dropped items: Laqta items move here, everything else is saved here.
    func acceptsDrops(into folderID: UUID, model: DropImportModel, isTargeted: Binding<Bool>) -> some View {
        modifier(FolderDropModifier(folderID: folderID, model: model, isTargeted: isTargeted))
    }
}
