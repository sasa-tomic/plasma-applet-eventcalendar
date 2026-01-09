import QtQuick 2.0
import org.kde.plasma.core 2.0 as PlasmaCore

import "./lib"

QtObject {
	id: notificationManager

	property var executable: ExecUtil { id: executable }

	// Parse notification ID from stdout (format: "id:123\n...")
	function parseNotificationId(stdout) {
		var match = stdout.match(/^id:(\d+)/)
		if (match) {
			return parseInt(match[1], 10)
		}
		return 0
	}

	function notify(args, callback) {
		logger.debugJSON('NotificationMananger.notify', args)
		args.sound = args.sound || args.soundFile

		var cmd = [
			'python3',
			plasmoid.file("", "scripts/notification.py"),
		]
		if (args.appName) {
			cmd.push('--app-name', args.appName)
		}
		if (args.appIcon) {
			cmd.push('--icon', args.appIcon)
		}
		if (args.sound) {
			cmd.push('--sound', args.sound)
			if (args.loop && args.loop > 1) {
				cmd.push('--loop', args.loop)
				if (args.loopDelay) {
					cmd.push('--loop-delay', args.loopDelay)
				}
			}
		}
		if (typeof args.expireTimeout !== 'undefined') {
			cmd.push('--timeout', args.expireTimeout)
		}
		if (args.actions) {
			for (var i = 0; i < args.actions.length; i++) {
				var action = args.actions[i]
				cmd.push('--action', action)
			}
		}
		// Support for updating existing notifications
		if (args.replaceId) {
			cmd.push('--replace-id', args.replaceId)
		}
		// Non-blocking mode for updateable notifications
		if (args.noWait) {
			cmd.push('--no-wait')
		}
		// Urgency level (low, normal, critical)
		if (args.urgency) {
			cmd.push('--urgency', args.urgency)
		}
		cmd.push('--metadata', '' + Date.now())
		var sanitizedSummary = executable.sanitizeString(args.summary)
		var sanitizedBody = executable.sanitizeString(args.body)
		cmd.push(sanitizedSummary)
		cmd.push(sanitizedBody)
		executable.exec(cmd, function(cmd, exitCode, exitStatus, stdout, stderr) {
			var notificationId = parseNotificationId(stdout)
			var actionId = stdout.replace(/^id:\d+\n?/, '').replace('\n', ' ').trim()
			if (typeof callback === 'function') {
				callback(actionId, notificationId)
			}
		})
	}
}
