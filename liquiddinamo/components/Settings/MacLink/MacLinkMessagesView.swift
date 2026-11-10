//
//  MacLinkMessagesView.swift
//  LiquidDynamo
//
//  MacLink Messages Hub: Full SMS/RCS conversation threads, inline reply,
//  and rich media previews.
//

import AppKit
import SwiftUI

public struct MacLinkMessagesView: View {
    @ObservedObject private var bridge = MacLinkBridgeService.shared
    @State private var selectedContact: String = "Alex"
    @State private var messageInputText: String = ""

    public init() {}

    public var body: some View {
        HStack(spacing: 0) {
            // Left Pane: Conversation Threads List
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("Messages")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(Color.white)
                    Spacer()
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 14))
                        .foregroundStyle(Color.blue)
                }
                .padding(16)

                Divider().opacity(0.12)

                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 2) {
                        ForEach(bridge.recentMessages) { msg in
                            conversationRow(msg)
                        }
                    }
                    .padding(8)
                }
            }
            .frame(width: 260)
            .background(Color(white: 0.10).opacity(0.6))

            Divider().opacity(0.12)

            // Right Pane: Active Chat Conversation
            VStack(spacing: 0) {
                // Thread Top Header
                HStack(spacing: 12) {
                    Circle()
                        .fill(Color.blue.opacity(0.2))
                        .frame(width: 36, height: 36)
                        .overlay(
                            Text(String(selectedContact.prefix(1)))
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(Color.blue)
                        )

                    VStack(alignment: .leading, spacing: 2) {
                        Text(selectedContact)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Color.white)
                        Text("SMS / RCS via \(bridge.deviceName)")
                            .font(.system(size: 11, weight: .regular))
                            .foregroundStyle(Color.white.opacity(0.5))
                    }

                    Spacer()

                    Button {
                        bridge.simulateIncomingCall(callerName: selectedContact)
                    } label: {
                        Image(systemName: "phone.fill")
                            .font(.system(size: 13))
                            .foregroundStyle(Color.white.opacity(0.75))
                            .padding(8)
                            .background(Circle().fill(Color.white.opacity(0.08)))
                    }
                    .buttonStyle(.plain)
                }
                .padding(14)
                .background(Color(white: 0.11).opacity(0.8))

                Divider().opacity(0.12)

                // Message Bubbles ScrollView
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 12) {
                        ForEach(bridge.recentMessages.filter { $0.sender == selectedContact || $0.sender == "You" }) { msg in
                            messageBubble(msg)
                        }
                    }
                    .padding(16)
                }

                Divider().opacity(0.12)

                // Bottom Reply Bar
                HStack(spacing: 10) {
                    TextField("Text message via \(bridge.deviceName)…", text: $messageInputText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13.5))
                        .foregroundStyle(Color.white)
                        .onSubmit {
                            sendCurrentMessage()
                        }

                    Button {
                        sendCurrentMessage()
                    } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 22))
                            .foregroundStyle(messageInputText.isEmpty ? Color.white.opacity(0.2) : Color.blue)
                    }
                    .buttonStyle(.plain)
                    .disabled(messageInputText.isEmpty)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(Color(white: 0.10).opacity(0.8))
            }
        }
    }

    private func conversationRow(_ msg: PhoneMessageItem) -> some View {
        let isSelected = selectedContact == msg.sender
        return Button {
            selectedContact = msg.sender
        } label: {
            HStack(spacing: 10) {
                Circle()
                    .fill(Color.blue.opacity(0.2))
                    .frame(width: 34, height: 34)
                    .overlay(
                        Text(String(msg.sender.prefix(1)))
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Color.blue)
                    )

                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(msg.sender)
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(Color.white)
                        Spacer()
                        Text("Now")
                            .font(.system(size: 10))
                            .foregroundStyle(Color.white.opacity(0.4))
                    }

                    Text(msg.text)
                        .font(.system(size: 11))
                        .foregroundStyle(Color.white.opacity(0.6))
                        .lineLimit(1)
                }
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? Color.blue.opacity(0.22) : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }

    private func messageBubble(_ msg: PhoneMessageItem) -> some View {
        let isMe = msg.sender == "You"
        return HStack {
            if isMe { Spacer(minLength: 40) }

            VStack(alignment: isMe ? .trailing : .leading, spacing: 3) {
                Text(msg.text)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(isMe ? Color.blue : Color(white: 0.18))
                    )
            }

            if !isMe { Spacer(minLength: 40) }
        }
    }

    private func sendCurrentMessage() {
        let text = messageInputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        bridge.sendMessage(recipient: selectedContact, text: text)
        messageInputText = ""
    }
}

