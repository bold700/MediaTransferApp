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
        ZStack {
            if library.isAuthorized {
                authorizedContent
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

    // MARK: - Authorized layout
    private var authorizedContent: some View {
        GeometryReader { geo in
            let topUI: CGFloat = library.isLimited ? 175 : 138
            let bottomUI: CGFloat = transfer.isTransferring ? 200 : 220
            let topInset = geo.safeAreaInsets.top + topUI
            let bottomInset = geo.safeAreaInsets.bottom + bottomUI

            ZStack(alignment: .top) {
                MediaGridView(
                    library: library,
                    transferring: transfer.isTransferring,
                    topInset: topInset,
                    bottomInset: bottomInset
                )
                    .ignoresSafeArea()

                topOverlay
                    .frame(maxWidth: .infinity, alignment: .top)

                VStack(spacing: 0) {
                    Spacer()
                    bottomOverlay
                }
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
                    .foregroundColor(.white)
                    .frame(maxWidth: 320)
                    .padding()
                    .background(appBlue)
                    .cornerRadius(12)
            }
        }
        .padding()
    }

    // MARK: - Top overlay
    private var topOverlay: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Select Media")
                        .font(.title.bold())
                        .foregroundColor(.white)
                    Text(countLabel)
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.85))
                        .monospacedDigit()
                }
                Spacer()
                Button {
                    showSettings = true
                } label: {
                    Image(systemName: "gearshape")
                        .font(.title3)
                        .foregroundColor(.white)
                        .frame(width: 36, height: 36)
                        .background(Color.white.opacity(0.2))
                        .clipShape(Circle())
                }
                .accessibilityLabel("Settings")
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 12)

            Picker("Filter", selection: $library.filter) {
                ForEach(PhotoLibrary.Filter.allCases) { f in
                    Text(f.title).tag(f)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.bottom, 12)

            if library.isLimited {
                limitedBanner
            }
        }
        .background {
            LinearGradient(
                stops: [
                    .init(color: Color.black.opacity(0.85), location: 0.0),
                    .init(color: Color.black.opacity(0.85), location: 0.65),
                    .init(color: Color.black.opacity(0.5),  location: 0.85),
                    .init(color: Color.clear,               location: 1.0)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea(edges: .top)
            .allowsHitTesting(false)
        }
    }

    private var limitedBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "info.circle")
                .foregroundColor(.secondary)
            Text("You've granted access to a limited set of photos.")
                .font(.footnote)
                .foregroundColor(.secondary)
                .lineLimit(2)
            Spacer()
            Button {
                if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                   let root = scene.windows.first?.rootViewController {
                    library.presentLimitedPicker(from: root)
                }
            } label: {
                Text("Manage")
                    .font(.footnote.weight(.semibold))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(uiColor: .secondarySystemBackground))
    }

    private var countLabel: String {
        if !library.selectedIdentifiers.isEmpty {
            return String(format: NSLocalizedString("%lld of %lld selected", comment: "selected count"),
                          library.selectedIdentifiers.count, library.totalCount)
        }
        return String(format: NSLocalizedString("%lld items", comment: "total items"), library.totalCount)
    }

    // MARK: - Bottom overlay
    private var bottomOverlay: some View {
        VStack(spacing: 0) {
            if transfer.isTransferring {
                progressCard
                    .padding(.horizontal, 16)
                    .padding(.top, 24)
                    .padding(.bottom, 12)
            } else {
                groupedList
                    .padding(.horizontal, 16)
                    .padding(.top, 24)
                primaryButton
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 12)
            }
        }
        .background {
            LinearGradient(
                colors: [
                    Color.clear,
                    Color.black.opacity(0.25),
                    Color.black.opacity(0.55),
                    Color.black.opacity(0.85),
                    Color.black.opacity(0.95)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea(edges: .bottom)
            .allowsHitTesting(false)
        }
    }

    private var groupedList: some View {
        VStack(spacing: 0) {
            Button {
                showDirectoryPicker = true
            } label: {
                HStack {
                    Image(systemName: "folder")
                        .foregroundColor(appBlue)
                    Text("Save to")
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
            .foregroundColor(.primary)

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
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .cornerRadius(12)
    }

    private var primaryButton: some View {
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
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .cornerRadius(12)
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
