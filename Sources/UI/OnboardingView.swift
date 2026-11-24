import SwiftUI

/// 30-second first-run guide, shown over HQ once.
struct OnboardingView: View {
    @State private var page = 0
    let onDone: () -> Void

    private let pages: [(String, String, String)] = [
        ("shield.lefthalf.filled", "책상 위의 작은 원정대",
         "화면 아래 띠에서 단추·클립·몽당이 알아서 싸워요. 클릭 통과가 켜져 있어 작업을 방해하지 않고, 전체화면·화면 공유 중에는 숨어요. 앱을 꺼 둔 동안의 진행도 최대 12시간까지 정산돼요."),
        ("hand.tap", "쉬는 시간엔 한 번만",
         "띠 오른쪽에 마우스를 올리면 바로 조작할 수 있어요: 지역 이름 ▾로 지역 이동, 웨이브 보석으로 웨이브 선택, 영웅 칩으로 레벨업, ⚖️로 전술. ★가 뜨면 특성을 고를 차례예요. 장비는 자동 정리가 알아서 해요."),
        ("book.closed", "모으고, 남기고, 맡기고",
         "반짝이·왕관 몬스터와 희귀 손님을 도감에 모으고, 일지를 읽고, 트로피와 동행 펫을 늘려 보세요. 구독 중인 AI(Claude·Codex)를 메뉴바의 'AI 원정대장'에 연결하면 AI가 대신 돌봐 줘요."),
    ]

    var body: some View {
        let p = pages[page]
        VStack(spacing: 16) {
            Image(systemName: p.0).font(.system(size: 40, weight: .bold)).foregroundStyle(Theme.gold)
            Text(LocalizedStringKey(p.1)).font(.system(size: 22, weight: .heavy, design: .rounded))
            Text(LocalizedStringKey(p.2)).font(.system(size: 14, design: .rounded)).foregroundStyle(Theme.dim)
                .multilineTextAlignment(.center).frame(maxWidth: 460).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 6) {
                ForEach(pages.indices, id: \.self) { i in
                    Circle().fill(i == page ? Theme.gold : Color.white.opacity(0.2)).frame(width: 7, height: 7)
                }
            }
            HStack {
                if page > 0 { Button("이전") { page -= 1 }.buttonStyle(GameButtonStyle(color: Theme.panelHi)) }
                Button(page == pages.count - 1 ? "원정 시작!" : "다음") {
                    if page == pages.count - 1 { onDone() } else { page += 1 }
                }
                .buttonStyle(GameButtonStyle())
            }
        }
        .padding(32)
        .frame(width: 560)
        .background(RoundedRectangle(cornerRadius: 18).fill(Theme.bg))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Theme.gold.opacity(0.4)))
        .foregroundStyle(Theme.text)
    }

    static var needed: Bool { !UserDefaults.standard.bool(forKey: "onboarded") }
    static func finish() { UserDefaults.standard.set(true, forKey: "onboarded") }
}
