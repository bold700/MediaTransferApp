import SwiftUI

struct OnboardingView: View {
    let onFinish: () -> Void
    @State private var page = 0

    private struct Page {
        let symbol: String
        let title: LocalizedStringKey
        let body: LocalizedStringKey
    }

    private let pages: [Page] = [
        Page(symbol: "lock.shield.fill",
             title: "Your photos stay yours",
             body: "No cloud. No account. Nothing leaves your iPhone."),
        Page(symbol: "externaldrive.connected.to.line.below.fill",
             title: "Any USB-C drive works",
             body: "Connect a stick, SSD or hard drive. Back up in seconds."),
        Page(symbol: "checkmark.circle.fill",
             title: "Free up space, safely",
             body: "Copy first, then auto-delete from your phone if you want."),
    ]

    private let appBlue = Color(red: 0, green: 0.478, blue: 1.0)

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $page) {
                ForEach(pages.indices, id: \.self) { i in
                    pageView(pages[i])
                        .tag(i)
                }
            }
            .tabViewStyle(.page)
            .indexViewStyle(.page(backgroundDisplayMode: .always))

            Button(action: handlePrimary) {
                Text(page == pages.count - 1 ? "Get Started" : "Next")
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(appBlue)
                    .cornerRadius(10)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
        }
        .background(Color(uiColor: .systemBackground))
    }

    private func pageView(_ p: Page) -> some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: p.symbol)
                .resizable()
                .scaledToFit()
                .frame(width: 100, height: 100)
                .foregroundColor(appBlue)
            Text(p.title)
                .font(.largeTitle.bold())
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            Text(p.body)
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer()
        }
    }

    private func handlePrimary() {
        if page < pages.count - 1 {
            withAnimation { page += 1 }
        } else {
            onFinish()
        }
    }
}

#Preview {
    OnboardingView(onFinish: {})
}
