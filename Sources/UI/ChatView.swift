import SwiftUI

/// "AI 대장" tab: talk to your own Claude / Codex subscription without leaving HQ.
struct ChatView: View {
    @Environment(GameStore.self) private var store
    @State private var input = ""
    @FocusState private var focused: Bool
    private var chat: AIChat { AIChat.shared }

    private let quick = ["원정대 돌봐 줘", "지금 상황을 요약해 줘", "다음에 뭘 하면 좋을까?", "가방 정리해 줘"]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            messages
            if chat.messages.isEmpty { quickPrompts }
            inputBar
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14).fill(Theme.panel))
        .onAppear { if chat.available.isEmpty { chat.detect() } }
    }

    private var header: some View {
        HStack(spacing: 8) {
            PixelIcon(.robot, size: 20)
            Text("AI 대장과 대화").font(.system(size: 15, weight: .heavy, design: .rounded))
            ForEach(AIChat.Provider.allCases) { p in
                let ok = chat.available[p] == true
                Button {
                    chat.select(p)
                } label: {
                    HStack(spacing: 4) {
                        Circle().fill(ok ? Color(hex: 0x6BE36F) : Color.white.opacity(0.25)).frame(width: 6, height: 6)
                        Text(p.title)
                    }
                }
                .buttonStyle(GameButtonStyle(color: chat.provider == p ? Theme.accent : Theme.panelHi, compact: true))
                .disabled(!ok || chat.running)
                .help(ok ? "\(p.title) 구독으로 대화" : "\(p.title) CLI가 설치·로그인되어 있지 않아요")
            }
            Spacer()
            if chat.running {
                ProgressView().controlSize(.small)
                Button("멈춤") { chat.stop() }.buttonStyle(GameButtonStyle(color: Color(hex: 0xB0623B), compact: true))
            }
            Button("새 대화") { chat.newConversation() }
                .buttonStyle(GameButtonStyle(color: Theme.panelHi, compact: true))
                .disabled(chat.messages.isEmpty)
        }
    }

    private var messages: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    if chat.messages.isEmpty { intro }
                    ForEach(chat.messages) { m in bubble(m).id(m.id) }
                    if chat.running {
                        Text("생각하는 중…").font(.system(size: 11, design: .rounded)).foregroundStyle(Theme.dim).id("typing")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
            }
            .onChange(of: chat.messages.count) { _, _ in
                withAnimation {
                    if chat.running { proxy.scrollTo("typing", anchor: .bottom) }
                    else if let last = chat.messages.last?.id { proxy.scrollTo(last, anchor: .bottom) }
                }
            }
        }
        .frame(maxHeight: .infinity)
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("쓰고 계신 Claude·Codex 구독으로 바로 대화해요. 게임 상태를 보고 레벨업·장비·전술 같은 일을 대신 해 줄 수도 있어요.")
            if chat.detecting {
                Text("설치된 AI를 찾는 중…")
            } else if !chat.available.values.contains(true) {
                Text("Claude Code(`claude`)나 Codex(`codex`) CLI가 필요해요. 터미널에서 설치하고 한 번 로그인한 뒤 다시 열어 주세요.")
                    .foregroundStyle(Color(hex: 0xFF9C9C))
            }
        }
        .font(.system(size: 12, design: .rounded))
        .foregroundStyle(Theme.dim)
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder private func bubble(_ m: AIChat.Message) -> some View {
        switch m.role {
        case .user:
            HStack {
                Spacer(minLength: 80)
                Text(m.text).textSelection(.enabled)
                    .padding(.horizontal, 10).padding(.vertical, 7)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Theme.accent.opacity(0.85)))
            }
        case .assistant:
            HStack(alignment: .top, spacing: 6) {
                PixelIcon(.robot, size: 16).padding(.top, 4)
                Text(Self.markdown(m.text)).textSelection(.enabled)
                    .padding(.horizontal, 10).padding(.vertical, 7)
                    .background(RoundedRectangle(cornerRadius: 12).fill(Theme.panelHi))
                Spacer(minLength: 60)
            }
        case .tool:
            HStack(spacing: 4) {
                PixelIcon(.check, size: 10)
                Text(m.text)
            }
            .font(.system(size: 10, weight: .bold, design: .rounded))
            .foregroundStyle(Color(hex: 0x9CF4FF))
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(Capsule().fill(Color(hex: 0x1F3340)))
            .padding(.leading, 22)
        case .error:
            Text(m.text).font(.system(size: 11, design: .rounded)).foregroundStyle(Color(hex: 0xFF9C9C))
                .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
        case .note:
            Text(m.text).font(.system(size: 11, design: .rounded)).foregroundStyle(Theme.dim)
        }
    }

    private var quickPrompts: some View {
        HStack(spacing: 6) {
            ForEach(quick, id: \.self) { q in
                Button(LocalizedStringKey(q)) { chat.send(L10n.t(q)) }
                    .buttonStyle(GameButtonStyle(color: Theme.panelHi, compact: true))
                    .disabled(chat.running || chat.available[chat.provider] != true)
            }
        }
    }

    private var inputBar: some View {
        HStack(spacing: 8) {
            TextField(L10n.t("AI 대장에게 말하기… (Enter로 보내기)"), text: $input, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(1...4)
                .focused($focused)
                .padding(.horizontal, 10).padding(.vertical, 7)
                .background(RoundedRectangle(cornerRadius: 10).fill(Theme.bg))
                .onSubmit(send)
            Button("보내기", action: send)
                .buttonStyle(GameButtonStyle())
                .disabled(input.trimmingCharacters(in: .whitespaces).isEmpty || chat.running || chat.available[chat.provider] != true)
                .keyboardShortcut(.return, modifiers: [])
        }
    }

    private func send() {
        let t = input
        input = ""
        chat.send(t)
    }

    static func markdown(_ s: String) -> AttributedString {
        (try? AttributedString(markdown: s, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(s)
    }
}
