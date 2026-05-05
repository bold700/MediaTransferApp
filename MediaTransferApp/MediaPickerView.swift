import SwiftUI
import Photos
import UIKit

private let appBlue = Color(red: 0, green: 0.478, blue: 1.0)

struct MediaPickerView: View {
    @StateObject private var library = PhotoLibrary()
    @StateObject private var transfer = TransferController()
    @StateObject private var appState = AppState()

    @State private var showSettings = false
    @State private var showDirectoryPicker = false
    @State private var showPhotoPermissionAlert = false
    @State private var deleteAfter = false
    @State private var resultAlert: ResultAlert?
    @State private var showError = false
    @State private var errorMessage = ""

    private struct ResultAlert: Identifiable {
        let id = UUID()
        let title: String
        let message: String
        let resetSelection: Bool
    }

    var body: some View {
        Group {
            if library.isAuthorized {
                authorizedView
            } else {
                permissionGate
            }
        }
        .task {
            if library.authStatus == .notDetermined {
                await library.requestAuthorization()
            } else if library.isAuthorized {
                library.reload()
            }
        }
        .sheet(isPresented: $showSettings) { SettingsView() }
        .fileImporter(
            isPresented: $showDirectoryPicker,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first { appState.selectedDirectory = url }
            case .failure(let error):
                errorMessage = error.localizedDescription
                showError = true
            }
        }
        .alert("Error", isPresented: $showError) {
            Button("OK", role: .cancel) { }
        } message: { Text(errorMessage) }
        .alert("Photo access required", isPresented: $showPhotoPermissionAlert) {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("To select media, please allow Photo access in Settings.")
        }
        .alert(item: $resultAlert) { alert in
            Alert(
                title: Text(alert.title),
                message: Text(alert.message),
                dismissButton: .default(Text("OK")) {
                    if alert.resetSelection { library.clearSelection() }
                }
            )
        }
    }

    // MARK: - Authorized layout (NavigationStack + system toolbar = automatic Liquid Glass)
    private var authorizedView: some View {
        NavigationStack {
            MediaGridView(library: library, transferring: transfer.isTransferring)
                .ignoresSafeArea()
                .modifier(ScrollEdgeEffectModifier())
                .safeAreaInset(edge: .top, spacing: 0) {
                    filterBar
                }
                .navigationTitle("Select Media")
                .modifier(NavSubtitleModifier(text: countLabel))
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            showSettings = true
                        } label: {
                            Image(systemName: "gearshape")
                        }
                        .accessibilityLabel("Settings")
                    }
                }
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    bottomBar
                }
        }
    }

    // MARK: - Filter bar
    @ViewBuilder
    private var filterBar: some View {
        if #available(iOS 26.0, *) {
            GlassFilterCapsule(filter: $library.filter)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
        } else {
            Picker("Filter", selection: $library.filter) {
                ForEach(PhotoLibrary.Filter.allCases) { f in
                    Text(f.title).tag(f)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color(uiColor: .systemBackground))
        }
    }

    // Use native .navigationSubtitle on iOS 26+, no-op on older versions.
    private struct NavSubtitleModifier: ViewModifier {
        let text: String
        func body(content: Content) -> some View {
            if #available(iOS 26.0, *) {
                content.navigationSubtitle(text)
            } else {
                content
            }
        }
    }

    // Apple's scroll edge effect: subtle fade behind the nav bar/filter so titles stay legible.
    private struct ScrollEdgeEffectModifier: ViewModifier {
        func body(content: Content) -> some View {
            if #available(iOS 26.0, *) {
                content.scrollEdgeEffectStyle(.soft, for: .top)
            } else {
                content
            }
        }
    }

    // MARK: - Permission gate
    private var permissionGate: some View {
        VStack(spacing: 24) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 72))
                .foregroundColor(appBlue)
            Text("Photo access required")
                .font(.title2.bold())
                .multilineTextAlignment(.center)
            Text("Media Transfer needs access to your photo library to select what to copy.")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button {
                Task {
                    if library.authStatus == .denied || library.authStatus == .restricted {
                        showPhotoPermissionAlert = true
                    } else {
                        await library.requestAuthorization()
                    }
                }
            } label: {
                Text("Allow Access")
                    .font(.headline)
                    .frame(maxWidth: 320)
                    .padding()
            }
            .buttonStyle(.borderedProminent)
            .tint(appBlue)
        }
        .padding()
    }

    private var countLabel: String {
        if !library.selectedIdentifiers.isEmpty {
            return String(format: NSLocalizedString("%lld of %lld selected", comment: "selected count"),
                          library.selectedIdentifiers.count, library.totalCount)
        }
        return String(format: NSLocalizedString("%lld items", comment: "total items"), library.totalCount)
    }

    // MARK: - Bottom bar (system safe area inset = Liquid Glass on iOS 26)
    private var bottomBar: some View {
        VStack(spacing: 12) {
            if transfer.isTransferring {
                progressCard
            } else {
                actionsCard
                primaryButton
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    private var actionsCard: some View {
        VStack(spacing: 0) {
            Button {
                showDirectoryPicker = true
            } label: {
                HStack {
                    Image(systemName: "folder")
                        .foregroundColor(appBlue)
                    Text("Save to")
                        .foregroundColor(.primary)
                    Spacer()
                    if let dir = appState.selectedDirectory {
                        Text(dir.lastPathComponent)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    } else {
                        Text("Choose…").foregroundColor(.secondary)
                    }
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .contentShape(Rectangle())
            }

            Divider().padding(.leading, 16)

            HStack {
                Image(systemName: "trash")
                    .foregroundColor(appBlue)
                Toggle(isOn: $deleteAfter) {
                    Text("Auto-delete after transfer")
                }
                .tint(appBlue)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .background {
            if #available(iOS 26.0, *) {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.regularMaterial)
            } else {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemGroupedBackground))
            }
        }
    }

    @ViewBuilder
    private var primaryButton: some View {
        if #available(iOS 26.0, *) {
            Button(action: startTransfer) {
                Text("Start Transfer")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.glassProminent)
            .tint(appBlue)
            .controlSize(.large)
            .disabled(!canTransfer)
        } else {
            Button(action: startTransfer) {
                Text("Start Transfer")
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(canTransfer ? appBlue : Color.gray.opacity(0.4))
                    .cornerRadius(12)
            }
            .disabled(!canTransfer)
        }
    }

    private var progressCard: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Transferring...")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(transfer.completed) / \(transfer.total)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .monospacedDigit()
            }
            ProgressView(value: transfer.progress)
                .tint(appBlue)
            if !transfer.currentFileName.isEmpty {
                Text(transfer.currentFileName)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack {
                Text("\(Int(transfer.progress * 100))%")
                    .font(.caption.monospacedDigit())
                Spacer()
                Button(role: .destructive) {
                    transfer.cancel()
                } label: {
                    Text("Cancel")
                        .font(.subheadline.weight(.semibold))
                }
            }
            Text("Keep this app open until finished")
                .font(.caption2)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .background {
            if #available(iOS 26.0, *) {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.regularMaterial)
            } else {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(uiColor: .secondarySystemGroupedBackground))
            }
        }
    }

    // MARK: - Logic
    private var canTransfer: Bool {
        !library.selectedIdentifiers.isEmpty
            && appState.selectedDirectory != nil
            && !transfer.isTransferring
    }

    private func startTransfer() {
        guard let destinationURL = appState.selectedDirectory else { return }
        guard appState.requestAccess() else {
            errorMessage = "No access to selected folder"
            showError = true
            return
        }
        let assets = library.selectedAssets
        transfer.start(assets: assets, destination: destinationURL, deleteAfter: deleteAfter) { outcome in
            if outcome.succeeded > 0 {
                UserStats.recordTransfer(succeededItems: outcome.succeeded)
            }
            self.resultAlert = makeAlert(for: outcome)
            if outcome.failed.isEmpty && !outcome.cancelled && !outcome.outOfSpace {
                ReviewPrompter.requestIfAppropriate()
            }
        }
    }

    private func makeAlert(for outcome: TransferController.Outcome) -> ResultAlert {
        if outcome.outOfSpace {
            return ResultAlert(
                title: NSLocalizedString("Not enough space", comment: ""),
                message: String(format: NSLocalizedString("The destination doesn't have enough free space. %lld item(s) were copied before stopping.", comment: ""), outcome.succeeded),
                resetSelection: false
            )
        }
        if outcome.cancelled {
            return ResultAlert(
                title: NSLocalizedString("Cancelled", comment: ""),
                message: String(format: NSLocalizedString("Transfer cancelled. %lld item(s) copied.", comment: ""), outcome.succeeded),
                resetSelection: false
            )
        }
        if !outcome.failed.isEmpty {
            let preview = outcome.failed.prefix(5).joined(separator: "\n")
            let extra = outcome.failed.count > 5
                ? String(format: NSLocalizedString("\n…and %lld more", comment: ""), outcome.failed.count - 5)
                : ""
            return ResultAlert(
                title: NSLocalizedString("Transfer completed with errors", comment: ""),
                message: String(format: NSLocalizedString("Copied %lld item(s). Failed:\n%@%@", comment: ""), outcome.succeeded, preview, extra),
                resetSelection: outcome.succeeded > 0
            )
        }
        return ResultAlert(
            title: NSLocalizedString("Transfer completed", comment: ""),
            message: String(format: NSLocalizedString("All %lld item(s) copied successfully.", comment: ""), outcome.succeeded),
            resetSelection: true
        )
    }
}

#Preview {
    MediaPickerView()
}

// MARK: - Glass Filter Capsule (iOS 26+)
@available(iOS 26.0, *)
private struct GlassFilterCapsule: View {
    @Binding var filter: PhotoLibrary.Filter
    @Namespace private var ns

    var body: some View {
        HStack(spacing: 0) {
            ForEach(PhotoLibrary.Filter.allCases) { f in
                let isSelected = filter == f
                Button {
                    UISelectionFeedbackGenerator().selectionChanged()
                    withAnimation(.smooth(duration: 0.3, extraBounce: 0.2)) {
                        filter = f
                    }
                } label: {
                    Text(f.title)
                        .font(.subheadline.weight(isSelected ? .semibold : .regular))
                        .foregroundStyle(isSelected ? Color.primary : Color.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background {
                            if isSelected {
                                Capsule()
                                    .fill(.regularMaterial)
                                    .matchedGeometryEffect(id: "selectedFilter", in: ns)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .glassEffect(.regular, in: Capsule())
    }
}
