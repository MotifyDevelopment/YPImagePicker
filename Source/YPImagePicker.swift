//
//  YPImagePicker.swift
//  YPImgePicker
//
//  Created by Sacha Durand Saint Omer on 27/10/16.
//  Copyright © 2016 Yummypets. All rights reserved.
//

import AVFoundation
import Photos
import UIKit

public protocol YPImagePickerDelegate: AnyObject {
    func noPhotos()
}

open class YPImagePicker: UINavigationController {
    private var _didFinishPicking: (([YPMediaItem], Bool) -> Void)?
    public func didFinishPicking(completion: @escaping (_ items: [YPMediaItem], _ cancelled: Bool) -> Void) {
        _didFinishPicking = completion
    }

    public weak var imagePickerDelegate: YPImagePickerDelegate?

    open override var preferredStatusBarStyle: UIStatusBarStyle {
        return YPImagePickerConfiguration.shared.preferredStatusBarStyle
    }

    // This nifty little trick enables us to call the single version of the callbacks.
    // This keeps the backwards compatibility keeps the api as simple as possible.
    // Multiple selection becomes available as an opt-in.
    private func didSelect(items: [YPMediaItem]) {
        DispatchQueue.main.async {
            if self.picker.isIgnoringInteraction {
                UIApplication.shared.endIgnoringInteractionEvents()
                self.picker.isIgnoringInteraction = false
            }
        }
        _didFinishPicking?(items, false)
    }

    let loadingView = YPLoadingView()
    private let picker: YPPickerVC!

    /// Get a YPImagePicker instance with the default configuration.
    public convenience init() {
        self.init(configuration: YPImagePickerConfiguration.shared)
    }

    /// Get a YPImagePicker with the specified configuration.
    public required init(configuration: YPImagePickerConfiguration) {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            log.error("Failed work with AVAudioSession")
        }
        YPImagePickerConfiguration.shared = configuration
        picker = YPPickerVC()
        super.init(nibName: nil, bundle: nil)
        picker.imagePickerDelegate = self
    }

    public required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    open override func viewDidLoad() {
        super.viewDidLoad()
        picker.didClose = { [weak self] in
            self?._didFinishPicking?([], true)
        }
        viewControllers = [picker]
        setupLoadingView()
        navigationBar.isTranslucent = false

        picker.didSelectItems = { [weak self] items in
            // Use Fade transition instead of default push animation
            let transition = CATransition()
            transition.duration = 0.3
            transition.timingFunction = CAMediaTimingFunction(name: CAMediaTimingFunctionName.easeInEaseOut)
            transition.type = CATransitionType.fade
            self?.view.layer.add(transition, forKey: nil)

            // Multiple items flow
            if items.count > 1 {
                if YPConfig.library.skipSelectionsGallery {
                    self?.didSelect(items: items)
                    return
                } else {
                    let selectionsGalleryVC = YPSelectionsGalleryVC(items: items) { _, items in
                        self?.didSelect(items: items)
                    }
                    self?.pushViewController(selectionsGalleryVC, animated: true)
                    return
                }
            }

            // One item flow
            let item = items.first!
            switch item {
            case let .photo(photo):
                let completion = { (photo: YPMediaPhoto) in
                    let mediaItem = YPMediaItem.photo(p: photo)
                    // Save new image or existing but modified, to the photo album.
                    if YPConfig.shouldSaveNewPicturesToAlbum {
                        let isModified = photo.modifiedImage != nil
                        if photo.fromCamera || (!photo.fromCamera && isModified) {
                            YPPhotoSaver.trySaveImage(photo.image, inAlbumNamed: YPConfig.albumName)
                        }
                    }
                    self?.didSelect(items: [mediaItem])
                }

                func showCropVC(photo: YPMediaPhoto, completion: @escaping (_ aphoto: YPMediaPhoto) -> Void) {
                    if case let YPCropType.rectangle(ratio) = YPConfig.showsCrop {
                        let cropVC = YPCropVC(image: photo.image, ratio: ratio)
                        cropVC.didFinishCropping = { croppedImage in
                            photo.modifiedImage = croppedImage
                            completion(photo)
                        }
                        self?.pushViewController(cropVC, animated: true)
                    } else {
                        completion(photo)
                    }
                }

                if YPConfig.showsPhotoFilters {
                    let filterVC = YPPhotoFiltersVC(inputPhoto: photo,
                                                    isFromSelectionVC: false)
                    // Show filters and then crop
                    filterVC.didSave = { outputMedia in
                        if case let YPMediaItem.photo(outputPhoto) = outputMedia {
                            showCropVC(photo: outputPhoto, completion: completion)
                        }
                    }
                    self?.pushViewController(filterVC, animated: false)
                } else {
                    showCropVC(photo: photo, completion: completion)
                }
            case let .video(video):
                if YPConfig.showsVideoTrimmer {
                    let videoFiltersVC = YPVideoFiltersVC.initWith(video: video,
                                                                   isFromSelectionVC: false)
                    videoFiltersVC.didSave = { [weak self] outputMedia in
                        self?.didSelect(items: [outputMedia])
                    }
                    self?.pushViewController(videoFiltersVC, animated: true)
                } else {
                    self?.didSelect(items: [YPMediaItem.video(v: video)])
                }
            }
        }

        // If user has not customized the Nav Bar tintColor, then use black.
        if UINavigationBar.appearance().tintColor == nil {
            UINavigationBar.appearance().tintColor = .black
        }
    }

    deinit {
        print("Picker deinited 👍")
    }

    private func setupLoadingView() {
        view.sv(
            loadingView
        )
        loadingView.fillContainer()
        loadingView.alpha = 0
    }
}

extension YPImagePicker: ImagePickerDelegate {
    func noPhotos() {
        imagePickerDelegate?.noPhotos()
    }
}
