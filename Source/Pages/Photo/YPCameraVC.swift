//
//  YPCameraVC.swift
//  YPImgePicker
//
//  Created by Sacha Durand Saint Omer on 25/10/16.
//  Copyright © 2016 Yummypets. All rights reserved.
//

import AVFoundation
import Photos
import UIKit

public class YPCameraVC: UIViewController, UIGestureRecognizerDelegate, YPPermissionCheckable {
    weak var videoCaptureDelegate: YPVideoCaptureDelegate?
    weak var photoCaptureDelegate: YPPhotoCaptureDelegate?
    public var didCapturePhoto: ((UIImage) -> Void)?
    var photoCapture = newPhotoCapture()
    let v: YPCameraView!
    public override func loadView() { view = v }

    public required init() {
        v = YPCameraView(overlayView: YPConfig.overlayView)
        super.init(nibName: nil, bundle: nil)
        title = YPConfig.wordings.cameraTitle
    }

    public required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func viewDidLoad() {
        super.viewDidLoad()
        v.flashButton.isHidden = true
        v.flashButton.addTarget(self, action: #selector(flashButtonTapped), for: .touchUpInside)
        v.shotButton.addTarget(self, action: #selector(shotButtonTapped), for: .touchUpInside)
        v.flipButton.addTarget(self, action: #selector(flipButtonTapped), for: .touchUpInside)

        // Focus
        let tapRecognizer = UITapGestureRecognizer(target: self, action: #selector(focusTapped(_:)))
        tapRecognizer.delegate = self
        v.previewViewContainer.addGestureRecognizer(tapRecognizer)
    }

    func start() {
        doAfterPermissionCheck { [weak self] in
            self?.videoCaptureDelegate?.willStartVideoCapture(completion: { [weak self] in
                guard let strongSelf = self else {
                    return
                }
                self?.photoCapture.start(with: strongSelf.v.previewViewContainer, completion: {
                    DispatchQueue.main.async {
                        self?.refreshFlashButton()
                    }
                })
            })
        }
    }

    @objc
    func focusTapped(_ recognizer: UITapGestureRecognizer) {
        doAfterPermissionCheck { [weak self] in
            self?.focus(recognizer: recognizer)
        }
    }

    func focus(recognizer: UITapGestureRecognizer) {
        let point = recognizer.location(in: v.previewViewContainer)

        // Focus the capture
        let viewsize = v.previewViewContainer.bounds.size
        let newPoint = CGPoint(x: point.x / viewsize.width, y: point.y / viewsize.height)
        photoCapture.focus(on: newPoint)

        // Animate focus view
        v.focusView.center = point
        YPHelper.configureFocusView(v.focusView)
        v.addSubview(v.focusView)
        YPHelper.animateFocusView(v.focusView)
    }

    func stopCamera(completion: (() -> Void)? = nil) {
        photoCapture.stopCamera(completion: completion)
    }

    @objc
    func flipButtonTapped() {
        doAfterPermissionCheck { [weak self] in
            self?.v.shotButton.isEnabled = false
            self?.photoCapture.flipCamera { [weak self] in
                self?.refreshFlashButton()
                self?.v.shotButton.isEnabled = true
            }
        }
    }

    @objc
    func shotButtonTapped() {
        doAfterPermissionCheck { [weak self] in
            self?.shoot()
        }
    }

    func shoot() {
        // Prevent from tapping multiple times in a row
        // causing a crash
        if !(photoCapture.hasInputs && photoCapture.session.isRunning) {
            return
        }

        v.shotButton.isEnabled = false

        photoCaptureDelegate?.willStartPhotoCapture()

        photoCapture.shoot { imageData in
            guard let unwrappedImageData = imageData,
                let shotImage = UIImage(data: unwrappedImageData) else {
                self.v.shotButton.isEnabled = true
                self.photoCaptureDelegate?.didCancelPhotoCapture()
                return
            }

            self.photoCapture.stopCamera()

            var image = shotImage
            // Crop the image if the output needs to be square.
            if YPConfig.onlySquareImagesFromCamera {
                image = self.cropImageToSquare(image)
            }

            // Flip image if taken form the front camera.
            if let device = self.photoCapture.device, device.position == .front {
                image = self.flipImage(image: image)
            }

            DispatchQueue.main.async {
                let noOrietationImage = image.resetOrientation()
                self.didCapturePhoto?(noOrietationImage.resizedImageIfNeeded())
            }
        }
    }

    func cropImageToSquare(_ image: UIImage) -> UIImage {
        let orientation: UIDeviceOrientation = UIDevice.current.orientation
        var imageWidth = image.size.width
        var imageHeight = image.size.height
        switch orientation {
        case .landscapeLeft, .landscapeRight:
            // Swap width and height if orientation is landscape
            imageWidth = image.size.height
            imageHeight = image.size.width
        default:
            break
        }

        // The center coordinate along Y axis
        let rcy = imageHeight * 0.5
        let rect = CGRect(x: rcy - imageWidth * 0.5, y: 0, width: imageWidth, height: imageWidth)
        let imageRef = image.cgImage?.cropping(to: rect)
        return UIImage(cgImage: imageRef!, scale: 1.0, orientation: image.imageOrientation)
    }

    // Used when image is taken from the front camera.
    func flipImage(image: UIImage!) -> UIImage! {
        let imageSize: CGSize = image.size
        UIGraphicsBeginImageContextWithOptions(imageSize, true, 1.0)
        let ctx = UIGraphicsGetCurrentContext()!
        ctx.rotate(by: CGFloat(Double.pi / 2.0))
        ctx.translateBy(x: 0, y: -imageSize.width)
        ctx.scaleBy(x: imageSize.height / imageSize.width, y: imageSize.width / imageSize.height)
        ctx.draw(image.cgImage!, in: CGRect(x: 0.0,
                                            y: 0.0,
                                            width: imageSize.width,
                                            height: imageSize.height))
        let newImage: UIImage = UIGraphicsGetImageFromCurrentImageContext()!
        UIGraphicsEndImageContext()
        return newImage
    }

    @objc
    func flashButtonTapped() {
        photoCapture.tryToggleFlash()
        refreshFlashButton()
    }

    func refreshFlashButton() {
        let flashImage = photoCapture.currentFlashMode.flashImage()
        v.flashButton.setImage(flashImage, for: .normal)
        v.flashButton.isHidden = !photoCapture.hasFlash
    }
}
