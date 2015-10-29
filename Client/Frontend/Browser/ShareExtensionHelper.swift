/* This Source Code Form is subject to the terms of the Mozilla Public
* License, v. 2.0. If a copy of the MPL was not distributed with this
* file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import Foundation
import Shared

private let log = Logger.browserLogger

class ShareExtensionHelper: NSObject {
    private let selectedTab: Browser

    private var onePasswordExtensionItem: NSExtensionItem!

    init(tab: Browser) {
        selectedTab = tab
    }

    func createActivityViewController(completionHandler: () -> Void) -> UIActivityViewController {
        let printInfo = UIPrintInfo(dictionary: nil)
        let url = selectedTab.url!
        printInfo.jobName = url.absoluteString
        printInfo.outputType = .General
        let renderer = BrowserPrintPageRenderer(browser: selectedTab)

        let activityItems = [printInfo, renderer, selectedTab.title ?? url.absoluteString, self]

        let activityViewController = UIActivityViewController(activityItems: activityItems, applicationActivities: nil)

        // Hide 'Add to Reading List' which currently uses Safari.
        // Also hide our own View Later… after all, you're in the browser!
        let viewLater = NSBundle.mainBundle().bundleIdentifier! + ".ViewLater"
        activityViewController.excludedActivityTypes = [
            UIActivityTypeAddToReadingList,
            viewLater,                        // Doesn't work: rdar://19430419
        ]

        // This needs to be ready by the time the share menu has been displayed and
        // activityViewController(activityViewController:, activityType:) is called,
        // which is after the user taps the button. So a million cycles away.
        if (isPasswordManagerAvailable()) {
            findLoginExtensionItem()
        }

        activityViewController.completionWithItemsHandler = { activityType, completed, returnedItems, activityError in
            log.debug("Selected activity type: \(activityType).")
            if !completed {
                return
            }

            if self.isPasswordManagerActivityType(activityType) {
                if let logins = returnedItems {
                    self.fillPasswords(logins)
                }
            } else {
                // Code for other custom activity types
            }

            completionHandler()
        }
        return activityViewController
    }
}

extension ShareExtensionHelper: UIActivityItemSource {
    func activityViewControllerPlaceholderItem(activityViewController: UIActivityViewController) -> AnyObject {
        return selectedTab.displayURL!
    }

    func activityViewController(activityViewController: UIActivityViewController, itemForActivityType activityType: String) -> AnyObject? {
        if isPasswordManagerActivityType(activityType) {
            // Return the 1Password extension item
            return onePasswordExtensionItem
        } else {
            // Return the selected tab's URL
            return selectedTab.displayURL!
        }
    }

    func activityViewController(activityViewController: UIActivityViewController, dataTypeIdentifierForActivityType activityType: String?) -> String {
        // Because of our UTI declaration, this UTI now satisfies both the 1Password Extension and the usual NSURL for Share extensions.
        return "org.appextension.fill-browser-action"
    }
}

private extension ShareExtensionHelper {
    func isPasswordManagerAvailable() -> Bool {
        return OnePasswordExtension.sharedExtension().isAppExtensionAvailable()
    }

    func isPasswordManagerActivityType(activityType: String?) -> Bool {
        if (!isPasswordManagerAvailable()) {
            return false
        }
        let isOnePassword = OnePasswordExtension.sharedExtension().isOnePasswordExtensionActivityType(activityType)

        // If your extension's bundle identifier contains "password"
        let isPasswordManager = activityType!.rangeOfString("pass") != nil

        // If your extension's bundle identifier does not contain "password", simply submit a pull request by adding your bundle idenfidier.
        let isAnotherPasswordManager = (activityType == "bundle.identifier.for.another.password.manager")
        return isOnePassword || isPasswordManager || isAnotherPasswordManager
    }

    func findLoginExtensionItem() {
        // Add 1Password to share sheet
        OnePasswordExtension.sharedExtension().createExtensionItemForWebView(selectedTab.webView!, completion: {(extensionItem, error) -> Void in
            if extensionItem == nil {
                log.error("Failed to create the password manager extension item: \(error).")
                return
            }

            // Set the 1Password extension item property
            self.onePasswordExtensionItem = extensionItem
        })
    }

    func fillPasswords(returnedItems: [AnyObject]) {
        OnePasswordExtension.sharedExtension().fillReturnedItems(returnedItems, intoWebView: self.selectedTab.webView!, completion: { (success, returnedItemsError) -> Void in
            if !success {
                log.error("Failed to fill item into webview: \(returnedItemsError).")
            }
        })
    }
}