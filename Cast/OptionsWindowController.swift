//
//  Created by Leonardo on 10/17/15.
//  Copyright © 2015 Leonardo Faoro. All rights reserved.
//

import Cocoa

class OptionsWindowController: NSWindowController {

	override var windowNibName: String? {
		return "OptionsWindow"
	}

	@IBOutlet weak var loginButton: NSButton!
	@IBOutlet weak var secretGistButton: NSButton!

	override func windowDidLoad() {
		super.windowDidLoad()

		updateLoginButton()

	}

	@IBAction func secretGistButtonAction(sender: NSButton) {

		userDefaults[.GistIsPublic] = sender.state == NSOnState
	}

	@IBAction func loginButtonAction(sender: NSButton) {

		switch sender.title {
		case "Login":
			app.oauth.authorize()

		case "Logout":
			if let error = OAuthClient.revoke() {
				app.userNotification.pushNotification(error: error.localizedDescription)
			} else {
				app.userNotification.pushNotification(error: "GitHub Authentication",
					description: "API key revoked internally")

				updateLoginButton()
			}

		default: return
		}
	}

	func updateLoginButton() {

		if OAuthClient.getToken() != nil {
			loginButton.title = "Logout"
		} else {
			loginButton.title = "Login"
		}
	}

	@IBAction func urlShortenerSegmentedControlAction(sender: NSSegmentedCell) {
		print(__FUNCTION__)
		
		userDefaults[.Shorten] = sender.selectedSegment
	}

	@IBAction func gistServiceControl(sender: NSSegmentedControl) {
		print(__FUNCTION__)

		enum GistSegments: Int {
			case GitHub = 0, PasteBin, NoPaste, TinyPaste
		}

		switch GistSegments(rawValue: sender.selectedSegment)! {
		case .GitHub, .PasteBin: secretGistButton.enabled = true
		default: secretGistButton.enabled = false
		}

	}

	@IBAction func openTwitterProfile(sender: NSButton) {

		NSWorkspace.sharedWorkspace().openURL(NSURL(string: "https://twitter.com/leonarth")!)
	}
	
}
