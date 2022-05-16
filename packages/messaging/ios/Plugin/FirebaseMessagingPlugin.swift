import Foundation
import Capacitor

import FirebaseMessaging
import FirebaseInstallations
import FirebaseCore

/**
 * Please read the Capacitor iOS Plugin Development Guide
 * here: https://capacitorjs.com/docs/plugins/ios
 */
@objc(FirebaseMessagingPlugin)
public class FirebaseMessagingPlugin: CAPPlugin {
    private var implementation: FirebaseMessaging?

    public let tokenReceivedEvent = "tokenReceived"
    public let notificationReceivedEvent = "notificationReceived"
    public let notificationActionPerformedEvent = "notificationActionPerformed"
    public let errorTopicMissing = "topic must be provided."

    override public func load() {
        implementation = FirebaseMessaging(plugin: self, config: firebaseMessagingConfig())
        NotificationCenter.default.addObserver(self, selector: #selector(self.didRegisterForRemoteNotifications(notification:)), name: .capacitorDidRegisterForRemoteNotifications, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(self.didReceiveRemoteNotification(notification:)), name: Notification.Name.init("didReceiveRemoteNotification"), object: nil)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc override public func checkPermissions(_ call: CAPPluginCall) {
        implementation?.checkPermissions(completion: { permission in
            call.resolve([
                "receive": permission
            ])
        })
    }

    @objc override public func requestPermissions(_ call: CAPPluginCall) {
        implementation?.requestPermissions(completion: { granted, error in
            guard error == nil else {
                call.reject(error!.localizedDescription)
                return
            }
            call.resolve(["receive": granted ? "granted" : "denied"])
        })
    }

    @objc func getToken(_ call: CAPPluginCall) {
        implementation?.getToken(completion: { token, error in
            if let error = error {
                call.reject(error.localizedDescription)
                return
            }
            self.handleTokenReceived(token: token)
            var result = JSObject()
            result["token"] = token
            call.resolve(result)
        })
    }

    @objc func deleteToken(_ call: CAPPluginCall) {
        implementation?.deleteToken(completion: { error in
            if let error = error {
                call.reject(error.localizedDescription)
                return
            }
            call.resolve()
        })
    }

    @objc func getDeliveredNotifications(_ call: CAPPluginCall) {
        implementation?.getDeliveredNotifications(completion: { notifications in
            let notificationResults = notifications.map({ notification in
                return FirebaseMessagingHelper.createNotificationResult(notification: notification)
            })
            call.resolve([
                "notifications": notificationResults
            ])
        })
    }

    @objc func removeDeliveredNotifications(_ call: CAPPluginCall) {
        let ids = call.getArray("ids", String.self) ?? []
        implementation?.removeDeliveredNotifications(ids: ids)
        call.resolve()
    }

    @objc func removeAllDeliveredNotifications(_ call: CAPPluginCall) {
        implementation?.removeAllDeliveredNotifications()
        call.resolve()
    }

    @objc func subscribeToTopic(_ call: CAPPluginCall) {
        guard let topic = call.getString("topic") else {
            call.reject(errorTopicMissing)
            return
        }
        implementation?.subscribeToTopic(topic: topic, completion: { error in
            if let error = error {
                call.reject(error.localizedDescription)
                return
            }
            call.resolve()
        })
    }

    @objc func unsubscribeFromTopic(_ call: CAPPluginCall) {
        guard let topic = call.getString("topic") else {
            call.reject(errorTopicMissing)
            return
        }
        implementation?.unsubscribeFromTopic(topic: topic, completion: { error in
            if let error = error {
                call.reject(error.localizedDescription)
                return
            }
            call.resolve()
        })
    }

    func handleTokenReceived(token: String?) {
        var result = JSObject()
        result["token"] = token
        notifyListeners(tokenReceivedEvent, data: result)
    }

    func handleNotificationReceived(notification: UNNotification) {
        let notificationResult = FirebaseMessagingHelper.createNotificationResult(notification: notification)
        var result = JSObject()
        result["notification"] = notificationResult
        notifyListeners(notificationReceivedEvent, data: result)
    }
    
    func handleRemoteNotificationReceived(notification: NSNotification) {
        let notificationResult = FirebaseMessagingHelper.createNotificationResult(notification: notification)
        var result = JSObject()
        result["notification"] = notificationResult
        notifyListeners(notificationReceivedEvent, data: result)
    }

    func handleNotificationActionPerformed(response: UNNotificationResponse) {
        let notificationResult = FirebaseMessagingHelper.createNotificationResult(notification: response.notification)
        var result = JSObject()
        result["notification"] = notificationResult
        if response.actionIdentifier == UNNotificationDefaultActionIdentifier {
            result["actionId"] = "tap"
        } else if response.actionIdentifier == UNNotificationDismissActionIdentifier {
            result["actionId"] = "dismiss"
        } else {
            result["actionId"] = response.actionIdentifier
        }
        if let inputType = response as? UNTextInputNotificationResponse {
            result["inputValue"] = inputType.userText
        }
        notifyListeners(notificationActionPerformedEvent, data: result)
    }

    @objc private func didRegisterForRemoteNotifications(notification: NSNotification) {
        guard let deviceToken = notification.object as? Data else {
            return
        }
        Messaging.messaging().apnsToken = deviceToken
        let deviceTokenAsString = String(decoding: deviceToken, as: UTF8.self)
        self.handleTokenReceived(token: deviceTokenAsString)
    }
    
    @objc private func didReceiveRemoteNotification(notification: NSNotification) {
        implementation?.handleRemoteNotificationReceived(notification: notification)
    }

    private func firebaseMessagingConfig() -> FirebaseMessagingConfig {
        var config = FirebaseMessagingConfig()

        if let presentationOptions = getConfigValue("presentationOptions") as? [String] {
            config.presentationOptions = presentationOptions
        }

        return config
    }
}