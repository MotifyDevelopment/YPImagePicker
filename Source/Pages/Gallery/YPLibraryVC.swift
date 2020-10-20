//
//  YPLibraryVC.swift
//  YPImagePicker
//
//  Created by Sacha Durand Saint Omer on 27/10/16.
//  Copyright © 2016 Yummypets. All rights reserved.
//

import Photos
import UIKit

public class YPLibraryVC: UIViewController, YPPermissionCheckable {
    private enum Constants {
        static let topViewTag = 1
    }

    internal weak var delegate: YPLibraryViewDelegate?
    internal var v: YPLibraryView!
    internal var isProcessing = false // true if video or image is in processing state
    internal var multipleSelectionEnabled = false
    internal var initialized = false
    internal var selection = [YPLibrarySelection]()
    internal var currentlySelectedIndex: Int = 0
    internal let mediaManager = LibraryMediaManager()
    internal var latestImageTapped = ""
    internal let panGestureHelper = PanGestureHelper()
    internal var emptyView: UIView?
    internal var resumableQueue = YPResumableQueue()
    internal var didSetInitialAlbumTitle = false
    internal var playerWasPlayingBeforeLock = false

    // MARK: - Init

    public required init() {
        super.init(nibName: nil, bundle: nil)
        title = YPConfig.wordings.libraryTitle

        YPConfig.library.onInit?(
            { [weak self] in
                self?.resumeVideoIfNeeded()
            },
            { [weak self] in
                self?.pauseVideoIfNeeded()
            }
        )
    }

    private func resumeVideoIfNeeded() {
        if playerWasPlayingBeforeLock {
            v.assetZoomableView.videoView.player.play()
        }
    }

    private func pauseVideoIfNeeded() {
        playerWasPlayingBeforeLock = v.assetZoomableView.videoView.isPlaying
        v.assetZoomableView.videoView.player.pause()
    }

    public required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setAlbum(_ album: YPAlbum) {
        title = album.title
        mediaManager.collection = album.collection
        currentlySelectedIndex = 0
        refreshMediaRequest()
        refreshSelectionIndex()
    }

    func initialize() {
        mediaManager.initialize()
        mediaManager.v = v

        if mediaManager.fetchResult != nil {
            return
        }

        setupCollectionView()
        registerForLibraryChanges()
        panGestureHelper.registerForPanGesture(on: v)
        registerForTapOnPreview()
        refreshMediaRequest()

        if YPConfig.library.defaultMultipleSelection {
            multipleSelectionButtonTapped()
        }
        v.assetViewContainer.multipleSelectionButton.isHidden = !(YPConfig.library.maxNumberOfItems > 1)
        v.maxNumberWarningLabel.text = String(format: YPConfig.wordings.warningMaxItemsLimit, YPConfig.library.maxNumberOfItems)
    }

    // MARK: - View Lifecycle

    public override func loadView() {
        v = YPLibraryView.xibView()
        view = v
    }

    public override func viewDidLoad() {
        super.viewDidLoad()

        // When crop area changes in multiple selection mode,
        // we need to update the scrollView values in order to restore
        // them when user selects a previously selected item.
        v.assetZoomableView.cropAreaDidChange = { [weak self] in
            guard let strongSelf = self else {
                return
            }

            strongSelf.updateCropInfo()
        }

        v.viewWithTag(Constants.topViewTag)?.backgroundColor = YPImagePickerConfiguration.shared.colors.libraryBackground

        self.emptyView = YPConfig.library.emptyView

        if let emptyView = self.emptyView {
            v.sv(emptyView)
            emptyView.fillContainer()
            emptyView.isHidden = true
        }
    }

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if !didSetInitialAlbumTitle {
            didSetInitialAlbumTitle = true
            title = YPConfig.library.allPhotosDefaultAlbumName
        }
    }

    public override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)

        v.assetViewContainer.squareCropButton
            .addTarget(self,
                       action: #selector(squareCropButtonTapped),
                       for: .touchUpInside)

        v.assetViewContainer.multipleSelectionButton.addGestureRecognizer(
            UITapGestureRecognizer(target: self, action: #selector(multipleSelectionButtonTapped))
        )

        // Forces assetZoomableView to have a contentSize.
        // otherwise 0 in first selection triggering the bug : "invalid image size 0x0"
        // Also fits the first element to the square if the onlySquareFromLibrary = true
        if !YPConfig.library.onlySquare && v.assetZoomableView.contentSize == CGSize(width: 0, height: 0) {
            v.assetZoomableView.setZoomScale(1, animated: false)
        }

        // Activate multiple selection when using `minNumberOfItems`
        if YPConfig.library.minNumberOfItems > 1 {
            multipleSelectionButtonTapped()
        }
    }

    public override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        pausePlayer()
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Crop control

    @objc
    func squareCropButtonTapped() {
        doAfterPermissionCheck { [weak self] in
            self?.v.assetViewContainer.squareCropButtonTapped()
        }
    }

    // MARK: - Multiple Selection

    @objc
    func multipleSelectionButtonTapped() {
        if !multipleSelectionEnabled {
            selection.removeAll()
        }

        // Prevent desactivating multiple selection when using `minNumberOfItems`
        if YPConfig.library.minNumberOfItems > 1 && multipleSelectionEnabled {
            return
        }

        multipleSelectionEnabled = !multipleSelectionEnabled

        if multipleSelectionEnabled {
            if selection.isEmpty {
                let asset = mediaManager.fetchResult[currentlySelectedIndex]
                selection = [
                    YPLibrarySelection(index: currentlySelectedIndex,
                                       cropRect: v.currentCropRect(),
                                       scrollViewContentOffset: v.assetZoomableView!.contentOffset,
                                       scrollViewZoomScale: v.assetZoomableView!.zoomScale,
                                       assetIdentifier: asset.localIdentifier),
                ]
            }
        } else {
            selection.removeAll()
            addToSelection(indexPath: IndexPath(row: currentlySelectedIndex, section: 0))
        }

        v.assetViewContainer.setMultipleSelectionMode(on: multipleSelectionEnabled)
        v.collectionView.reloadData()
        checkLimit()
        delegate?.libraryViewDidToggleMultipleSelection(enabled: multipleSelectionEnabled)
    }

    // MARK: - Tap Preview

    func registerForTapOnPreview() {
        let tapImageGesture = UITapGestureRecognizer(target: self, action: #selector(tappedImage))
        v.assetViewContainer.addGestureRecognizer(tapImageGesture)
    }

    @objc
    func tappedImage() {
        if !panGestureHelper.isImageShown {
            panGestureHelper.resetToOriginalState()
            // no dragup? needed? dragDirection = .up
            v.refreshImageCurtainAlpha()
        }
    }

    // MARK: - Permissions

    func doAfterPermissionCheck(block: @escaping () -> Void) {
        checkPermissionToAccessPhotoLibrary { hasPermission in
            if hasPermission {
                block()
            }
        }
    }

    func checkPermission() {
        checkPermissionToAccessPhotoLibrary { [weak self] hasPermission in
            guard let strongSelf = self else {
                return
            }
            if hasPermission && !strongSelf.initialized {
                strongSelf.initialize()
                strongSelf.initialized = true
            }
        }
    }

    // Async beacause will prompt permission if .notDetermined
    // and ask custom popup if denied.
    func checkPermissionToAccessPhotoLibrary(block: @escaping (Bool) -> Void) {
        // Only intilialize picker if photo permission is Allowed by user.
        let status = PHPhotoLibrary.authorizationStatus()
        switch status {
        case .authorized:
            block(true)
        case .restricted, .denied, .limited:
            let popup = YPPermissionDeniedPopup()
            let alert = popup.popup(cancelBlock: {
                block(false)
            })
            present(alert, animated: true, completion: nil)
        case .notDetermined:
            // Show permission popup and get new status
            PHPhotoLibrary.requestAuthorization { s in
                DispatchQueue.main.async {
                    block(s == .authorized)
                }
            }
        }
    }

    func refreshMediaRequest() {
        let options = buildPHFetchOptions()

        if let collection = mediaManager.collection {
            mediaManager.fetchResult = PHAsset.fetchAssets(in: collection, options: options)
        } else {
            mediaManager.fetchResult = PHAsset.fetchAssets(with: options)
        }

        updateStateForCount(mediaManager.fetchResult.count)
        scrollToTop()
    }

    func updateStateForCount(_ count: Int) {
        if count > 0 {
            emptyView?.isHidden = true
            changeAsset(mediaManager.fetchResult[0])
            v.collectionView.reloadData()
            v.collectionView.selectItem(at: IndexPath(row: 0, section: 0),
                                        animated: false,
                                        scrollPosition: UICollectionView.ScrollPosition())
            if !multipleSelectionEnabled, selection.isEmpty {
                addToSelection(indexPath: IndexPath(row: 0, section: 0))
            }
        } else {
            selection = []
            emptyView?.isHidden = false
            delegate?.noPhotosForOptions()
        }
    }

    func buildPHFetchOptions() -> PHFetchOptions {
        // Sorting condition
        if let userOpt = YPConfig.library.options {
            return userOpt
        }
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.predicate = YPConfig.library.mediaType.predicate()
        return options
    }

    func scrollToTop() {
        tappedImage()
        v.collectionView.contentOffset = CGPoint.zero
    }

    // MARK: - ScrollViewDelegate

    public func scrollViewDidScroll(_ scrollView: UIScrollView) {
        if scrollView == v.collectionView {
            mediaManager.updateCachedAssets(in: v.collectionView)
        }
    }

    func changeVideoAsset(_ asset: PHAsset, storedCropPosition: YPLibrarySelection?) {
        DispatchQueue.global(qos: .userInitiated).async {
            switch asset.mediaType {
            case .video:
                self.mediaManager.cancelPendingFetchRequests()
                self.v.assetZoomableView.setVideo(asset,
                                                  mediaManager: self.mediaManager,
                                                  storedCropPosition: storedCropPosition,
                                                  completion: {})
            case .image, .audio, .unknown:
                break
            }
        }
    }

    func changeAsset(_ asset: PHAsset) {
        latestImageTapped = asset.localIdentifier
        delegate?.libraryViewStartedLoading(withSpinner: true)

        let completion = {
            self.v.hideLoader()
            self.v.hideGrid()
            self.delegate?.libraryViewFinishedLoading()
            self.v.assetViewContainer.refreshSquareCropButton()
            self.updateCropInfo()
        }

        DispatchQueue.global(qos: .userInitiated).async {
            switch asset.mediaType {
            case .image:
                self.mediaManager.cancelPendingFetchRequests()
                self.v.assetZoomableView.setImage(asset,
                                                  mediaManager: self.mediaManager,
                                                  storedCropPosition: self.fetchStoredCrop(),
                                                  completion: completion)
            case .video:
                self.mediaManager.cancelPendingFetchRequests()
                self.v.assetZoomableView.setVideo(asset,
                                                  mediaManager: self.mediaManager,
                                                  storedCropPosition: self.fetchStoredCrop(),
                                                  completion: completion)
            case .audio, .unknown:
                ()
            }
        }
    }

    // MARK: - Verification

    private func fitsVideoLengthLimits(asset: PHAsset) -> Bool {
        guard asset.mediaType == .video else {
            return true
        }

        let tooLong = asset.duration > YPConfig.video.libraryTimeLimit
        let tooShort = asset.duration < YPConfig.video.minimumTimeLimit

        if tooLong || tooShort {
            DispatchQueue.main.async {
                let alert = tooLong ? YPAlert.videoTooLongAlert(self.view) : YPAlert.videoTooShortAlert(self.view)
                self.present(alert, animated: true, completion: nil)
            }
            return false
        }

        return true
    }

    // MARK: - Stored Crop Position

    internal func updateCropInfo(shouldUpdateOnlyIfNil: Bool = false) {
        guard let selectedAssetIndex = selection.firstIndex(where: { $0.index == currentlySelectedIndex }) else {
            return
        }

        if shouldUpdateOnlyIfNil && selection[selectedAssetIndex].scrollViewContentOffset != nil {
            return
        }

        // Fill new values
        var selectedAsset = selection[selectedAssetIndex]
        selectedAsset.scrollViewContentOffset = v.assetZoomableView.contentOffset
        selectedAsset.scrollViewZoomScale = v.assetZoomableView.zoomScale
        selectedAsset.cropRect = v.currentCropRect()

        // Replace
        selection.remove(at: selectedAssetIndex)
        selection.insert(selectedAsset, at: selectedAssetIndex)
    }

    internal func fetchStoredCrop() -> YPLibrarySelection? {
        if multipleSelectionEnabled,
            selection.contains(where: { $0.index == currentlySelectedIndex }) {
            guard let selectedAssetIndex = self.selection
                .firstIndex(where: { $0.index == self.currentlySelectedIndex }) else {
                return nil
            }
            return self.selection[selectedAssetIndex]
        }
        return nil
    }

    internal func hasStoredCrop(index: Int) -> Bool {
        return selection.contains(where: { $0.index == index })
    }

    // MARK: - Fetching Media

    private func fetchImageAndCrop(for asset: PHAsset,
                                   withCropRect: CGRect? = nil,
                                   callback: @escaping (_ photo: UIImage, _ exif: [String: Any]) -> Void) {
        delegate?.libraryViewStartedLoading(withSpinner: true)
        let cropRect = withCropRect ?? DispatchQueue.main.sync { v.currentCropRect() }
        let ts = targetSize(for: asset, cropRect: cropRect)
        mediaManager.imageManager?.fetchImage(for: asset, cropRect: cropRect, targetSize: ts, callback: callback)
    }

    private func checkVideoLengthAndCrop(for asset: PHAsset,
                                         withCropRect: CGRect? = nil,
                                         callback: @escaping (_ videoURL: URL) -> Void) {
        if fitsVideoLengthLimits(asset: asset) == true {
            delegate?.libraryViewStartedLoading(withSpinner: false)
            let normalizedCropRect = withCropRect ?? DispatchQueue.main.sync { v.currentCropRect() }
            let ts = targetSize(for: asset, cropRect: normalizedCropRect)
            let xCrop: CGFloat = normalizedCropRect.origin.x * CGFloat(asset.pixelWidth)
            let yCrop: CGFloat = normalizedCropRect.origin.y * CGFloat(asset.pixelHeight)
            let resultCropRect = CGRect(x: xCrop,
                                        y: yCrop,
                                        width: ts.width,
                                        height: ts.height)
            mediaManager.fetchVideoUrlAndCrop(for: asset, cropRect: resultCropRect, callback: callback)
        }
    }

    private func cancelExport() {
        mediaManager.clearExport()
        delegate?.libraryViewFinishedLoading()
        delegate?.didEndProcessing()
    }

    public func selectedMedia(photoCallback: @escaping (_ photo: YPMediaPhoto) -> Void,
                              videoCallback: @escaping (_ videoURL: YPMediaVideo) -> Void,
                              multipleItemsCallback: @escaping (_ items: [YPMediaItem]) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            if self.selection.isEmpty {
                return
            }
            let selectedAssets: [(asset: PHAsset, cropRect: CGRect?, selection: YPLibrarySelection)] = self.selection.map {
                guard let asset = PHAsset.fetchAssets(withLocalIdentifiers: [$0.assetIdentifier], options: PHFetchOptions()).firstObject else { fatalError() }
                return (asset, $0.cropRect, $0)
            }

            self.resumableQueue.stop()
            self.resumableQueue.onFailure = { [weak self] in
                self?.cancelExport()
            }

            self.delegate?.didStartProcessing()

            // Multiple selection
            if self.multipleSelectionEnabled && self.selection.count > 1 {
                // Check video length
                for asset in selectedAssets {
                    if self.fitsVideoLengthLimits(asset: asset.asset) == false {
                        self.cancelExport()
                        return
                    }
                }

                var orderedResults: [YPMediaItem?] = Array<YPMediaItem?>.init(repeating: nil, count: selectedAssets.count)

                for (index, asset) in selectedAssets.enumerated() {
                    var task: YPTask?
                    switch asset.asset.mediaType {
                    case .image:
                        task = YPTask(
                            start: { [weak self] handler in
                                guard let self = self else {
                                    handler.failure()
                                    return
                                }
                                self.fetchImageAndCrop(for: asset.asset, withCropRect: asset.cropRect) { image, exifMeta in
                                    let photo = YPMediaPhoto(image: image.resizedImageIfNeeded(), exifMeta: exifMeta, asset: asset.asset)
                                    if orderedResults.indices.contains(index) {
                                        orderedResults[index] = YPMediaItem.photo(p: photo)
                                    }
                                    handler.completion()
                                }
                            },
                            onRestart: {}
                        )

                    case .video:
                        task = YPTask(
                            start: { [weak self] handler in
                                guard let self = self else {
                                    handler.failure()
                                    return
                                }
                                self.changeVideoAsset(asset.asset, storedCropPosition: asset.selection)
                                self.checkVideoLengthAndCrop(for: asset.asset, withCropRect: asset.cropRect) { videoURL in
                                    let videoItem = YPMediaVideo(thumbnail: thumbnailFromVideoPath(videoURL),
                                                                 videoURL: videoURL, asset: asset.asset)
                                    if orderedResults.indices.contains(index) {
                                        orderedResults[index] = YPMediaItem.video(v: videoItem)
                                    }
                                    handler.completion()
                                }
                            },
                            onRestart: { [weak self] in
                                self?.mediaManager.clearExport()
                            }
                        )
                    default:
                        break
                    }
                    if let unwrappedTask = task {
                        self.resumableQueue.appendTask(unwrappedTask)
                    }
                }
                self.resumableQueue.onCompletion = {
                    DispatchQueue.main.async { [weak self] in
                        var resultMediaItems: [YPMediaItem] = []
                        for result in orderedResults {
                            if let resultUnwrapped = result {
                                resultMediaItems.append(resultUnwrapped)
                            }
                        }
                        multipleItemsCallback(resultMediaItems)
                        self?.delegate?.libraryViewFinishedLoading()
                        self?.delegate?.didEndProcessing()
                    }
                }
            } else {
                let asset = selectedAssets.first!.asset
                // Check video length
                if !self.fitsVideoLengthLimits(asset: asset) {
                    self.cancelExport()
                    return
                }

                switch asset.mediaType {
                case .video:
                    var videoURLWrapped: URL?
                    self.resumableQueue.appendTask(YPTask(
                        start: { [weak self] handler in
                            guard let self = self else {
                                handler.failure()
                                return
                            }
                            self.changeVideoAsset(asset, storedCropPosition: selectedAssets.first?.selection)
                            self.checkVideoLengthAndCrop(for: asset, callback: { videoURL in
                                videoURLWrapped = videoURL
                                handler.completion()
                            })
                        },
                        onRestart: { [weak self] in
                            self?.mediaManager.clearExport()
                        }
                    ))
                    self.resumableQueue.onCompletion = {
                        guard let videoURL = videoURLWrapped else {
                            return
                        }
                        DispatchQueue.main.async {
                            self.delegate?.libraryViewFinishedLoading()
                            let video = YPMediaVideo(thumbnail: thumbnailFromVideoPath(videoURL),
                                                     videoURL: videoURL, asset: asset)
                            self.delegate?.didEndProcessing()
                            videoCallback(video)
                        }
                    }
                case .image:
                    var imageWrapped: UIImage?
                    var exifMetaWrapped: [String: Any]?
                    self.resumableQueue.appendTask(YPTask(
                        start: { [weak self] handler in
                            guard let self = self else {
                                handler.failure()
                                return
                            }
                            self.fetchImageAndCrop(for: asset) { image, exifMeta in
                                imageWrapped = image
                                exifMetaWrapped = exifMeta
                                handler.completion()
                            }
                        },
                        onRestart: {}
                    ))
                    self.resumableQueue.onCompletion = {
                        guard let image = imageWrapped,
                            let exifMeta = exifMetaWrapped else {
                                return
                        }
                        DispatchQueue.main.async {
                            self.delegate?.libraryViewFinishedLoading()
                            let photo = YPMediaPhoto(image: image.resizedImageIfNeeded(),
                                                     exifMeta: exifMeta,
                                                     asset: asset)
                            self.delegate?.didEndProcessing()
                            photoCallback(photo)
                        }
                    }
                case .audio, .unknown:
                    return
                }
            }

            self.resumableQueue.start()
        }
    }

    // MARK: - TargetSize

    private func targetSize(for asset: PHAsset, cropRect: CGRect) -> CGSize {
        var width = (CGFloat(asset.pixelWidth) * cropRect.width).rounded(.toNearestOrEven)
        var height = (CGFloat(asset.pixelHeight) * cropRect.height).rounded(.toNearestOrEven)
        // round to lowest even number
        width = (width.truncatingRemainder(dividingBy: 2) == 0) ? width : width - 1
        height = (height.truncatingRemainder(dividingBy: 2) == 0) ? height : height - 1
        return CGSize(width: width, height: height)
    }

    // MARK: - Player

    func pausePlayer() {
        v.assetZoomableView.videoView.pause()
    }

    // MARK: - Deinit

    deinit {
        unregisterForLibraryChanges()
    }
}
