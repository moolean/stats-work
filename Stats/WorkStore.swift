import Foundation
import SwiftUI
import WidgetKit

@MainActor
final class WorkStore: ObservableObject {
    @Published private(set) var items: [WorkItem] = []
    @Published private(set) var errorMessage: String?
    @Published private(set) var waitingToSave = false
    private(set) var canEdit = false

    private let files: WorkFiles
    private var pending: DispatchWorkItem?
    private var dirty = false
    private var widgetPins: [PinnedItem]?

    init(files: WorkFiles = .local) {
        self.files = files
        load()
    }

    private func load() {
        do {
            items = try files.load()
            widgetPins = try? files.loadPins()
            let expectedPins = WorkFiles.pins(in: items)
            canEdit = true
            errorMessage = nil
            if !items.isEmpty && widgetPins != expectedPins {
                dirty = true
                _ = flush()
            }
        } catch {
            canEdit = false
            errorMessage = "读取工作项失败。原文件已保留，可以重试。"
        }
    }

    func retry() {
        if canEdit { _ = flush() } else { load() }
    }

    func item(_ id: UUID) -> WorkItem? {
        items.first { $0.id == id }
    }

    func openOrAdd(_ input: String) -> UUID? {
        let keyword = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard canEdit, !keyword.isEmpty else { return nil }
        if let match = WorkFiles.exactMatch(keyword, in: items) { return match.id }
        let newItem = WorkItem(keyword: keyword)
        items.append(newItem)
        markDirty(immediate: true)
        return newItem.id
    }

    func rename(_ id: UUID, to input: String) -> String? {
        guard canEdit, let index = items.firstIndex(where: { $0.id == id }) else { return nil }
        let keyword = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyword.isEmpty else { return "关键词不能为空。" }
        guard keyword != items[index].keyword else { return nil }
        let otherItems = items.filter { $0.id != id }
        guard WorkFiles.exactMatch(keyword, in: otherItems) == nil else { return "这个关键词已存在。" }
        items[index].keyword = keyword
        markDirty(immediate: true)
        return nil
    }

    func writeNotes(_ text: String, for id: UUID) {
        guard canEdit, let index = items.firstIndex(where: { $0.id == id }),
              items[index].notes != text else { return }
        items[index].notes = text
        markDirty()
    }

    func writeLink(_ text: String, for id: UUID) {
        guard canEdit, let index = items.firstIndex(where: { $0.id == id }),
              items[index].link != text else { return }
        items[index].link = text
        markDirty()
    }

    func togglePin(_ id: UUID) {
        guard canEdit, let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].pinned.toggle()
        markDirty(immediate: true)
    }

    func move(from offsets: IndexSet, to destination: Int) {
        guard canEdit else { return }
        items.move(fromOffsets: offsets, toOffset: destination)
        markDirty(immediate: true)
    }

    func remove(_ id: UUID) {
        guard canEdit else { return }
        items.removeAll { $0.id == id }
        markDirty(immediate: true)
    }

    private func markDirty(immediate: Bool = false) {
        dirty = true
        pending?.cancel()
        if immediate {
            _ = flush()
            return
        }
        waitingToSave = true
        let operation = DispatchWorkItem { [weak self] in _ = self?.flush() }
        pending = operation
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(450), execute: operation)
    }

    @discardableResult
    func flush() -> Bool {
        pending?.cancel()
        pending = nil
        waitingToSave = false
        guard canEdit else { return false }
        guard dirty else { return true }
        do {
            try files.save(items)
            let latestPins = WorkFiles.pins(in: items)
            if widgetPins != latestPins {
                widgetPins = latestPins
                WidgetCenter.shared.reloadTimelines(ofKind: WorkFiles.widgetKind)
            }
            dirty = false
            errorMessage = nil
            return true
        } catch {
            errorMessage = "保存失败，编辑内容仍在面板中。请重试。"
            return false
        }
    }
}
