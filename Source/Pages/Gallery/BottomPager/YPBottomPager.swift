//
//  YPBottomPager.swift
//  YPImagePicker
//
//  Created by Sacha Durand Saint Omer on 27/10/16.
//  Copyright © 2016 Yummypets. All rights reserved.
//

import Stevia
import UIKit

protocol YPBottomPagerDelegate: class {
    func pagerScrollViewDidScroll(_ scrollView: UIScrollView)
    func pagerDidSelectController(_ vc: UIViewController)
}

open class YPBottomPager: UIViewController, UIScrollViewDelegate {
    weak var delegate: YPBottomPagerDelegate?
    var controllers = [UIViewController]() { didSet { reload() } }

    var v = YPBottomPagerView()

    var currentPage = 0

    var currentController: UIViewController {
        return controllers[currentPage]
    }

    open override func loadView() {
        automaticallyAdjustsScrollViewInsets = false
        v.scrollView.delegate = self
        view = v
    }

    public func scrollViewDidScroll(_ scrollView: UIScrollView) {
        delegate?.pagerScrollViewDidScroll(scrollView)
    }

    public func scrollViewWillEndDragging(_: UIScrollView,
                                          withVelocity _: CGPoint,
                                          targetContentOffset: UnsafeMutablePointer<CGPoint>) {
        if !v.header.menuItems.isEmpty {
            let menuIndex = (targetContentOffset.pointee.x + v.frame.size.width) / v.frame.size.width
            let selectedIndex = Int(round(menuIndex)) - 1
            if selectedIndex != currentPage {
                selectPage(selectedIndex)
            }
        }
    }

    func reload() {
        let viewWidth: CGFloat = UIScreen.main.bounds.width
        for (index, c) in controllers.enumerated() {
            c.willMove(toParent: self)
            addChild(c)
            let x: CGFloat = CGFloat(index) * viewWidth
            v.scrollView.sv(c.view)
            c.didMove(toParent: self)
            c.view.steviaLeft(x)
            c.view.steviaTop(0)
            c.view.steviaWidth(viewWidth)
            equal(heights: c.view, v.scrollView)
        }

        let scrollableWidth: CGFloat = CGFloat(controllers.count) * CGFloat(viewWidth)
        v.scrollView.contentSize = CGSize(width: scrollableWidth, height: 0)

        // Build headers
        for (index, c) in controllers.enumerated() {
            let menuItem = YPMenuItem()
            let title = YPImagePickerConfiguration.shared.bottomMenuLabelUppercased
                ? c.title?.uppercased()
                : c.title?.capitalized
            menuItem.textLabel.text = title
            menuItem.button.tag = index
            menuItem.button.addTarget(self,
                                      action: #selector(tabTapped(_:)),
                                      for: .touchUpInside)
            v.header.menuItems.append(menuItem)
        }

        let currentMenuItem = v.header.menuItems[0]
        currentMenuItem.select()
        v.header.refreshMenuItems()
    }

    @objc
    func tabTapped(_ b: UIButton) {
        showPage(b.tag)
    }

    func showPage(_ page: Int, animated: Bool = true) {
        let x = CGFloat(page) * UIScreen.main.bounds.width
        v.scrollView.setContentOffset(CGPoint(x: x, y: 0), animated: animated)
        selectPage(page)
    }

    func selectPage(_ page: Int) {
        guard page != currentPage && page >= 0 && page < controllers.count else {
            return
        }
        currentPage = page
        // select menu item and deselect others
        for (i, mi) in v.header.menuItems.enumerated() {
            if i == page {
                mi.select()
                v.header.lineViewContainer.moveLineTo(index: i)
            } else {
                mi.deselect()
            }
        }
        delegate?.pagerDidSelectController(controllers[page])
    }

    func startOnPage(_ page: Int) {
        currentPage = page
        let x = CGFloat(page) * UIScreen.main.bounds.width
        v.scrollView.setContentOffset(CGPoint(x: x, y: 0), animated: false)
        // select menu item and deselect others
        for mi in v.header.menuItems {
            mi.deselect()
        }
        let currentMenuItem = v.header.menuItems[page]
        currentMenuItem.select()
    }
}
