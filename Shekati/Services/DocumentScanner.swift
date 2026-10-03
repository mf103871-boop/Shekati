import SwiftUI
import VisionKit

struct DocumentScanner: UIViewControllerRepresentable {
    var onScan: (UIImage) -> Void
    var onCancel: () -> Void

    static var isSupported: Bool { VNDocumentCameraViewController.isSupported }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIViewController(context: Context) -> UIViewController {
        guard Self.isSupported else {
            let fallback = ScannerUnavailableViewController()
            fallback.onCancel = onCancel
            return fallback
        }
        let controller = VNDocumentCameraViewController()
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        context.coordinator.parent = self
    }

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        var parent: DocumentScanner
        init(parent: DocumentScanner) { self.parent = parent }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
            guard scan.pageCount > 0 else { parent.onCancel(); return }
            // One image represents one cheque; the form always requires confirmation of OCR suggestions.
            parent.onScan(scan.imageOfPage(at: 0))
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) { parent.onCancel() }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) {
            let alert = UIAlertController(title: "تعذر المسح / Scan unavailable",
                                          message: "يمكنك إضافة صورة أو إدخال المعلومات يدويًا. / Add a photo or enter the details manually.",
                                          preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "حسنًا / OK", style: .default) { [weak self] _ in self?.parent.onCancel() })
            controller.present(alert, animated: true)
        }
    }
}

private final class ScannerUnavailableViewController: UIViewController {
    var onCancel: (() -> Void)?
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        let label = UILabel()
        label.text = "المسح غير متاح على هذا الجهاز. يمكنك إضافة صورة أو إدخال المعلومات يدويًا.\n\nScanning is unavailable on this device. Add a photo or enter the details manually."
        label.numberOfLines = 0
        label.textAlignment = .center
        let close = UIButton(type: .system)
        close.setTitle("إغلاق / Close", for: .normal)
        close.addAction(UIAction { [weak self] _ in self?.onCancel?() }, for: .touchUpInside)
        let stack = UIStackView(arrangedSubviews: [label, close])
        stack.axis = .vertical
        stack.spacing = 24
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            stack.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 28),
            stack.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor, constant: -28)
        ])
    }
}
