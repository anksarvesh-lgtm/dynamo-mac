//
//  ShelfView.swift
//  LiquidDynamo
//
//  Compact liquid dropper shelf with organic droplet styling and ideal sizing.
//

import AppKit
import SwiftUI

struct ShelfView: View {
    @EnvironmentObject var vm: LiquidViewModel
    @StateObject var tvm = ShelfStateViewModel.shared
    @StateObject var selection = ShelfSelectionModel.shared
    @StateObject private var quickLookService = QuickLookService()
    private let spacing: CGFloat = 8

    var body: some View {
        panel
            .onDrop(of: [.fileURL, .url, .utf8PlainText, .plainText, .data], isTargeted: $vm.dragDetectorTargeting) { providers in
                handleDrop(providers: providers)
            }
            .onChange(of: selection.selectedIDs) {
                updateQuickLookSelection()
            }
            .quickLookPresenter(using: quickLookService)
    }

    private func handleDrop(providers: [NSItemProvider]) -> Bool {
        guard !selection.isDragging else { return false }
        vm.dropEvent = true
        ShelfStateViewModel.shared.load(providers)
        return true
    }

    private func updateQuickLookSelection() {
        guard quickLookService.isQuickLookOpen && !selection.selectedIDs.isEmpty else { return }

        let selectedItems = selection.selectedItems(in: tvm.items)
        let urls: [URL] = selectedItems.compactMap { item in
            if let fileURL = item.fileURL {
                return fileURL
            }
            if case .link(let url) = item.kind {
                return url
            }
            return nil
        }

        if !urls.isEmpty {
            quickLookService.updateSelection(urls: urls)
        }
    }

    var panel: some View {
        VStack(spacing: 6) {
            // Header Bar
            HStack(spacing: 6) {
                Image(systemName: "tray.and.arrow.down.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(Color.cyan)
                Text("Dropper")
                    .font(.system(size: 11.5, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)

                if !tvm.isEmpty {
                    Text("\(tvm.items.count)")
                        .font(.system(size: 9.5, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.cyan)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1.5)
                        .background(Capsule().fill(Color.cyan.opacity(0.18)))

                    Spacer()

                    Button {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            tvm.clearAll()
                        }
                    } label: {
                        HStack(spacing: 3) {
                            Image(systemName: "trash")
                                .font(.system(size: 9))
                            Text("Clear")
                                .font(.system(size: 9.5, weight: .semibold))
                        }
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Color.white.opacity(0.08)))
                    }
                    .buttonStyle(.plain)
                } else {
                    Spacer()
                }
            }
            .padding(.horizontal, 10)
            .padding(.top, 4)

            // Content Area
            Group {
                if tvm.isEmpty {
                    VStack(spacing: 5) {
                        Image(systemName: "tray.and.arrow.down")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(vm.dragDetectorTargeting ? Color.orange : Color.white.opacity(0.45))
                            .scaleEffect(vm.dragDetectorTargeting ? 1.15 : 1.0)
                            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: vm.dragDetectorTargeting)

                        Text("Dropper Empty")
                            .font(.system(size: 11.5, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white.opacity(0.85))

                        Text("Drop files here to hold temporarily")
                            .font(.system(size: 9.5, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .padding(.vertical, 4)
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: spacing) {
                            ForEach(tvm.items) { item in
                                ShelfItemView(item: item)
                                    .environmentObject(quickLookService)
                            }
                        }
                        .padding(.horizontal, 6)
                    }
                    .frame(maxHeight: .infinity)
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(
                        vm.dragDetectorTargeting ? Color.cyan.opacity(0.9) : Color.white.opacity(0.12),
                        style: StrokeStyle(lineWidth: vm.dragDetectorTargeting ? 2 : 1, lineCap: .round, dash: [6, 4])
                    )
                    .background(Color.white.opacity(vm.dragDetectorTargeting ? 0.08 : 0.03))
            )
            .padding(.horizontal, 6)
            .padding(.bottom, 6)
        }
        .frame(width: 410, height: 105)
        .contentShape(Rectangle())
        .onTapGesture { selection.clear() }
        .onAppear {
            ShelfStateViewModel.shared.cleanupInvalidItems()
        }
    }
}
