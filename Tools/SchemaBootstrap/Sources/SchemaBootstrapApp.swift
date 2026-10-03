import SwiftUI
import UIKit
import Combine
import CloudKit

@main
@MainActor
struct SchemaBootstrapApp: App {
    @StateObject private var setup = SchemaBootstrapController()

    var body: some Scene {
        WindowGroup {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Image(systemName: "icloud.and.arrow.up").font(.system(size: 48)).foregroundStyle(.teal)
                    Text("تهيئة مزامنة شيكاتي\nSet up Shekati sync").font(.largeTitle.bold())
                    Text("جهّز بنية التخزين السحابي، ثم راجعها وانشرها من لوحة CloudKit.\nPrepare the cloud storage structure, then review and deploy it in CloudKit Console.")
                    LabeledContent("Environment", value: "Development")
                    if let identifier = setup.containerIdentifier {
                        Text(identifier).font(.footnote.monospaced()).textSelection(.enabled)
                    }
                    Text("سجّل الدخول إلى iCloud على هذا الآيفون، وابقَ في هذه الشاشة حتى تنتهي العملية.\nSign in to iCloud on this iPhone and keep this screen open until setup finishes.")
                        .font(.callout)
                    if setup.isRunning { ProgressView() }
                    if let message = setup.message { Text(message).textSelection(.enabled) }
                    if let diagnostic = setup.diagnostic {
                        Text(diagnostic).font(.footnote).foregroundStyle(.secondary).textSelection(.enabled)
                    }
                    Button {
                        Task { await setup.initialize() }
                    } label: {
                        Text(setup.succeeded ? "اكتملت التهيئة / Setup complete" : "ابدأ التهيئة / Start setup")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(setup.isRunning || setup.succeeded)
                    if setup.succeeded {
                        Text("راجع أنواع السجلات والحقول في بيئة التطوير، ثم اختر Deploy Schema Changes. بعد ذلك اختبر المزامنة من نسخة TestFlight.\nReview the development record types and fields, choose Deploy Schema Changes, then verify sync in the TestFlight app.")
                        Link("CloudKit Console", destination: URL(string: "https://icloud.developer.apple.com/")!)
                    }
                }
                .padding(24)
            }
        }
    }
}

@MainActor
final class SchemaBootstrapController: ObservableObject {
    @Published private(set) var isRunning = false
    @Published private(set) var succeeded = false
    @Published private(set) var message: String?
    @Published private(set) var diagnostic: String?

    let containerIdentifier = Bundle.main.object(forInfoDictionaryKey: "ShekatiCloudContainerIdentifier") as? String

    func initialize() async {
        guard !isRunning, !succeeded else { return }
        #if targetEnvironment(simulator)
        message = "ثبّت النسخة الموقعة على الآيفون لتهيئة المزامنة.\nInstall the signed setup build on your iPhone to initialize sync."
        return
        #endif
        guard let identifier = containerIdentifier, identifier.hasPrefix("iCloud."), !identifier.contains("$("),
              Bundle.main.object(forInfoDictionaryKey: "ShekatiCloudEnvironment") as? String == "Development" else {
            message = "إعداد الحاوية غير مكتمل.\nCloud container setup is incomplete."
            return
        }
        isRunning = true
        diagnostic = nil
        UIApplication.shared.isIdleTimerDisabled = true
        defer {
            UIApplication.shared.isIdleTimerDisabled = false
            isRunning = false
        }
        do {
            message = "جارٍ التحقق من iCloud…\nChecking iCloud…"
            let status = try await CKContainer(identifier: identifier).accountStatus()
            guard status == .available else {
                message = "سجّل الدخول إلى iCloud وفعّل iCloud Drive، ثم حاول مجددًا.\nSign in to iCloud and enable iCloud Drive, then try again."
                return
            }
            message = "جارٍ تجهيز بنية التخزين…\nPreparing cloud storage…"
            try await SchemaInitializer.initialize(containerIdentifier: identifier)
            succeeded = true
            message = "اكتملت التهيئة. راجع البنية وانشرها من لوحة CloudKit.\nInitialization completed. Review and deploy the schema in CloudKit Console."
        } catch {
            message = "تعذرت التهيئة. تحقّق من الاتصال وإعدادات iCloud ثم حاول مجددًا.\nSetup failed. Check your connection and iCloud settings, then try again."
            diagnostic = error.localizedDescription
        }
    }
}
