//
//  LFNotifications.swift
//  Cast
//
//  Created by Leonardo on 29/07/2015.
//  Copyright © 2015 Leonardo Faoro. All rights reserved.
//
import Cocoa

final class LFUserNotifications: NSObject {
    //---------------------------------------------------------------------------
    var unc = NSUserNotificationCenter.defaultUserNotificationCenter()
    var url: String?
    var timer: NSTimer!
    //---------------------------------------------------------------------------
    override init() {
        super.init()
        self.unc.delegate = self
    }
    //---------------------------------------------------------------------------
    func pushNotification(openURL url: String) -> Void {
        self.url = url
        let notification = NSUserNotification()
        notification.title = "Casted to gist.GitHub.com"
        notification.subtitle = url
        notification.informativeText = "Copied to your clipboard"
        notification.actionButtonTitle = "Open URL"
        notification.soundName = NSUserNotificationDefaultSoundName
        self.unc.deliverNotification(notification)
        self.startUserNotificationTimer() //IRC: calling from here doesn't work
    }
    //---------------------------------------------------------------------------
    func pushNotification(error error: String, description: String = "An error occured, please try again.") {
        let notification = NSUserNotification()
        notification.title = error
        notification.informativeText = description
        notification.soundName = NSUserNotificationDefaultSoundName
        notification.hasActionButton = false
        self.startUserNotificationTimer()
        self.unc.deliverNotification(notification)
    }
    //---------------------------------------------------------------------------
    func startUserNotificationTimer() {
        print(__FUNCTION__)
        self.timer = NSTimer
            .scheduledTimerWithTimeInterval(
                5.0,
                target: self,
                selector: "removeUserNotifcationsAction:",
                userInfo: nil,
                repeats: true)
    }
    //---------------------------------------------------------------------------
    func removeUserNotifcationsAction(timer: NSTimer) {
        print(__FUNCTION__)
        self.unc.removeAllDeliveredNotifications()
        timer.invalidate()
    }
    //---------------------------------------------------------------------------
}
typealias UserNotificationCenterDelegate = LFUserNotifications
extension UserNotificationCenterDelegate: NSUserNotificationCenterDelegate {
    //---------------------------------------------------------------------------
    func userNotificationCenter(center: NSUserNotificationCenter, didActivateNotification notification: NSUserNotification) {
        print("notification pressed")
        if let url = url {
            NSWorkspace.sharedWorkspace().openURL(NSURL(string: url)!)
        }
    } // executes an action whenever the notification is pressed
    //---------------------------------------------------------------------------
    func userNotificationCenter(center: NSUserNotificationCenter, shouldPresentNotification notification: NSUserNotification) -> Bool {
        return true
    } // forces the notification to display even when app is active app
    //---------------------------------------------------------------------------
}