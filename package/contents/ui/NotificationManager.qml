import QtQuick 2.0
import org.kde.plasma.core 2.0 as PlasmaCore

import "./lib"

QtObject {
	id: notificationManager

	property var executable: ExecUtil { id: executable }

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
		// Non-blocking mode - show notification and exit without waiting for user interaction
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
			if (typeof callback === 'function') {
				// Parse action ID from output (remove notification ID prefix if present)
				var actionId = stdout.replace(/^id:\d+\n?/, '').replace('\n', ' ').trim()
				callback(actionId)
			}
		})
	}
}
