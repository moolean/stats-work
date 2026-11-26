//
//  CombinedView.swift
//  Stats
//
//  Created by Serhiy Mytrovtsiy on 09/01/2023
//  Using Swift 5.0
//  Running on macOS 13.1
//
//  Copyright © 2023 Serhiy Mytrovtsiy. All rights reserved.
//

import Cocoa
import Kit

internal class CombinedView: NSObject, NSGestureRecognizerDelegate {
    static let panelWidth: CGFloat = 535

    private var menuBarItem: NSStatusItem? = nil
    private var view: NSView = NSView(frame: NSRect(x: 0, y: 0, width: 0, height: Constants.Widget.height))
    private var popup: PopupWindow? = nil
    var secondaryPopupPage: PopupPage?
    private var clickMonitor: Any? = nil
    private let summary: CombinedSummaryWidget = CombinedSummaryWidget()
    
    private var status: Bool {
        Store.shared.bool(key: "CombinedModules", defaultValue: false) && !Store.shared.bool(key: "pause", defaultValue: false)
    }
    private var spacing: CGFloat {
        CGFloat(Int(Store.shared.string(key: "CombinedModules_spacing", defaultValue: "")) ?? 0)
    }
    private var separator: Bool {
        Store.shared.bool(key: "CombinedModules_separator", defaultValue: false)
    }
    
    private var activeModules: [Module] {
        modules.filter({ $0.enabled }).sorted(by: { $0.combinedPosition < $1.combinedPosition })
    }
    
    private var combinedModulesPopup: Bool {
        get { Store.shared.bool(key: "CombinedModules_popup", defaultValue: true) }
        set { Store.shared.set(key: "CombinedModules_popup", value: newValue) }
    }
    private var combinedModulesAlternateDetails: Bool {
        get { Store.shared.bool(key: "CombinedModules_alternateDetails", defaultValue: true) }
        set { Store.shared.set(key: "CombinedModules_alternateDetails", value: newValue) }
    }
    private var combinedModulesModifierKeys: [UInt16] {
        get { Store.shared.array(key: "CombinedModules_modifierKeys", defaultValue: [58]) as? [UInt16] ?? [58] }
        set { Store.shared.set(key: "CombinedModules_modifierKeys", value: newValue) }
    }
    
    override init() {
        super.init()
        
        modules.forEach { (m: Module) in
            m.menuBar.callback = { [weak self] in
                if let s = self?.status, s {
                    DispatchQueue.main.async(execute: {
                        self?.recalculate()
                    })
                }
            }
            m.summaryCallback = { [weak self] module, value in
                guard let self else { return }
                self.summary.setValue(for: module, with: value)
                guard self.status, CombinedModulesWidget.current.isSummaryWidget else { return }
                self.updateSummary()
            }
        }
        
        if self.status {
            self.enable()
        }
        
        self.clickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown]) { [weak self] event in
            guard let self else { return event }
            return self.handleAlternateClick(event)
        }
        
        NotificationCenter.default.addObserver(self, selector: #selector(self.listenForStateChange), name: .toggleOneView, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(self.listenForStateChange), name: .pause, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(self.listenForModuleRearrrange), name: .moduleRearrange, object: nil)
    }
    
    deinit {
        if let monitor = self.clickMonitor {
            NSEvent.removeMonitor(monitor)
        }
        NotificationCenter.default.removeObserver(self, name: .toggleOneView, object: nil)
        NotificationCenter.default.removeObserver(self, name: .pause, object: nil)
        NotificationCenter.default.removeObserver(self, name: .moduleRearrange, object: nil)
    }
    
    public func enable() {
        guard self.menuBarItem == nil else { return }
        
        self.menuBarItem = NSStatusBar.system.statusItem(withLength: 0)
        DispatchQueue.main.async(execute: {
            self.menuBarItem?.autosaveName = "CombinedModules"
        })
        if let button = self.menuBarItem?.button {
            self.view.frame = button.bounds
            self.view.autoresizingMask = [.height]
            button.addSubview(self.view)
        }
        self.menuBarItem?.button?.image = NSImage()
        self.menuBarItem?.button?.toolTip = localizedString("Combined modules")
        
        self.menuBarItem?.button?.target = self
        self.menuBarItem?.button?.action = #selector(self.handleClick)
        self.menuBarItem?.button?.sendAction(on: [.leftMouseDown, .rightMouseDown])
        
        DispatchQueue.main.async(execute: {
            self.recalculate()
        })
    }
    
    public func disable() {
        self.popup?.setIsVisible(false)
        if let item = self.menuBarItem {
            NSStatusBar.system.removeStatusItem(item)
        }
        self.menuBarItem = nil
    }
    
    private func recalculate() {
        guard self.status, self.menuBarItem != nil else { return }
        self.view.subviews.forEach({ $0.removeFromSuperview() })
        self.menuBarItem?.button?.toolTip = localizedString("Combined modules")
        self.menuBarItem?.button?.setAccessibilityLabel(localizedString("Combined modules"))
        
        if CombinedModulesWidget.current.isSummaryWidget {
            self.updateSummary()
            return
        }
        
        if CombinedModulesWidget.current == .icon {
            self.showAppIcon()
            return
        }
        
        let visibleModules = self.activeModules.filter({ !$0.menuBar.activeWidgets.isEmpty })
        var w: CGFloat = 0
        visibleModules.enumerated().forEach { (i, m) in
            if i != 0 {
                w += self.spacing
                if self.separator {
                    self.view.addSubview(SeparatorLineView(frame: NSRect(x: w, y: 3, width: 1, height: Constants.Widget.height-6)))
                    w += 3 + self.spacing
                }
            }
            self.view.addSubview(m.menuBar.view)
            m.menuBar.view.setFrameOrigin(NSPoint(x: w, y: 0))
            w += m.menuBar.view.frame.width
        }
        self.resizeStatusContent(toWidth: w)
    }

    private func resizeStatusContent(toWidth width: CGFloat) {
        guard let item = self.menuBarItem else { return }
        item.length = width
        let height = item.button?.bounds.height ?? self.view.frame.height
        self.view.frame = NSRect(x: 0, y: 0, width: width, height: height)
    }

    private func showAppIcon() {
        self.resizeStatusContent(toWidth: AppIcon.size.width)
        let icon = AppIcon()
        icon.setFrameOrigin(NSPoint(x: 0, y: (self.view.bounds.height - icon.frame.height) / 2))
        icon.autoresizingMask = [.minYMargin, .maxYMargin]
        self.view.addSubview(icon)
    }
    
    private func updateSummary() {
        guard self.menuBarItem != nil else { return }
        let list = self.activeModules.filter({ $0.config.hasSummary })
        
        if list.isEmpty {
            self.view.subviews.forEach({ $0.removeFromSuperview() })
            self.showAppIcon()
            self.menuBarItem?.button?.toolTip = localizedString("Combined modules")
            self.menuBarItem?.button?.setAccessibilityLabel(localizedString("Combined modules"))
            return
        }
        
        if self.summary.superview == nil {
            self.view.subviews.forEach({ $0.removeFromSuperview() })
            self.summary.autoresizingMask = [.width, .height]
            self.view.addSubview(self.summary)
        }

        self.resizeStatusContent(toWidth: self.summary.update(list))
        self.summary.frame = self.view.bounds
        
        self.menuBarItem?.button?.toolTip = self.summary.toolTip
        self.menuBarItem?.button?.setAccessibilityLabel(self.summary.toolTip)
    }
    
    @objc private func handleClick() {
        if CombinedModulesWidget.current != .widgets || self.combinedModulesPopup {
            self.togglePopup()
        } else {
            self.openModulePopup()
        }
    }
    
    private func handleAlternateClick(_ event: NSEvent) -> NSEvent? {
        guard let window = self.menuBarItem?.button?.window, event.window == window,
              CombinedModulesWidget.current == .widgets, self.combinedModulesAlternateDetails else { return event }
        
        let flags = CGEventSource.flagsState(.combinedSessionState)
        guard flags.isDisjoint(with: [.maskControl, .maskCommand]) else { return event }
        
        let keys = self.combinedModulesModifierKeys
        let matches = !keys.isEmpty && keys.allSatisfy { key in
            switch key {
            case 60: return flags.contains(.maskShift)
            case 58: return flags.contains(.maskAlternate)
            default: return false
            }
        }
        guard matches else { return event }
        
        if self.combinedModulesPopup {
            self.openModulePopup()
        } else {
            self.togglePopup()
        }
        return nil
    }
    
    private func openModulePopup() {
        guard let window = self.menuBarItem?.button?.window else { return }
        let location = self.view.convert(window.convertPoint(fromScreen: NSEvent.mouseLocation), from: nil)
        let visibleModules = self.activeModules.filter({ !$0.menuBar.activeWidgets.isEmpty })
        guard let module = visibleModules.last(where: { $0.menuBar.view.frame.minX <= location.x }) ?? visibleModules.first else { return }
        
        var userInfo: [String: Any] = [
            "module": module.name,
            "origin": window.frame.origin,
            "center": window.frame.width/2
        ]
        let widgetLocation = module.menuBar.view.convert(location, from: self.view)
        let widgets = module.menuBar.activeWidgets
        if let widget = widgets.last(where: { $0.item.frame.minX <= widgetLocation.x }) ?? widgets.first {
            userInfo["widget"] = widget.type
        }
        NotificationCenter.default.post(name: .togglePopup, object: nil, userInfo: userInfo)
    }
    
    private func togglePopup() {
        guard let item = self.menuBarItem, let window = item.button?.window else { return }
        
        if self.popup == nil {
            self.popup = PopupWindow(title: "Combined modules", module: .combined, view: Popup(),
                                     page: self.secondaryPopupPage) { _ in }
        }
        guard let popup = self.popup else { return }
        
        if popup.occlusionState.rawValue == 8192 {
            popup.contentView?.invalidateIntrinsicContentSize()
            
            let windowCenter = popup.contentView!.intrinsicContentSize.width / 2
            var x = window.frame.origin.x - windowCenter + window.frame.width/2
            let y = window.frame.origin.y - popup.contentView!.intrinsicContentSize.height - 3
            
            let buttonPoint = NSPoint(x: window.frame.midX, y: window.frame.midY)
            if let screen = NSScreen.screens.first(where: { $0.frame.contains(buttonPoint) }) ?? NSScreen.main {
                if x + popup.contentView!.intrinsicContentSize.width > screen.frame.maxX {
                    x = screen.frame.maxX - popup.contentView!.intrinsicContentSize.width - 3
                }
                if x < screen.frame.minX {
                    x = screen.frame.minX + 3
                }
            }
            
            popup.setFrameOrigin(NSPoint(x: x, y: y))
            popup.orderFrontRegardless()
            popup.makeKey()
        } else {
            popup.setIsVisible(false)
        }
    }
    
    @objc private func listenForStateChange(_ notification: Notification) {
        guard notification.userInfo?["module"] == nil else { return }
        
        if self.status {
            self.enable()
        } else {
            self.disable()
        }
    }
    
    @objc private func listenForModuleRearrrange() {
        self.recalculate()
    }
}

private class CombinedSummaryWidget: NSView {
    private var values: [(ModuleType, Double?)] = []
    
    private var color: NSColor { self.isDarkMode ? .white : .black }
    
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        
        switch CombinedModulesWidget.current {
        case .rings: self.drawRings()
        case .dial: self.drawDial()
        default: self.drawBars()
        }
    }
    
    private func color(for value: Double?, moduleType: ModuleType) -> NSColor {
        guard let value else { return self.color }
        return (moduleType == .battery ? value < 0.1 : value > 0.9) ? .systemRed : self.color
    }
    
    private func drawBars() {
        let height: CGFloat = min(16, self.bounds.height - 4)
        let width = CGFloat(self.values.count) * 6 - 2
        let origin = ((self.bounds.width - width) / 2).rounded()
        let y = ((self.bounds.height - height) / 2).rounded()
        
        for (i, (module, value)) in self.values.enumerated() {
            let color = self.color(for: value, moduleType: module)
            let rect = NSRect(x: origin + CGFloat(i) * 6, y: y, width: 4, height: height)
            let track = NSBezierPath(roundedRect: rect, xRadius: 1, yRadius: 1)
            color.withAlphaComponent(0.25).setFill()
            track.fill()
            
            if let value, value > 0 {
                let fill = NSRect(x: rect.minX, y: rect.minY, width: rect.width, height: height * CGFloat(value))
                NSGraphicsContext.saveGraphicsState()
                track.addClip()
                color.setFill()
                NSBezierPath(rect: fill).fill()
                NSGraphicsContext.restoreGraphicsState()
            }
        }
    }
    
    private func drawRings() {
        guard !self.values.isEmpty else { return }
        let diameter = min(20, self.bounds.height - 2)
        let spacing = min(3, diameter / (CGFloat(self.values.count) * 2))
        let lineWidth = spacing - 0.5
        let center = NSPoint(x: self.bounds.midX, y: self.bounds.midY)
        
        for (i, (module, value)) in self.values.enumerated() {
            let color = self.color(for: value, moduleType: module)
            let radius = (diameter - lineWidth) / 2 - CGFloat(i) * spacing
            let track = NSBezierPath(ovalIn: NSRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
            track.lineWidth = lineWidth
            color.withAlphaComponent(0.25).setStroke()
            track.stroke()
            
            if let value, value > 0 {
                color.setStroke()
                if value == 1 {
                    track.stroke()
                } else {
                    let fill = NSBezierPath()
                    fill.lineWidth = lineWidth
                    fill.lineCapStyle = .round
                    fill.appendArc(withCenter: center, radius: radius, startAngle: 90, endAngle: 90 - CGFloat(value) * 360, clockwise: true)
                    fill.stroke()
                }
            }
        }
    }
    
    private func drawDial() {
        guard !self.values.isEmpty else { return }
        let lineWidth: CGFloat = 2.5
        let radius = (min(20, self.bounds.height - 2) - lineWidth) / 2
        let center = NSPoint(x: self.bounds.midX, y: self.bounds.midY)
        let segment = 360 / CGFloat(self.values.count)
        let gap: CGFloat = self.values.count > 1 ? 32 : 0
        
        for (i, (module, value)) in self.values.enumerated() {
            let color = self.color(for: value, moduleType: module)
            let start = 90 - CGFloat(i) * segment - gap / 2
            let length = segment - gap
            let track = NSBezierPath()
            track.lineWidth = lineWidth
            track.lineCapStyle = .round
            track.appendArc(withCenter: center, radius: radius, startAngle: start, endAngle: start - length, clockwise: true)
            color.withAlphaComponent(0.25).setStroke()
            track.stroke()
            
            if let value, value > 0 {
                let fill = NSBezierPath()
                fill.lineWidth = lineWidth
                fill.lineCapStyle = .round
                fill.appendArc(withCenter: center, radius: radius, startAngle: start, endAngle: start - length * CGFloat(value), clockwise: true)
                color.setStroke()
                fill.stroke()
            }
        }
    }
    
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        self.needsDisplay = true
    }
    
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    
    fileprivate func setValue(for module: ModuleType, with value: Double?) {
        let value = value.flatMap({ $0.isFinite ? min(max($0, 0), 1) : nil })
        if let index = self.values.firstIndex(where: { $0.0 == module }) {
            self.values[index].1 = value
        } else {
            self.values.append((module, value))
        }
    }
    
    fileprivate func update(_ list: [Module]) -> CGFloat {
        self.values = list.map { module in
            (module.moduleType, self.values.first(where: { $0.0 == module.moduleType })?.1)
        }
        let width: CGFloat = CombinedModulesWidget.current == .bars ? max(22, CGFloat(self.values.count) * 6 + 2) : 22
        self.toolTip = list.map { module in
            let value = self.values.first(where: { $0.0 == module.moduleType })?.1.map({ "\(Int($0 * 100))%" }) ?? localizedString("Unknown")
            return "\(localizedString(module.name)): \(value)"
        }.joined(separator: "\n")
        self.needsDisplay = true
        return width
    }
}

private class SeparatorLineView: NSView {
    override var wantsUpdateLayer: Bool { true }
    
    override init(frame: NSRect) {
        super.init(frame: frame)
        self.wantsLayer = true
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func updateLayer() {
        self.layer?.backgroundColor = (self.isDarkMode ? NSColor.white : NSColor.black).cgColor
    }
    
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        self.needsDisplay = true
    }
}

private class Popup: NSStackView, Popup_p {
    fileprivate var keyboardShortcut: [UInt16] = []
    fileprivate var sizeCallback: ((NSSize) -> Void)? = nil
    private let processTable = ProcessesView(values: [("占用", nil)], showPID: true, allowsTermination: false)
    private let overview = NSStackView()
    private let processHeader = NSStackView()
    private lazy var processTabs = NSSegmentedControl(labels: ["CPU", "内存"], trackingMode: .selectOne,
                                                      target: self, action: #selector(self.updateProcessSelection))
    private lazy var processTableHeight = self.processTable.heightAnchor.constraint(equalToConstant: 24)
    private lazy var overviewHeight = self.overview.heightAnchor.constraint(equalToConstant: 0)
    private var processModules: [Module?] = [nil, nil]
    private var portalHeight: CGFloat = 0
    private var observedModule: Module?
    private var monitoringVisible = false
    
    init() {
        self.keyboardShortcut = Store.shared.array(key: "CombinedModules_popup_keyboardShortcut", defaultValue: []) as? [UInt16] ?? []
        
        super.init(frame: NSRect(x: 0, y: 0, width: CombinedView.panelWidth, height: 0))
        
        self.orientation = .vertical
        self.distribution = .fill
        self.alignment = .width
        self.spacing = 10
        self.edgeInsets = NSEdgeInsets(top: 6, left: 8, bottom: 8, right: 8)

        self.overview.orientation = .horizontal
        self.overview.distribution = .fillEqually
        self.overview.alignment = .height
        self.overview.spacing = 10
        self.overviewHeight.isActive = true
        
        let title = NSTextField(labelWithString: "进程")
        title.font = .systemFont(ofSize: 13, weight: .semibold)
        title.setContentHuggingPriority(.required, for: .horizontal)
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        self.processHeader.orientation = .horizontal
        self.processHeader.alignment = .centerY
        self.processHeader.distribution = .fill
        self.processHeader.addArrangedSubview(title)
        self.processHeader.addArrangedSubview(spacer)
        self.processHeader.addArrangedSubview(self.processTabs)
        self.processTabs.setContentHuggingPriority(.required, for: .horizontal)
        self.processHeader.heightAnchor.constraint(equalToConstant: 30).isActive = true

        self.processTable.alignment = .width
        self.processTable.setContentHuggingPriority(.defaultLow, for: .horizontal)
        self.processTableHeight.isActive = true
        self.processTabs.selectedSegment = 0
        self.reinit()
        
        NotificationCenter.default.addObserver(self, selector: #selector(self.reinit), name: .toggleModule, object: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self, name: .toggleModule, object: nil)
        self.observedModule?.observeTopProcesses(nil)
    }
    
    fileprivate func settings() -> NSView? { return nil }
    fileprivate func appear() {
        self.monitoringVisible = true
        self.updateProcessSelection()
    }
    fileprivate func disappear() {
        self.monitoringVisible = false
        self.observedModule?.observeTopProcesses(nil)
        self.observedModule = nil
    }
    fileprivate func setKeyboardShortcut(_ binding: [UInt16]) {
        self.keyboardShortcut = binding
        Store.shared.set(key: "CombinedModules_popup_keyboardShortcut", value: binding)
    }
    
    @objc private func reinit() {
        self.arrangedSubviews.forEach { $0.removeFromSuperview() }
        self.overview.arrangedSubviews.forEach { $0.removeFromSuperview() }
        
        let availableModules = modules.filter({ $0.enabled && $0.portal != nil })
        let summaryPortals = [ModuleType.CPU, .RAM].compactMap { type in
            availableModules.first { $0.moduleType == type }?.portal
        }
        let otherPortals = availableModules.filter { $0.moduleType != .CPU && $0.moduleType != .RAM }.compactMap(\.portal)
        self.portalHeight = 0
        if let tallest = summaryPortals.map(\.height).max() {
            self.overviewHeight.constant = tallest + 20
            summaryPortals.forEach { self.overview.addArrangedSubview(self.overviewCard($0)) }
            self.portalHeight += self.overviewHeight.constant
            self.addFullWidthSection(self.overview)
        }
        for portal in otherPortals {
            self.portalHeight += portal.height
            self.addFullWidthSection(portal)
        }

        self.processModules = [.CPU, .RAM].map { type in
            availableModules.first { $0.moduleType == type && $0.topProcessesReader != nil }
        }
        self.addFullWidthSection(self.processHeader)
        self.addFullWidthSection(self.processTable)
        let available = self.processModules.indices.filter { self.processModules[$0] != nil }
        self.processHeader.isHidden = available.isEmpty
        self.processModules.indices.forEach { self.processTabs.setEnabled(self.processModules[$0] != nil, forSegment: $0) }
        if !available.contains(self.processTabs.selectedSegment) {
            self.processTabs.selectedSegment = available.first ?? -1
        }
        self.updateProcessSelection()
    }

    private func addFullWidthSection(_ section: NSView) {
        self.addArrangedSubview(section)
        section.widthAnchor.constraint(equalTo: self.widthAnchor,
                                       constant: -(self.edgeInsets.left + self.edgeInsets.right)).isActive = true
    }

    private func overviewCard(_ portal: Portal_p) -> NSBox {
        let card = NSBox()
        card.boxType = .custom
        card.titlePosition = .noTitle
        card.cornerRadius = 9
        card.borderWidth = 1
        card.borderColor = .separatorColor
        card.fillColor = NSColor.labelColor.withAlphaComponent(0.025)
        card.contentViewMargins = .zero

        let content = NSView()
        card.contentView = content
        portal.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(portal)
        NSLayoutConstraint.activate([
            portal.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 10),
            portal.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -10),
            portal.topAnchor.constraint(equalTo: content.topAnchor, constant: 10)
        ])
        return card
    }

    @objc private func updateProcessSelection() {
        let index = self.processTabs.selectedSegment
        let module = self.processModules.indices.contains(index) ? self.processModules[index] : nil
        let count = module.map { max(0, Store.shared.int(key: "\($0.name)_processes", defaultValue: 8)) } ?? 0
        self.processTable.setNumberOfProcesses(count)
        self.processTableHeight.constant = 24 + 28 * CGFloat(count)
        self.processTable.isHidden = count == 0

        let next = self.monitoringVisible && count > 0 ? module : nil
        if self.observedModule !== next {
            self.observedModule?.observeTopProcesses(nil)
            self.observedModule = next
            self.processTable.clear()
            if let next {
                let isCPU = next.moduleType == .CPU
                next.observeTopProcesses { [weak self] processes in
                    self?.drawProcesses(processes, cpu: isCPU)
                }
            }
        }

        let spacing = CGFloat(max(0, self.arrangedSubviews.filter { !$0.isHidden }.count - 1)) * self.spacing
        let headerHeight: CGFloat = self.processHeader.isHidden ? 0 : 30
        let tableHeight = self.processTable.isHidden ? 0 : self.processTableHeight.constant
        let height = self.portalHeight + headerHeight + tableHeight + spacing + self.edgeInsets.top + self.edgeInsets.bottom
        if height != self.frame.height {
            self.setFrameSize(NSSize(width: self.frame.width, height: height))
            self.sizeCallback?(self.frame.size)
        }
    }

    private func drawProcesses(_ processes: [TopProcess], cpu: Bool) {
        for index in 0..<self.processTable.count {
            guard processes.indices.contains(index) else {
                self.processTable.set(index, nil, [])
                continue
            }
            let process = processes[index]
            let value = cpu ? "\(process.usage)%" : Units(bytes: Int64(process.usage)).getReadableMemory(style: .memory)
            self.processTable.set(index, process, [value])
        }
    }
}
