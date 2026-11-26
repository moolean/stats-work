import SwiftUI

@MainActor
final class PanelState: ObservableObject {
    enum Field: Hashable { case search, keyword, notes }

    struct FocusRequest: Equatable {
        let field: Field
        let id = UUID()
    }

    @Published var query = ""
    @Published var keyword = ""
    @Published private(set) var keywordError: String?
    @Published private(set) var selection: UUID?
    @Published private(set) var focusRequest = FocusRequest(field: .search)
    private var savedKeyword = ""

    func select(_ item: WorkItem?) {
        guard selection != item?.id else { return }
        selection = item?.id
        keyword = item?.keyword ?? ""
        savedKeyword = keyword
        keywordError = nil
    }

    func requestFocus(_ field: Field) {
        focusRequest = FocusRequest(field: field)
    }

    @discardableResult
    func commitKeyword(in store: WorkStore) -> Bool {
        guard let id = selection, let item = store.item(id) else { return true }
        if keyword == savedKeyword {
            savedKeyword = item.keyword
            keyword = item.keyword
            return keywordError == nil
        }
        keywordError = store.rename(id, to: keyword)
        keyword = store.item(id)?.keyword ?? item.keyword
        savedKeyword = keyword
        return keywordError == nil
    }

    func beginEditingKeyword() {
        keywordError = nil
    }
}

struct WorkPanel: View {
    @ObservedObject var store: WorkStore
    @ObservedObject var state: PanelState
    @FocusState private var focus: PanelState.Field?
    @State private var confirmRemoval = false

    private var query: String { state.query.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var filtered: [WorkItem] {
        guard !query.isEmpty else { return store.items }
        return store.items.filter {
            $0.keyword.range(of: query, options: [.caseInsensitive, .widthInsensitive], locale: .current) != nil
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            searchBar
            Divider()
            HStack(spacing: 0) {
                itemList
                    .frame(idealWidth: 180, maxWidth: 180, maxHeight: .infinity)
                Divider()
                if let id = state.selection, let item = store.item(id) {
                    editor(item)
                        .id(item.id)
                } else {
                    Text(store.items.isEmpty ? "输入关键词，按回车开始记录。" : "选择一个工作项查看或编辑笔记。")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            Divider()
            statusBar
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { focus = state.focusRequest.field }
        .onChange(of: state.focusRequest) { _, request in
            DispatchQueue.main.async { focus = request.field }
        }
        .onChange(of: store.items.first { $0.id == state.selection }?.keyword) { _, _ in
            if focus != .keyword { state.commitKeyword(in: store) }
        }
        .onChange(of: focus) { previous, next in
            if previous == .keyword { state.commitKeyword(in: store) }
            if next == .keyword { state.beginEditingKeyword() }
        }
        .onDisappear {
            state.commitKeyword(in: store)
            store.flush()
        }
    }

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("搜索或输入关键词", text: $state.query)
                .textFieldStyle(.plain)
                .focused($focus, equals: .search)
                .onSubmit(commitSearch)
                .disabled(!store.canEdit)
            Button(action: commitSearch) {
                Label("新增", systemImage: "plus")
            }
            .disabled(!store.canEdit || query.isEmpty)
            .help("输入关键词后按回车新增或打开同名工作项")
        }
        .padding(.horizontal, 16)
        .frame(height: 45)
    }

    private var itemList: some View {
        let reorder: ((IndexSet, Int) -> Void)? = query.isEmpty ? { offsets, destination in
            store.move(from: offsets, to: destination)
        } : nil
        return Group {
            if filtered.isEmpty {
                Text(query.isEmpty ? "还没有工作项" : "没有匹配的工作项")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(filtered, content: itemRow)
                        .onMove(perform: reorder)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .background(.quaternary.opacity(0.35))
        .accessibilityLabel("工作项")
    }

    private func itemRow(_ item: WorkItem) -> some View {
        HStack(spacing: 6) {
            Button {
                open(item)
            } label: {
                Text(item.keyword)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(state.selection == item.id ? .isSelected : [])
            .help(item.keyword)
            Button {
                store.togglePin(item.id)
            } label: {
                Image(systemName: item.pinned ? "pin.fill" : "pin")
                    .foregroundStyle(item.pinned ? Color.accentColor : Color.secondary)
            }
            .buttonStyle(.borderless)
            .disabled(!store.canEdit)
            .accessibilityLabel(item.pinned ? "取消置顶 \(item.keyword)" : "置顶 \(item.keyword)")
            .help(item.pinned ? "取消置顶" : "置顶到小组件")
        }
        .frame(minHeight: 27)
        .listRowBackground(state.selection == item.id ? Color.accentColor.opacity(0.16) : Color.clear)
    }

    private func editor(_ item: WorkItem) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                TextField("关键词", text: $state.keyword)
                    .font(.title3.weight(.semibold))
                    .focused($focus, equals: .keyword)
                    .onSubmit {
                        if state.commitKeyword(in: store) { focus = .notes }
                    }
                    .accessibilityLabel("关键词")
                Button {
                    store.togglePin(item.id)
                } label: {
                    Image(systemName: item.pinned ? "pin.fill" : "pin")
                        .foregroundStyle(item.pinned ? Color.accentColor : Color.secondary)
                }
                .accessibilityLabel(item.pinned ? "取消置顶" : "置顶")
                .help(item.pinned ? "取消置顶" : "置顶到小组件")
                Button {
                    confirmRemoval = true
                } label: {
                    Image(systemName: "trash")
                }
                .accessibilityLabel("删除工作项")
                .help("删除工作项")
                .confirmationDialog("删除「\(item.keyword)」及笔记？", isPresented: $confirmRemoval, titleVisibility: .visible) {
                    Button("删除工作项", role: .destructive) {
                        state.select(nil)
                        store.remove(item.id)
                        state.requestFocus(.search)
                    }
                    Button("取消", role: .cancel) {}
                }
            }
            if let error = state.keywordError {
                Text(error).font(.caption).foregroundStyle(.orange)
            }
            ZStack(alignment: .topLeading) {
                TextEditor(text: Binding(
                    get: { store.item(item.id)?.notes ?? "" },
                    set: { store.writeNotes($0, for: item.id) }
                ))
                .font(.body)
                .focused($focus, equals: .notes)
                .scrollContentBackground(.hidden)
                .accessibilityLabel("笔记")
                if item.notes.isEmpty {
                    Text("写下笔记…")
                        .font(.body)
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 5)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .padding(8)
            .frame(maxHeight: .infinity)
            .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 8))
            HStack(spacing: 7) {
                Image(systemName: "link").foregroundStyle(.secondary)
                TextField("关联链接（可选）", text: Binding(
                    get: { store.item(item.id)?.link ?? "" },
                    set: { store.writeLink($0, for: item.id) }
                ))
                .accessibilityLabel("关联链接")
                if let url = WorkLinks.external(item.link) {
                    Link(destination: url) { Image(systemName: "arrow.up.right") }
                        .accessibilityLabel("打开关联链接")
                        .help("打开关联链接")
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .disabled(!store.canEdit)
    }

    private var statusBar: some View {
        HStack(spacing: 8) {
            if let error = store.errorMessage {
                Text(error).foregroundStyle(.orange)
                Button("重试", action: store.retry).controlSize(.small)
            } else {
                Text(store.waitingToSave ? "正在保存…" : state.selection == nil ? "置顶项会显示在小组件" : "自动保存到本机")
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .font(.caption)
        .padding(.horizontal, 16)
        .frame(height: 30)
    }

    private func commitSearch() {
        state.commitKeyword(in: store)
        guard let id = store.openOrAdd(query), let item = store.item(id) else { return }
        state.query = ""
        open(item)
    }

    private func open(_ item: WorkItem) {
        state.commitKeyword(in: store)
        store.flush()
        state.select(item)
        state.requestFocus(.notes)
    }
}
