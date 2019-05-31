//
//  YPCameraView.swift
//  YPImgePicker
//
//  Created by Sacha Durand Saint Omer on 2015/11/14.
//  Copyright © 2015 Yummypets. All rights reserved.
//

import UIKit

class YPCameraView: UIView, UIGestureRecognizerDelegate {
    let focusView = UIView(frame: CGRect(x: 0, y: 0, width: 90, height: 90))
    let previewViewContainer = UIView()
    let buttonsContainer = UIView()
    let flipButton = UIButton()
    let shotButton = UIButton()
    let flashButton = UIButton()
    let timeElapsedLabel = UILabel()
    let progressBar = UIProgressView()

    convenience init(overlayView: UIView? = nil) {
        self.init(frame: .zero)

        if let overlayView = overlayView {
            // View Hierarchy
            sv(
                previewViewContainer,
                overlayView,
                progressBar,
                timeElapsedLabel,
                buttonsContainer.sv(
                    flashButton,
                    flipButton,
                    shotButton
                )
            )
        } else {
            // View Hierarchy
            sv(
                previewViewContainer,
                progressBar,
                timeElapsedLabel,
                buttonsContainer.sv(
                    flashButton,
                    flipButton,
                    shotButton
                )
            )
        }

        // Layout
        let isIphone4 = UIScreen.main.bounds.height == 480
        let sideMargin: CGFloat = isIphone4 ? 20 : 0
        layout(
            0,
            |-sideMargin - previewViewContainer - sideMargin-|,
            -2,
            |progressBar|,
            0,
            |buttonsContainer|,
            0
        )
        previewViewContainer.heightEqualsWidth()

        overlayView?.followEdges(previewViewContainer)

        |-(30 + sideMargin) - flashButton.size(48)
        flashButton.centerVertically()

        flipButton.size(48) - (30 + sideMargin)-|
        flipButton.centerVertically()

        timeElapsedLabel - (15 + sideMargin)-|
        timeElapsedLabel.Top == previewViewContainer.Top + 15

        shotButton.centerVertically()
        shotButton.size(84).centerHorizontally()

        // Style
        backgroundColor = YPConfig.colors.photoVideoScreenBackground
        previewViewContainer.backgroundColor = .black
        timeElapsedLabel.style { l in
            l.textColor = .white
            l.text = "00:00"
            l.isHidden = true
            l.font = .monospacedDigitSystemFont(ofSize: 13, weight: UIFont.Weight.medium)
        }
        progressBar.style { p in
            p.trackTintColor = .clear
            p.tintColor = YPImagePickerConfiguration.shared.colors.tintColor
        }
        flashButton.backgroundColor = Asset.darkNine.color
        flashButton.setImage(YPConfig.icons.flashOffIcon, for: .normal)
        flashButton.layer.cornerRadius = 24
        flashButton.clipsToBounds = true
        flipButton.backgroundColor = Asset.darkNine.color
        flipButton.setImage(YPConfig.icons.loopIcon, for: .normal)
        flipButton.layer.cornerRadius = 24
        flipButton.clipsToBounds = true
        shotButton.setImage(YPConfig.icons.capturePhotoImage, for: .normal)
    }
}
