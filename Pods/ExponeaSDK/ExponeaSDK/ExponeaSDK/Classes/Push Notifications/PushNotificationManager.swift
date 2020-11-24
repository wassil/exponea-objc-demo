//
//  PushNotificationManager.swift
//  ExponeaSDK
//
//  Created by Dominik Hadl on 25/05/2018.
//  Copyright © 2018 Exponea. All rights reserved.
//

import Foundation
import UserNotifications

public protocol PushNotificationManagerDelegate: class {
    func pushNotificationOpened(
        with action: ExponeaNotificationActionType,
        value: String?,
        extraData: [AnyHashable: Any]?
    )

    func silentPushNotificationReceived(extraData: [AnyHashable: Any]?)
}

public extension PushNotificationManagerDelegate {
    // default implementation is empty for compatibility
    func silentPushNotificationReceived(extraData: [AnyHashable: Any]?) {}
}

final class PushNotificationManager: NSObject, PushNotificationManagerType {
    /// The tracking manager used to track push events
    internal weak var trackingManager: TrackingManagerType?

    private let requirePushAuthorization: Bool
    private let appGroup: String? // used for sharing data across extensions, fx. for push delivered tracking
    private let tokenTrackFrequency: TokenTrackFrequency
    private let urlOpener: UrlOpenerType
    private var currentPushToken: String?
    private var lastTokenTrackDate: Date
    private var pushNotificationSwizzler: PushNotificationSwizzler?

    internal weak var delegate: PushNotificationManagerDelegate?

    var didReceiveSelfPushCheck: Bool = false

    let decoder: JSONDecoder = JSONDecoder.snakeCase

    init(trackingManager: TrackingManagerType,
         swizzlingEnabled: Bool,
         requirePushAuthorization: Bool,
         appGroup: String?,
         tokenTrackFrequency: TokenTrackFrequency,
         currentPushToken: String?,
         lastTokenTrackDate: Date?,
         urlOpener: UrlOpenerType) {
        self.appGroup = appGroup
        self.trackingManager = trackingManager
        self.tokenTrackFrequency = tokenTrackFrequency
        self.currentPushToken = currentPushToken
        self.lastTokenTrackDate = lastTokenTrackDate ?? .distantPast
        self.urlOpener = urlOpener
        self.requirePushAuthorization = requirePushAuthorization
        super.init()

        if swizzlingEnabled {
            pushNotificationSwizzler = PushNotificationSwizzler(self)
            pushNotificationSwizzler?.addAutomaticPushTracking()
        }
        checkForDeliveredPushMessages()
        processStoredPushOpens()
        verifyPushStatusAndTrackPushToken()

        // We need to register for silent push notifications, but let's only do it when visible pushes are allowed
        // so we don't track push token to exponea without permission to show
        // push notifications unless enabled by developer in configuration
        if requirePushAuthorization {
            UNAuthorizationStatusProvider.current.isAuthorized { authorized in
                if authorized {
                    DispatchQueue.main.async {
                        UIApplication.shared.registerForRemoteNotifications()
                    }
                }
            }
        } else {
            DispatchQueue.main.async {
                UIApplication.shared.registerForRemoteNotifications()
            }
        }
    }

    deinit {
        pushNotificationSwizzler?.removeAutomaticPushTracking()
    }

    // MARK: - Actions -

    func handlePushOpened(userInfoObject: AnyObject?, actionIdentifier: String?) {
        Exponea.shared.executeSafely {
            handlePushOpenedUnsafe(userInfoObject: userInfoObject, actionIdentifier: actionIdentifier)
        }
    }

    func handlePushOpenedUnsafe(userInfoObject: AnyObject?, actionIdentifier: String?) {
        guard let pushOpenedData = PushNotificationParser.parsePushOpened(
            userInfoObject: userInfoObject,
            actionIdentifier: actionIdentifier
        ) else {
            return
        }
        handlePushOpenedUnsafe(pushOpenedData: pushOpenedData)
    }

    func handlePushOpenedUnsafe(pushOpenedData: PushOpenedData) {
        if case .selfCheck = pushOpenedData.actionType {
            didReceiveSelfPushCheck = true
            return
        }

        do {
            try trackingManager?.track(pushOpenedData.eventType, with: pushOpenedData.eventData)
        } catch {
            Exponea.logger.log(.error, message: "Error tracking push opened: \(error.localizedDescription)")
        }

        if pushOpenedData.silent {
            delegate?.silentPushNotificationReceived(extraData: pushOpenedData.extraData)
        } else {
            // save campaign to be added to session start
            Exponea.shared.trackCampaignData(data: pushOpenedData.campaignData, timestamp: nil)

            // Notify the delegate
            delegate?.pushNotificationOpened(
                with: pushOpenedData.actionType,
                value: pushOpenedData.actionValue,
                extraData: pushOpenedData.extraData
            )

            switch pushOpenedData.actionType {
            case .none, .openApp, .selfCheck:
                // No need to do anything, app was opened automatically
                break

            case .browser:
                if let value = pushOpenedData.actionValue {
                    urlOpener.openBrowserLink(value)
                }

            case .deeplink:
                if let value = pushOpenedData.actionValue {
                    urlOpener.openDeeplink(value)
                }
            }
        }
    }

    func handlePushTokenRegistered(dataObject: AnyObject?) {
        Exponea.shared.executeSafely {
            handlePushTokenRegisteredUnsafe(dataObject: dataObject)
        }
    }

    func handlePushTokenRegisteredUnsafe(dataObject: AnyObject?) {
        guard let tokenData = dataObject as? Data else {
            return
        }
        UNAuthorizationStatusProvider.current.isAuthorized { authorized in
            if !self.requirePushAuthorization || authorized {
                self.currentPushToken = tokenData.tokenString
                self.trackCurrentPushToken(isAuthorized: authorized)
            }
        }
    }

    static func storePushOpened(userInfoObject: AnyObject?, actionIdentifier: String?) {
        guard let userDefaults = UserDefaults(suiteName: Constants.General.userDefaultsSuite),
              let pushOpenedData = PushNotificationParser.parsePushOpened(
                  userInfoObject: userInfoObject,
                  actionIdentifier: actionIdentifier
              ) else {
            return
        }
        if let serialized = pushOpenedData.serialize() {
            var opened = userDefaults.array(forKey: Constants.General.openedPushUserDefaultsKey) ?? []
            opened.append(serialized)
            userDefaults.set(opened, forKey: Constants.General.openedPushUserDefaultsKey)
        }
    }

    func processStoredPushOpens() {
        let userDefaults = UserDefaults(suiteName: Constants.General.userDefaultsSuite)
        guard let array = userDefaults?.array(forKey: Constants.General.openedPushUserDefaultsKey) else {
            Exponea.logger.log(.verbose, message: "No opened push to track present in shared app group.")
            return
        }

        guard let dataArray = array as? [Data] else {
            Exponea.logger.log(.warning, message: "Opened push data present in shared group but incorrect type.")
            return
        }

        for data in dataArray {
            guard let pushOpenedData = PushOpenedData.deserialize(from: data) else {
                Exponea.logger.log(.warning, message: "Cannot deserialize stored opened push data.")
                continue
            }
            Exponea.logger.log(.verbose, message: "Handling saved opened push notification.")
            handlePushOpenedUnsafe(pushOpenedData: pushOpenedData)
        }
        userDefaults?.removeObject(forKey: Constants.General.openedPushUserDefaultsKey)
    }

    internal func checkForDeliveredPushMessages() {
        guard let appGroup = appGroup else {
            Exponea.logger.log(.verbose, message: "No app group was setup, push delivered tracking is disabled.")
            return
        }

        let userDefaults = UserDefaults(suiteName: appGroup)
        guard let array = userDefaults?.array(forKey: Constants.General.deliveredPushUserDefaultsKey) else {
            Exponea.logger.log(.verbose, message: "No delivered push to track present in shared app group.")
            return
        }

        guard let dataArray = array as? [Data] else {
            Exponea.logger.log(.warning, message: "Delivered push data present in shared group but incorrect type.")
            return
        }

        // Process notifications
        for data in dataArray {
            guard let notification = NotificationData.deserialize(from: data) else {
                Exponea.logger.log(.warning, message: "Cannot deserialize stored delivered push data.")
                continue
            }

            // Create payload
            var properties: [String: JSONValue] = notification.properties
            properties["status"] = .string("delivered")

            // Track the event
            do {
                if let customEventType = notification.eventType,
                   !customEventType.isEmpty,
                   customEventType != Constants.EventTypes.pushDelivered {
                    try trackingManager?.track(
                        .customEvent,
                        with: [
                            .eventType(customEventType),
                            .properties(properties),
                            .timestamp(notification.timestamp.timeIntervalSince1970)
                        ]
                    )
                } else {
                    try trackingManager?.track(
                        .pushDelivered,
                        with: [.properties(properties), .timestamp(notification.timestamp.timeIntervalSince1970)]
                    )
                }
            } catch {
                Exponea.logger.log(.error, message: "Error tracking push opened: \(error.localizedDescription)")
            }
        }

        // Clear after all is processed
        userDefaults?.removeObject(forKey: Constants.General.deliveredPushUserDefaultsKey)
    }

    func verifyPushStatusAndTrackPushToken() {
        UNAuthorizationStatusProvider.current.isAuthorized { authorized in
            if self.requirePushAuthorization && !authorized {
                if self.currentPushToken != nil {
                    self.currentPushToken = nil
                    self.trackCurrentPushToken(isAuthorized: authorized)
                }
            } else {
                self.checkForPushTokenFrequency(isAuthorized: authorized)
            }
        }
    }

    private func trackCurrentPushToken(isAuthorized authorized: Bool) {
        do {
            try trackingManager?.track(
                .registerPushToken,
                with: [.pushNotificationToken(token: currentPushToken, authorized: authorized)]
            )
        } catch {
            Exponea.logger.log(.error, message: "Error tracking current push token. \(error.localizedDescription)")
        }
    }

    private func checkForPushTokenFrequency(isAuthorized authorized: Bool) {
        switch tokenTrackFrequency {
        case .everyLaunch:
            // Track push token
            lastTokenTrackDate = .init()
            trackCurrentPushToken(isAuthorized: authorized)

        case .daily:
            // Compare last track dates, if equal or more than a day, track
            let now = Date()
            if abs(lastTokenTrackDate.timeIntervalSince(now)) >= 60 * 60 * 24 {
                lastTokenTrackDate = now
                trackCurrentPushToken(isAuthorized: authorized)
            }

        case .onTokenChange:
            // nothing to do
            break
        }
    }
}

extension PushNotificationManager {
    func applicationDidBecomeActive() {
        checkForDeliveredPushMessages()
        // we don't have to check for opened pushes here, Exponea SDK was initialized so it will be tracked directly
        verifyPushStatusAndTrackPushToken()
    }
}
