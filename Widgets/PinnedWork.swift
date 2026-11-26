import SwiftUI
import WidgetKit

struct WorkEntry: TimelineEntry {
    let date: Date
    let items: [PinnedItem]
    var unavailable = false
}

struct PinnedProvider: TimelineProvider {
    func placeholder(in context: Context) -> WorkEntry {
        WorkEntry(date: .now, items: ["项目计划", "周报", "资料整理"].map {
            PinnedItem(id: UUID(), keyword: $0)
        })
    }

    func getSnapshot(in context: Context, completion: @escaping (WorkEntry) -> Void) {
        let actual = read()
        completion(context.isPreview && actual.items.isEmpty ? placeholder(in: context) : actual)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WorkEntry>) -> Void) {
        completion(Timeline(entries: [read()], policy: .after(Date().addingTimeInterval(30 * 60))))
    }

    private func read() -> WorkEntry {
        do {
            return WorkEntry(date: .now, items: try WorkFiles.local.loadPins())
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return WorkEntry(date: .now, items: [])
        } catch {
            return WorkEntry(date: .now, items: [], unavailable: true)
        }
    }
}

struct PinnedWorkView: View {
    let entry: WorkEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("置顶工作", systemImage: "pin.fill").font(.headline)
                Spacer(minLength: 0)
                Link(destination: WorkLinks.add) {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                        .accessibilityLabel("添加工作项")
                }
            }
            if entry.items.isEmpty {
                Spacer(minLength: 0)
                Text(entry.unavailable ? "暂时无法读取置顶项" : "还没有置顶项")
                    .font(.subheadline)
                Text(entry.unavailable ? "打开工作追踪查看" : "在工作追踪中点图钉")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(entry.items.prefix(family == .systemLarge ? 5 : 3)) { item in
                    Link(destination: WorkLinks.item(item.id)) {
                        Label(item.keyword, systemImage: "circle.fill")
                            .font(.subheadline)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 1)
        .widgetURL(WorkLinks.add)
        .containerBackground(.fill.tertiary, for: .widget)
    }
}

struct PinnedWorkWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WorkFiles.widgetKind, provider: PinnedProvider()) { entry in
            PinnedWorkView(entry: entry)
        }
        .configurationDisplayName("置顶工作")
        .description("查看置顶的工作关键词，点一下即可打开笔记。")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}
