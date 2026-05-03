import SwiftUI
import VisionKit
import Vision
import UIKit

/// Wrapper SwiftUI autour de `VNDocumentCameraViewController`. Permet à l'utilisateur
/// de prendre une photo d'une page du cahier de suivi (papier rempli par l'école /
/// le centre) — la page est ensuite passée à Vision pour OCR.
struct BookletScannerView: UIViewControllerRepresentable {
    enum Result {
        case success(images: [UIImage])
        case cancelled
        case failed(Error)
    }

    let onCompletion: (Result) -> Void

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let vc = VNDocumentCameraViewController()
        vc.delegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ uiViewController: VNDocumentCameraViewController, context: Context) { }

    func makeCoordinator() -> Coordinator {
        Coordinator(onCompletion: onCompletion)
    }

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let onCompletion: (Result) -> Void
        init(onCompletion: @escaping (Result) -> Void) { self.onCompletion = onCompletion }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
            var images: [UIImage] = []
            for i in 0..<scan.pageCount {
                images.append(scan.imageOfPage(at: i))
            }
            controller.dismiss(animated: true)
            onCompletion(.success(images: images))
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            controller.dismiss(animated: true)
            onCompletion(.cancelled)
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) {
            controller.dismiss(animated: true)
            onCompletion(.failed(error))
        }
    }
}

/// OCR sur une image avec Vision. Renvoie le texte concaténé ligne par ligne.
@MainActor
enum BookletOCR {
    static func recognizeText(from image: UIImage) async throws -> String {
        guard let cgImage = image.cgImage else { return "" }
        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<String, Error>) in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    cont.resume(throwing: error)
                    return
                }
                let observations = (request.results as? [VNRecognizedTextObservation]) ?? []
                let text = observations
                    .compactMap { $0.topCandidates(1).first?.string }
                    .joined(separator: "\n")
                cont.resume(returning: text)
            }
            // Le cahier est rédigé à la main ou tapuscrit en français — on couvre les deux.
            request.recognitionLanguages = ["fr-FR", "en-US"]
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            DispatchQueue.global(qos: .userInitiated).async {
                do { try handler.perform([request]) }
                catch { cont.resume(throwing: error) }
            }
        }
    }
}
