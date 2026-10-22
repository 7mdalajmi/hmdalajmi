//
//  ShotInfoSheet.swift
//  لقطة
//

import Foundation
import SwiftData
import SwiftUI

struct ShotInfoSheet: View {
    @Bindable var shot: Shot
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Spacer()
                        ShotThumbnail(shot: shot, cornerRadius: 16)
                            .frame(width: 150, height: 150 * aspect)
                        Spacer()
                    }
                    .listRowBackground(Color.clear)
                }

                Section("ملاحظة") {
                    TextField("أضف ملاحظة…", text: $shot.note, axis: .vertical)
                        .lineLimit(2...6)
                }

                Section("التفاصيل") {
                    LabeledContent("النوع", value: shot.isScreenshot ? "لقطة شاشة" : "صورة")
                    LabeledContent("الأبعاد", value: "\(shot.pixelWidth) × \(shot.pixelHeight)")
                    LabeledContent("الحجم", value: Int64(shot.byteCount).formatted(.byteCount(style: .file)))
                    if let name = shot.originalName, !name.isEmpty {
                        LabeledContent("الاسم الأصلي", value: name)
                    }
                    if let captured = shot.capturedAt {
                        LabeledContent("التُقطت", value: captured.formatted(date: .long, time: .shortened))
                    }
                    LabeledContent("أُضيفت", value: shot.addedAt.formatted(date: .long, time: .shortened))
                }

                Section("ألبوم الصور") {
                    LabeledContent("الأصل", value: statusText)
                }
            }
            .navigationTitle("معلومات")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("تم") {
                        try? modelContext.save()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationBackground(Color(uiColor: .systemGroupedBackground))
    }

    private var aspect: CGFloat {
        guard shot.pixelWidth > 0 else { return 1 }
        return min(max(CGFloat(shot.pixelHeight) / CGFloat(shot.pixelWidth), 0.5), 2)
    }

    private var statusText: String {
        switch shot.libraryStatus {
        case .untouched: "باقٍ في ألبوم الصور"
        case .pendingDeletion: "بانتظار الحذف"
        case .deleted: "حُذف من ألبوم الصور"
        case .notFound: "لم يُعثر عليه"
        case .declined: "أُبقي بطلبك"
        }
    }
}
