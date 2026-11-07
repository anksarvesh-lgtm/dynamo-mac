//
//  TeleprompterView.swift
//  LiquidDynamo
//
//  Webcam-aligned presentation prompter view rendered directly beneath the physical notch.
//  Merged from SuperIsland.
//

import SwiftUI

public struct TeleprompterView: View {
    @ObservedObject var prompter = TeleprompterService.shared
    @State private var isEditing: Bool = false

    public init() {}

    public var body: some View {
        VStack(spacing: 8) {
            // Header & Controls
            HStack(spacing: 8) {
                Image(systemName: "text.bubble.fill")
                    .foregroundColor(.cyan)
                    .font(.system(size: 12))

                Text("Notch Teleprompter")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundColor(.white)

                Spacer()

                // Mirror mode button
                Button {
                    prompter.isMirrored.toggle()
                } label: {
                    Image(systemName: prompter.isMirrored ? "arrow.left.and.right.righttriangle.left.righttriangle.right.fill" : "arrow.left.and.right")
                        .font(.system(size: 11))
                        .foregroundColor(prompter.isMirrored ? .cyan : .white.opacity(0.6))
                }
                .buttonStyle(.plain)
                .help("Mirror text horizontally")

                // Edit script toggle
                Button {
                    isEditing.toggle()
                } label: {
                    Image(systemName: isEditing ? "checkmark.circle.fill" : "pencil.circle")
                        .font(.system(size: 12))
                        .foregroundColor(isEditing ? .green : .white.opacity(0.7))
                }
                .buttonStyle(.plain)
                .help(isEditing ? "Finish editing" : "Edit presentation script")
            }
            .padding(.horizontal, 14)
            .padding(.top, 6)

            if isEditing {
                TextEditor(text: $prompter.scriptText)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.white)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .background(Color.black.opacity(0.5))
                    .cornerRadius(8)
                    .frame(height: 100)
                    .padding(.horizontal, 14)
            } else {
                // Prompter Viewport
                GeometryReader { geo in
                    ZStack(alignment: .top) {
                        Text(prompter.scriptText)
                            .font(.system(size: prompter.fontSize, weight: .medium, design: .rounded))
                            .foregroundColor(.white)
                            .lineSpacing(4)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                            .offset(y: -prompter.scrollOffset + 20)
                            .scaleEffect(x: prompter.isMirrored ? -1 : 1, y: 1)
                    }
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()
                }
                .frame(height: 90)
                .background(Color.black.opacity(0.45))
                .cornerRadius(8)
                .padding(.horizontal, 14)
            }

            // Playback and Speed bar
            HStack(spacing: 12) {
                Button {
                    prompter.resetScroll()
                } label: {
                    Image(systemName: "backward.end.fill")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.7))
                }
                .buttonStyle(.plain)

                Button {
                    prompter.toggleScrolling()
                } label: {
                    Image(systemName: prompter.isScrolling ? "pause.fill" : "play.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.white)
                        .padding(6)
                        .background(prompter.isScrolling ? Color.orange.opacity(0.8) : Color.cyan.opacity(0.8))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)

                HStack(spacing: 4) {
                    Text("Speed:")
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.6))
                    Text(String(format: "%.1fx", prompter.scrollSpeed))
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(.cyan)
                }

                Slider(value: $prompter.scrollSpeed, in: 0.5...3.0, step: 0.1)
                    .frame(width: 80)

                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 6)
        }
    }
}

