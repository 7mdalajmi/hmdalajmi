//
//  NoteEditorSheet.swift
//  Laqta
//
//  Write a note on any saved item. Notes are searchable and sync with the library.
//

import Foundation
import SwiftData
import SwiftUI

struct NoteEditorSheet: View {
    let item: Shot

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @AppObject(LibraryModel.self) private var library
    @Environment(\.laqta) private var palette

    @State private var text = ""
    @State private var didLoad = false
    @FocusState private var isFocused: Bool

    static let limit = 2_000

    var body: some View {
        VStack(spacing: 0) {
            SheetBar(item.note.isEmpty ? "Add Note" : "Edit Note") {
                Button {
                    dismiss()
                } label: {
                    BarTextButtonLabel(title: "Cancel")
                }
            } trailing: {
                Button {
                    save()
                } label: {
                    BarTextButtonLabel(title: "Save", prominent: true)
                }
                .disabled(!hasChanges)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    header
                    editor
                    footer
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .background(palette.sheet.ignoresSafeArea())
        .presentationDetents([.medium, .large])
        .presentationBackground(palette.sheet)
        .presentationCornerRadius(32)
        .onAppear {
            guard !didLoad else { return }
            didLoad = true
            text = item.note
            isFocused = true
        }
    }

    private var hasChanges: Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines) != item.note
    }

    private var header: some View {
        HStack(spacing: 12) {
            FolderItemCell(item: item, height: 56, showsBadges: false)
                .frame(width: 56)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: item.displayTitle)
                    .laqtaFont(15, weight: .semibold)
                    .foregroundStyle(palette.ink)
                    .lineLimit(2)
                Text(verbatim: "\(item.kindLabel) · \(LaqtaFormat.shortDate(item.addedAt))")
                    .laqtaFont(12)
                    .foregroundStyle(palette.ink2)
            }
            Spacer(minLength: 0)
        }
        .padding(.top, 4)
    }

    private var editor: some View {
        ZStack(alignment: .topLeading) {
            if text.isEmpty {
                Text("Why you saved it, what to remember, what to do next…")
                    .laqtaFont(16)
                    .foregroundStyle(palette.ink3)
                    .padding(.horizontal, 17)
                    .padding(.vertical, 16)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            TextEditor(text: $text)
                .laqtaFont(16)
                .foregroundStyle(palette.ink)
                .scrollContentBackground(.hidden)
                .focused($isFocused)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .frame(minHeight: 180)
                .accessibilityLabel(Text("Note"))
                .onChange(of: text) { _, newValue in
                    if newValue.count > Self.limit {
                        text = String(newValue.prefix(Self.limit))
                    }
                }
        }
        .background(palette.field, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(isFocused ? palette.buttonBorder : palette.line, lineWidth: 1))
    }

    private var footer: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: "magnifyingglass")
                .laqtaIconFont(11, weight: .semibold)
                .foregroundStyle(palette.ink3)
                .accessibilityHidden(true)
            Text("Search finds your notes too.")
                .laqtaFont(12)
                .foregroundStyle(palette.ink2)
            Spacer(minLength: 0)
            Text(verbatim: "\(LaqtaFormat.number(text.count)) / \(LaqtaFormat.number(Self.limit))")
                .laqtaFont(12, monospacedDigit: true)
                .foregroundStyle(text.count > Self.limit - 100 ? palette.goldHi : palette.ink3)
                .accessibilityLabel(Text(verbatim: "\(text.count) of \(Self.limit) characters"))
        }
        .overlay(alignment: .bottomLeading) {
            if !item.note.isEmpty {
                Button(role: .destructive) {
                    text = ""
                    save()
                } label: {
                    Label("Delete Note", systemImage: "trash")
                        .laqtaFont(14, weight: .medium)
                }
                .buttonStyle(.borderless)
                .tint(Color(hex: 0xE5735C))
                .offset(y: 44)
            }
        }
        .padding(.bottom, item.note.isEmpty ? 0 : 44)
    }

    private func save() {
        library.setNote(text, for: item, context: modelContext)
        dismiss()
    }
}
