import SwiftUI
import AppKit

struct RefreshShareSheet: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var sharing: RefreshShareController
    @State private var destination: RefreshSocialDestination?
    @State private var editing = false
    @State private var draft = ""
    @State private var message: String?
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(sharing.isTotal ? settings.t("累計の記録をシェア", "Share your total record") : settings.t("今日の記録をシェア", "Share today’s record"))
                    .font(.system(size: 18, weight: .medium))
                if let image = sharing.image { Image(nsImage: image).frame(width: 362, height: 187) }
                else { RefreshLoadingPlaceholder(japanese: settings.isJapanese) }
                HStack {
                    Text("GitHub URL").font(.system(size: 12)).foregroundStyle(.secondary)
                    Spacer()
                    Button(settings.t("変更", "Edit")) { draft = settings.publicShareURL; editing.toggle() }
                }
                if editing {
                    TextField("https://github.com/owner/repository", text: $draft).textFieldStyle(.roundedBorder)
                        .accessibilityLabel(settings.t("共有するGitHub URL", "GitHub URL to share"))
                    if RefreshExternalLinks.githubURL(draft) == nil {
                        Text(settings.t("GitHubのリポジトリURLを入力してください。", "Enter an HTTPS GitHub repository URL."))
                            .font(.system(size: 12)).foregroundStyle(.red)
                    }
                    HStack {
                        Button(settings.t("保存", "Save")) {
                            guard let url = RefreshExternalLinks.githubURL(draft) else { return }
                            settings.publicShareURL = url.absoluteString; editing = false
                        }.disabled(RefreshExternalLinks.githubURL(draft) == nil)
                        Button("Cancel") { editing = false }
                    }
                } else {
                    Text(settings.publicShareURL).font(.system(size: 12)).textSelection(.enabled).lineLimit(2)
                    if settings.isDemoShareURL {
                        Text(settings.t("デモURLです。公開後に変更してください。", "Demo URL. Replace it after publishing."))
                            .font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                }
                HStack {
                    ForEach(RefreshSocialDestination.allCases) { item in
                        Button { destination = item } label: { Text(item.title).frame(maxWidth: .infinity) }
                            .disabled(sharing.isPreparing || settings.shareURL == nil)
                    }
                }.buttonStyle(.bordered)
                if let destination {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(settings.t("\(destination.title)に投稿", "Post on \(destination.title)"))
                            .font(.system(size: 14, weight: .medium))
                        Text(destination == .x
                             ? settings.t("画像を保存し、Xの投稿画面で添付してください。GitHub URLは投稿欄に入ります。", "Save the image, then attach it in X. The GitHub URL is filled in for you.")
                             : settings.t("画像を保存し、Instagramで選んでください。GitHub URLはコピーして投稿文に貼り付けられます。", "Save the image and select it in Instagram. Copy the GitHub URL to paste into your caption."))
                            .font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
                        HStack {
                            Button(settings.t("画像を保存…", "Save image…")) { sharing.save() }
                            Button(settings.t("URLをコピー", "Copy URL")) { copyURL() }
                            Button(settings.t("\(destination.title)を開く", "Open \(destination.title)")) { open(destination) }
                        }.font(.system(size: 12))
                        Text(settings.t("画像は自動添付されません。投稿はご自身で確認して行ってください。", "The image isn't attached automatically. Review and publish the post yourself."))
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                    }.padding(12).background(Color(white: 0.96)).clipShape(RoundedRectangle(cornerRadius: 8))
                }
                HStack {
                    Button(settings.t("その他…", "More…")) { sharing.share(githubURL: settings.shareURL) }.disabled(sharing.isPreparing || settings.shareURL == nil)
                    Button(settings.t("画像をコピー", "Copy image")) { sharing.copyImage() }.disabled(sharing.isPreparing)
                    Button(settings.t("画像を保存…", "Save image…")) { sharing.save() }.disabled(sharing.isPreparing)
                    Spacer()
                    Button("Done") { sharing.cancel() }.keyboardShortcut(.defaultAction)
                }.font(.system(size: 12))
            }.padding(24)
        }.frame(width: 410, height: destination == nil ? (editing ? 520 : 440) : (editing ? 670 : 620))
            .background(Color.white).foregroundStyle(.black)
            .onAppear {
                guard Bundle.main.bundleIdentifier == "local.thinkandmove.ui-preview.v27", CommandLine.arguments.contains(where: { $0.hasPrefix("--ui-fixture=") }) else { return }
                if CommandLine.arguments.contains("--review-sheet=share-x") { destination = .x }
                if CommandLine.arguments.contains("--review-sheet=share-instagram") { destination = .instagram }
                if CommandLine.arguments.contains("--review-sheet=share-edit") { draft = settings.publicShareURL; editing = true }
            }
            .alert("Squat", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
                Button("OK") { message = nil }
            } message: { Text(message ?? "") }
    }
    private func copyURL() {
        guard let url = settings.shareURL else { return }
        NSPasteboard.general.clearContents(); NSPasteboard.general.setString(url.absoluteString, forType: .string)
    }
    private func open(_ destination: RefreshSocialDestination) {
        guard let github = settings.shareURL else { return }
        if !NSWorkspace.shared.open(destination.composeURL(github: github)) {
            message = settings.t("ブラウザを開けませんでした。", "Could not open your browser.")
        }
    }
}
