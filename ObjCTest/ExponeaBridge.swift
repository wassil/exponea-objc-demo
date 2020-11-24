//
//  ExponeaBridge.swift
//  ObjCTest
//
//  Created by Juraj Dudak on 24/11/2020.
//

import Foundation
import ExponeaSDK

class ExponeaBridge: NSObject {
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
    }

    @objc static func checkPushSetup() {
        Exponea.shared.checkPushSetup = true
    }
}
