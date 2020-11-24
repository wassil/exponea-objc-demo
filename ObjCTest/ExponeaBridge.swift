//
//  ExponeaBridge.swift
//  ObjCTest
//
//  Created by Juraj Dudak on 24/11/2020.
//

import Foundation
import ExponeaSDK

class ExponeaBridge: NSObject {
    private static var pushDelegate = ExponeaPushDelegate()

    @objc static func configureExponea() {
        Exponea.shared.configure(
            Exponea.ProjectSettings(
                projectToken: "f3a64f78-c27c-11e9-8a72-f69eea2c8d5c",
                authorization: .token("6aro4v392ekj8lnwbzkupcrzccdi6lc71461n128vhma6m0zqy1n33c4wgbgsvg1"),
                baseUrl: "https://cloud-api.exponea.com",
                projectMapping: nil
            ),
            pushNotificationTracking: .enabled(appGroup: "group.com.exponea.ExponeaSDK-Example2")
        )
        UNUserNotificationCenter.current().delegate = pushDelegate
    }

    @objc static func checkPushSetup() {
        Exponea.shared.checkPushSetup = true
    }

    @objc static func gotToken(token: Data) {
        Exponea.shared.handlePushNotificationToken(deviceToken: token)
    }

    @objc static func onNotification(userInfo: [AnyHashable : Any], actionIdentifier: String?) {
        Exponea.shared.handlePushNotificationOpened(userInfo: userInfo, actionIdentifier: actionIdentifier)
    }

    @objc static func onNotification(userInfo: [AnyHashable : Any]) {
        Exponea.shared.handlePushNotificationOpened(userInfo: userInfo)
    }
}

class ExponeaPushDelegate: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        Exponea.shared.handlePushNotificationOpened(response: response)
        completionHandler()
    }
}
