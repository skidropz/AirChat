//
//  ImagePickerCoordinator.swift
//  AirChat
//
//  Photo attachments. On Android the WebView's WebChromeClient.onShowFileChooser
//  bridges <input type="file"> to the system picker. WKWebView has **no** public API
//  for that — a file input simply does nothing — so the page asks us over the message
//  bridge and we run the picker ourselves, then hand back exactly what the JS canvas
//  pipeline would have produced: a resized JPEG data URL.
//

import AVFoundation
import ImageIO
import PhotosUI
import UIKit
import UniformTypeIdentifiers

final class ImagePickerCoordinator: NSObject {

    private var completion: ((String?) -> Void)?
    private weak var presenter: UIViewController?
    private var picker: PHPickerViewController?
    private var camera: UIImagePickerController?

    /// Returns a `data:image/jpeg;base64,…` string, or nil if the user cancelled.
    func present(from presenter: UIViewController, completion: @escaping (String?) -> Void) {
        guard self.completion == nil else {
            completion(nil)
            return
        }
        self.presenter = presenter
        self.completion = completion

        if UIImagePickerController.isSourceTypeAvailable(.camera) {
            let sheet = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
            sheet.addAction(UIAlertAction(title: Localization.t("PICK_PHOTO", "Choose Photo"),
                                         style: .default) { [weak self] _ in self?.openLibrary() })
            sheet.addAction(UIAlertAction(title: Localization.t("TAKE_PHOTO", "Take Photo"),
                                         style: .default) { [weak self] _ in self?.openCamera() })
            sheet.addAction(UIAlertAction(title: Localization.t("CANCEL", "Cancel"),
                                         style: .cancel) { [weak self] _ in self?.finish(nil) })
            presenter.present(sheet, animated: true)
        } else {
            openLibrary()
        }
    }

    // MARK: - Library (PHPicker: no photo-library permission prompt at all)

    private func openLibrary() {
        var config = PHPickerConfiguration()
        config.selectionLimit = 1
        config.filter = .images
        // .current avoids re-encoding HEIC → keeps the bytes small and fast.
        config.preferredAssetRepresentationMode = .current
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = self
        picker.isModalInPresentation = false
        self.picker = picker
        presenter?.present(picker, animated: true)
    }

    // MARK: - Camera

    private func openCamera() {
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else { finish(nil); return }
        let controller = UIImagePickerController()
        controller.sourceType = .camera
        controller.mediaTypes = ["public.image"]
        controller.cameraCaptureMode = .photo
        controller.delegate = self
        self.camera = controller
        presenter?.present(controller, animated: true)
    }

    private func finish(_ payload: String?) {
        let completion = self.completion
        self.completion = nil
        DispatchQueue.main.async {
            self.picker?.dismiss(animated: true)
            self.camera?.dismiss(animated: true)
            self.picker = nil
            self.camera = nil
            completion?(payload)
        }
    }

    // MARK: - Encoding (mirrors processAndSendImage() in app.js)

    private static func encodeToDataURL(_ image: UIImage, maxDimension: CGFloat = 800, quality: CGFloat = 0.7) -> String? {
        let size = image.size
        guard size.width > 0, size.height > 0 else { return nil }
        var width = size.width
        var height = size.height
        if width > height {
            if width > maxDimension { height *= maxDimension / width; width = maxDimension }
        } else {
            if height > maxDimension { width *= maxDimension / height; height = maxDimension }
        }
        width = max(1, floor(width))
        height = max(1, floor(height))

        let resized: UIImage
        if width == size.width, height == size.height {
            resized = image
        } else {
            let format = UIGraphicsImageRendererFormat.default()
            format.scale = 1
            format.opaque = true
            let renderer = UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format)
            resized = renderer.image { _ in
                image.draw(in: CGRect(x: 0, y: 0, width: width, height: height))
            }
        }
        guard let data = resized.jpegData(compressionQuality: quality) else { return nil }
        return "data:image/jpeg;base64," + data.base64EncodedString()
    }
}

extension ImagePickerCoordinator: PHPickerViewControllerDelegate {
    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        guard let provider = results.first?.itemProvider else { finish(nil); return }

        guard provider.canLoadObject(ofClass: UIImage.self) else { finish(nil); return }
        provider.loadObject(ofClass: UIImage.self) { [weak self] object, error in
            if let error = error { NSLog("AirChat: picker load failed \(error.localizedDescription)") }
            guard let self = self, let image = object as? UIImage else {
                self?.finish(nil)
                return
            }
            self.finish(ImagePickerCoordinator.encodeToDataURL(image))
        }
    }
}

extension ImagePickerCoordinator: UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    func imagePickerController(_ picker: UIImagePickerController,
                               didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
        let image = (info[.editedImage] as? UIImage) ?? (info[.originalImage] as? UIImage)
        guard let image = image else { finish(nil); return }
        finish(ImagePickerCoordinator.encodeToDataURL(image))
    }

    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        finish(nil)
    }
}
