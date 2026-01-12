import QtQuick 2.0
import org.kde.plasma.core 2.0 as PlasmaCore

import "LocaleFuncs.js" as LocaleFuncs
import "./calendars"

CalendarManager {
	id: upcomingEvents

	property int upcomingEventRange: 90 // minutes
	property int minutesBeforeReminding: plasmoid.configuration.eventReminderMinutesBefore // minutes

	// Persistent notification history cache to avoid duplicate notifications
	// Stored as JSON in plasmoid.configuration.notificationHistory
	// Format: { "eventUid": { "reminded": timestamp, "notified": timestamp, "shownAt": timestamp } }
	property var _notificationHistory: ({})
	property bool _historyLoaded: false
	property int _historyCacheMs: 24 * 60 * 60 * 1000 // Keep entries for 24 hours

	function loadNotificationHistory() {
		if (_historyLoaded) return
		try {
			var historyJson = plasmoid.configuration.notificationHistory || '{}'
			_notificationHistory = JSON.parse(historyJson)
			logger.debug('upcomingEvents: loaded notification history with', Object.keys(_notificationHistory).length, 'entries')
		} catch (e) {
			logger.debug('upcomingEvents: failed to parse notification history, starting fresh:', e)
			_notificationHistory = {}
		}
		_historyLoaded = true
		cleanupOldHistory()
	}

	function saveNotificationHistory() {
		try {
			plasmoid.configuration.notificationHistory = JSON.stringify(_notificationHistory)
		} catch (e) {
			logger.debug('upcomingEvents: failed to save notification history:', e)
		}
	}

	function cleanupOldHistory() {
		var now = Date.now()
		var cutoff = now - _historyCacheMs
		var removedCount = 0
		for (var eventUid in _notificationHistory) {
			var entry = _notificationHistory[eventUid]
			// Remove if the entry is older than 24 hours
			if (entry.shownAt < cutoff) {
				delete _notificationHistory[eventUid]
				removedCount++
			}
		}
		if (removedCount > 0) {
			logger.debug('upcomingEvents: cleaned up', removedCount, 'old notification history entries')
			saveNotificationHistory()
		}
	}

	function hasReminded(eventUid) {
		loadNotificationHistory()
		return !!(_notificationHistory[eventUid] && _notificationHistory[eventUid].reminded)
	}

	function hasNotified(eventUid) {
		loadNotificationHistory()
		return !!(_notificationHistory[eventUid] && _notificationHistory[eventUid].notified)
	}

	function markReminded(eventUid, expiresAt) {
		loadNotificationHistory()
		if (!_notificationHistory[eventUid]) {
			_notificationHistory[eventUid] = {}
		}
		_notificationHistory[eventUid].reminded = expiresAt
		_notificationHistory[eventUid].shownAt = Date.now()
		logger.debug('upcomingEvents: marked as reminded:', eventUid)
		saveNotificationHistory()
	}

	function markNotified(eventUid, expiresAt) {
		loadNotificationHistory()
		if (!_notificationHistory[eventUid]) {
			_notificationHistory[eventUid] = {}
		}
		_notificationHistory[eventUid].notified = expiresAt
		_notificationHistory[eventUid].shownAt = Date.now()
		logger.debug('upcomingEvents: marked as notified:', eventUid)
		saveNotificationHistory()
	}

	// Track active live-updating notifications
	// Key: eventUid, Value: { notificationId, eventItem, expiresAt }
	property var _activeNotifications: ({})

	function registerActiveNotification(eventUid, notificationId, eventItem, expiresAt, phase) {
		_activeNotifications[eventUid] = {
			notificationId: notificationId,
			eventItem: eventItem,
			expiresAt: expiresAt,
			phase: phase || LocaleFuncs.CountdownPhase.UPCOMING
		}
		logger.debug('upcomingEvents: registered active notification:', eventUid, 'id:', notificationId, 'phase:', phase)
	}

	function unregisterActiveNotification(eventUid) {
		if (_activeNotifications[eventUid]) {
			delete _activeNotifications[eventUid]
			logger.debug('upcomingEvents: unregistered active notification:', eventUid)
		}
	}

	function cleanupExpiredActiveNotifications() {
		var now = timeModel.currentTime.getTime()
		for (var eventUid in _activeNotifications) {
			if (_activeNotifications[eventUid].expiresAt < now) {
				unregisterActiveNotification(eventUid)
			}
		}
	}

	function updateActiveNotifications() {
		cleanupExpiredActiveNotifications()

		for (var eventUid in _activeNotifications) {
			var info = _activeNotifications[eventUid]
			var eventItem = info.eventItem
			var notificationId = info.notificationId
			var previousPhase = info.phase

			// Get current countdown info with phase
			var countdownInfo = LocaleFuncs.getEventCountdownInfo(eventItem.startDateTime, timeModel.currentTime)
			var currentPhase = countdownInfo.phase
			var summaryText = countdownInfo.text

			var bodyText = ''
			bodyText += eventItem.summary + '<br />'
			bodyText += LocaleFuncs.formatEventDuration(eventItem, {
				relativeDate: timeModel.currentTime,
				clock24h: appletConfig.clock24h,
			})

			// Detect phase transitions
			var phaseChanged = previousPhase !== currentPhase
			var isNowStarting = phaseChanged && currentPhase === LocaleFuncs.CountdownPhase.STARTING
			var isNowStarted = phaseChanged && currentPhase === LocaleFuncs.CountdownPhase.STARTED

			logger.debug('upcomingEvents: updating notification:', eventUid, 'summary:', summaryText,
				'phase:', previousPhase, '->', currentPhase, 'changed:', phaseChanged)

			var args = {
				appName: i18n("Event Calendar"),
				appIcon: "view-calendar-upcoming-events",
				summary: summaryText,
				body: bodyText,
				noWait: true,
				expireTimeout: 0, // Keep persistent
			}

			// On phase change, make the notification more prominent
			if (isNowStarting) {
				// Event is starting NOW - critical urgency, play sound multiple times, new popup
				// Re-generate text with emphasis
				summaryText = LocaleFuncs.formatEventCountdown(eventItem.startDateTime, timeModel.currentTime, true)
				args.summary = summaryText
				args.urgency = 'critical'
				args.soundFile = plasmoid.configuration.eventStartingSfxEnabled ? plasmoid.configuration.eventStartingSfxPath : ''
				args.loop = 3 // Play sound 3 times
				args.loopDelay = 0.8 // 0.8 seconds between plays
				// Don't use replaceId - create fresh notification to grab attention
				logger.debug('upcomingEvents: EVENT STARTING NOW - playing sound and creating prominent notification')
			} else if (isNowStarted) {
				// Event just started (first minute after start) - high urgency, play sound
				// Re-generate text with emphasis
				summaryText = LocaleFuncs.formatEventCountdown(eventItem.startDateTime, timeModel.currentTime, true)
				args.summary = summaryText
				args.urgency = 'critical'
				args.soundFile = plasmoid.configuration.eventStartingSfxEnabled ? plasmoid.configuration.eventStartingSfxPath : ''
				args.loop = 2 // Play sound 2 times
				args.loopDelay = 1.0
				// Don't use replaceId - create fresh notification
				logger.debug('upcomingEvents: EVENT STARTED - playing sound and creating prominent notification')
			} else {
				// Normal update - just replace quietly
				args.replaceId = notificationId
			}

			// Update the phase
			info.phase = currentPhase

			notificationManager.notify(args, function(actionId, newNotificationId) {
				// Update stored notification ID if it changed
				if (newNotificationId && newNotificationId !== notificationId) {
					info.notificationId = newNotificationId
				}
			})
		}
	}

	onFetchingData: {
		logger.debug('upcomingEvents.onFetchingData')

	}
	onAllDataFetched: {
		logger.debug('upcomingEvents.onAllDataFetched',
			upcomingEvents.dateMin.toISOString(),
			timeModel.currentTime.toISOString(),
			upcomingEvents.dateMax.toISOString()
		)
		// sendEventListNotification()
	}

	function isUpcomingEvent(eventItem) {
		// console.log(eventItem.startDateTime, timeModel.currentTime, eventItem.startDateTime - timeModel.currentTime, eventItem.summary)
		var dt = eventItem.startDateTime - timeModel.currentTime
		return -30 * 1000 <= dt && dt <= upcomingEventRange * 60 * 1000 // starting within 90 minutes
	}

	function isSameMinute(a, b) {
		return a.getFullYear() === b.getFullYear()
			&& a.getMonth() === b.getMonth()
			&& a.getDate() === b.getDate()
			&& a.getHours() === b.getHours()
			&& a.getMinutes() === b.getMinutes()
	}

	function getDeltaMinutes(a1, n) {
		var a2 = new Date(a1)
		a2.setMinutes(a2.getMinutes() + n)
		return a2
	}

	function shouldSendReminder(eventItem) {
		var reminderDateTime = getDeltaMinutes(timeModel.currentTime, minutesBeforeReminding)
		return isSameMinute(reminderDateTime, eventItem.startDateTime)
	}

	// Check if event is within reminder window but we haven't sent a reminder yet
	function isWithinReminderWindow(eventItem) {
		var now = timeModel.currentTime
		var msUntilStart = eventItem.startDateTime - now
		var reminderWindowMs = minutesBeforeReminding * 60 * 1000
		// Event starts within the reminder window (but not in the past)
		return msUntilStart > 0 && msUntilStart <= reminderWindowMs
	}

	function isEventStarting(eventItem) {
		return isSameMinute(timeModel.currentTime, eventItem.startDateTime) // starting this minute
	}

	function isEventInProgress(eventItem) {
		return eventItem.startDateTime <= timeModel.currentTime && timeModel.currentTime < eventItem.endDateTime
	}

	function filterEvents(predicate) {
		var events = []
		for (var calendarId in eventsByCalendar) {
			var calendar = eventsByCalendar[calendarId]
			calendar.items.forEach(function(eventItem, index, calendarEventList) {
				if (predicate(eventItem)) {
					events.push(eventItem)
				}
			})
		}
		return events
	}

	function formatHeading(heading) {
		var line = ''
		line += '<font size="4"><u>'
		line += heading
		line += '</u></font>'
		return line
	}

	function formatEvent(eventItem) {
		var line = ''
		line += '<font color="' + eventItem.backgroundColor + '">■</font> '
		line += '<b>' + eventItem.summary + ':</b> '
		line += LocaleFuncs.formatEventDuration(eventItem, {
			relativeDate: timeModel.currentTime,
			clock24h: appletConfig.clock24h,
		})
		return line
	}

	function formatEventList(events, heading) {
		var lines = []
		if (events.length > 0 && heading) {
			lines.push(formatHeading(heading))
		}
		events.forEach(function(eventItem) {
			lines.push(formatEvent(eventItem))
		})
		return lines
	}

	function addEventList(lines, heading, events) {
		var newLines = formatEventList(events, heading)
		lines.push.apply(lines, newLines)
	}

	function sendEventListNotification(args) {
		args = args || {}
		var eventsStarting = []
		var eventsInProgress = []
		var upcomingEvents = []
		for (var calendarId in eventsByCalendar) {
			var calendar = eventsByCalendar[calendarId]
			calendar.items.forEach(function(eventItem, index, calendarEventList) {
				if (isEventStarting(eventItem)) {
					eventsStarting.push(eventItem)
				} else if (isEventInProgress(eventItem)) {
					eventsInProgress.push(eventItem)
				} else if (isUpcomingEvent(eventItem)) {
					upcomingEvents.push(eventItem)
				}
			})
		}

		var lines = []
		if (typeof args.showEventsStarting !== "undefined" ? args.showEventsStarting : true) {
			addEventList(lines, i18n("Events Starting"), eventsStarting)
		}
		if (typeof args.showEventInProgress !== "undefined" ? args.showEventInProgress : true) {
			addEventList(lines, i18n("Events In Progress"), eventsInProgress)
		}
		if (typeof args.showUpcomingEvent !== "undefined" ? args.showUpcomingEvent : true) {
			addEventList(lines, i18n("Upcoming Events"), upcomingEvents)
		}

		if (lines.length >= 0) {
			var summary = i18n("Calendar")
			// var summary = lines.splice(0, 1)[0] // pop first item of array
			var bodyText = lines.join('<br />')
			bodyText = bodyText

			notificationManager.notify({
				appName: i18n("Event Calendar"),
				appIcon: "view-calendar-upcoming-events",
				summary: summary,
				body: bodyText,
			})
		}
	}

	function sendEventsStartingNotification() {
		sendEventListNotification({
			showEventInProgress: false,
			showUpcomingEvent: false,
		})
	}

	function sendEventReminderNotification(eventItem, minutes) {
		var eventUid = getEventUniqueId(eventItem)
		var countdownInfo = LocaleFuncs.getEventCountdownInfo(eventItem.startDateTime, timeModel.currentTime)
		var summaryText = countdownInfo.text
		var initialPhase = countdownInfo.phase

		var bodyText = ''
		bodyText += eventItem.summary + '<br />'
		bodyText += LocaleFuncs.formatEventDuration(eventItem, {
			relativeDate: timeModel.currentTime,
			clock24h: appletConfig.clock24h,
		})
		var args = {
			appName: i18n("Event Calendar"),
			appIcon: "view-calendar-upcoming-events",
			summary: summaryText,
			body: bodyText,
			soundFile: plasmoid.configuration.eventReminderSfxEnabled ? plasmoid.configuration.eventReminderSfxPath : '',
		}

		// For persistent notifications, use live-updating mode
		if (plasmoid.configuration.eventReminderNotificationPersistent) {
			args.expireTimeout = 0 // 0 = EXPIRES_NEVER in libnotify
			args.noWait = true // Don't block - we'll update this notification

			notificationManager.notify(args, function(actionId, notificationId) {
				if (notificationId) {
					// Register for live updates until the event ends
					registerActiveNotification(eventUid, notificationId, eventItem, eventItem.endDateTime.getTime(), initialPhase)
				}
			})
		} else {
			// Non-persistent notifications don't need updates
			notificationManager.notify(args)
		}
	}

	function sendEventStartingNotification(eventItem) {
		var eventUid = getEventUniqueId(eventItem)
		// Use emphasis for starting notifications
		var countdownInfo = LocaleFuncs.getEventCountdownInfo(eventItem.startDateTime, timeModel.currentTime, true)
		var summaryText = countdownInfo.text
		var initialPhase = countdownInfo.phase

		var bodyText = ''
		bodyText += eventItem.summary + '<br />'
		bodyText += LocaleFuncs.formatEventDuration(eventItem, {
			relativeDate: timeModel.currentTime,
			clock24h: appletConfig.clock24h,
		})

		// Check if there's an existing reminder notification we can reuse
		var existingNotification = _activeNotifications[eventUid]
		var existingNotificationId = existingNotification ? existingNotification.notificationId : 0

		var args = {
			appName: i18n("Event Calendar"),
			appIcon: "view-calendar-upcoming-events",
			summary: summaryText,
			body: bodyText,
			soundFile: plasmoid.configuration.eventStartingSfxEnabled ? plasmoid.configuration.eventStartingSfxPath : '',
			urgency: 'critical', // Event starting notifications are always critical
			loop: 3, // Play sound 3 times for starting notifications
			loopDelay: 0.8,
		}

		// Don't reuse existing notification - we want a fresh popup for "starting now"
		// This ensures the notification grabs attention

		// For persistent notifications, use live-updating mode
		if (plasmoid.configuration.eventStartingNotificationPersistent) {
			args.expireTimeout = 0 // 0 = EXPIRES_NEVER in libnotify
			args.noWait = true // Don't block - we'll update this notification

			notificationManager.notify(args, function(actionId, notificationId) {
				if (notificationId) {
					// Register for live updates until the event ends
					registerActiveNotification(eventUid, notificationId, eventItem, eventItem.endDateTime.getTime(), initialPhase)
				}
			})
		} else {
			// Non-persistent notifications don't need updates
			// If we had an active notification, unregister it
			if (existingNotificationId) {
				unregisterActiveNotification(eventUid)
			}
			notificationManager.notify(args)
		}
	}

	function getEventUniqueId(eventItem) {
		// Create a unique ID for tracking notifications
		return eventItem.calendarId + '_' + eventItem.id + '_' + eventItem.startDateTime.getTime()
	}

	function cleanupOldTracking() {
		// Clean up persistent notification history
		// This removes entries older than 24 hours
		cleanupOldHistory()
	}

	function checkForEventsStarting() {
		var eventsChecked = 0
		var notificationsSent = 0
		cleanupOldTracking()

		for (var calendarId in eventsByCalendar) {
			var calendar = eventsByCalendar[calendarId]
			calendar.items.forEach(function(eventItem, index, calendarEventList) {
				eventsChecked++
				var eventUid = getEventUniqueId(eventItem)

				if (isEventStarting(eventItem) || (isEventInProgress(eventItem) && !hasNotified(eventUid))) {
					var isStartingNow = isEventStarting(eventItem)
					logger.debug('upcomingEvents:', isStartingNow ? 'event starting now:' : 'event in progress (catch-up):', eventItem.summary, eventItem.startDateTime)
					if (plasmoid.configuration.eventStartingNotificationEnabled && !hasNotified(eventUid)) {
						sendEventStartingNotification(eventItem)
						markNotified(eventUid, eventItem.endDateTime.getTime()) // Track until event ends
						logger.debug('upcomingEvents: marked as notified:', eventUid)
						notificationsSent++
					} else if (hasNotified(eventUid)) {
						logger.debug('upcomingEvents: already notified for:', eventItem.summary)
					} else {
						logger.debug('upcomingEvents: eventStartingNotificationEnabled is disabled')
					}
				} else if (plasmoid.configuration.eventReminderNotificationEnabled && !hasReminded(eventUid)) {
					// Check both exact time and window-based reminders
					if (shouldSendReminder(eventItem)) {
						logger.debug('upcomingEvents: sending reminder for:', eventItem.summary, minutesBeforeReminding, 'minutes before')
						sendEventReminderNotification(eventItem, minutesBeforeReminding)
						markReminded(eventUid, eventItem.startDateTime.getTime())
						notificationsSent++
					} else if (isWithinReminderWindow(eventItem)) {
						// Event is within reminder window (e.g., added after reminder time passed)
						var msUntilStart = eventItem.startDateTime - timeModel.currentTime
						var minutesUntilStart = Math.ceil(msUntilStart / 60000)
						logger.debug('upcomingEvents: sending catch-up reminder for:', eventItem.summary, minutesUntilStart, 'minutes before')
						sendEventReminderNotification(eventItem, minutesUntilStart)
						markReminded(eventUid, eventItem.startDateTime.getTime())
						notificationsSent++
					}
				} else if (hasReminded(eventUid)) {
					// Already reminded, skip silently
				} else if (!plasmoid.configuration.eventReminderNotificationEnabled) {
					logger.debug('upcomingEvents: eventReminderNotificationEnabled is disabled')
				}
			})
		}
		if (eventsChecked > 0) {
			logger.debug('upcomingEvents: checked', eventsChecked, 'events, sent', notificationsSent, 'notifications')
		}
	}

	function tick() {
		logger.debug('upcomingEvents: tick at', timeModel.currentTime)
		checkForEventsStarting()
		updateActiveNotifications()
	}

	function syncWithEventModel() {
		// if data is from current month
		if (eventModel.dateMin <= timeModel.currentTime && timeModel.currentTime <= eventModel.dateMax) {
			logger.debug('syncing upcomingEvents with eventModel')
			upcomingEvents.clear()
			upcomingEvents.dateMin = eventModel.dateMin
			upcomingEvents.dateMax = eventModel.dateMax
			upcomingEvents.eventsByCalendar = eventModel.eventsByCalendar
			upcomingEvents.allDataFetched()
		}
	}

	Connections {
		target: eventModel
		onAllDataFetched: {
			logger.debug('upcomingEvents eventModel.onAllDataFetched', eventModel.dateMin, timeModel.currentTime, eventModel.dateMax)
			syncWithEventModel()
		}
		onEventAdded: {
			logger.debug('upcomingEvents eventModel.onEventAdded', calendarId)
			syncWithEventModel()
		}
		onEventCreated: {
			logger.debug('upcomingEvents eventModel.onEventCreated', calendarId)
			syncWithEventModel()
		}
		onEventUpdated: {
			logger.debug('upcomingEvents eventModel.onEventUpdated', calendarId, eventId)
			syncWithEventModel()
		}
		onEventRemoved: {
			logger.debug('upcomingEvents eventModel.onEventRemoved', calendarId, eventId)
			syncWithEventModel()
		}
		onEventDeleted: {
			logger.debug('upcomingEvents eventModel.onEventDeleted', calendarId, eventId)
			syncWithEventModel()
		}
	}

	Connections {
		target: timeModel
		onMinuteChanged: upcomingEvents.tick()
	}

	// On startup, clear active notifications since notification IDs are not valid across restarts
	// and don't re-register notifications for events we've already notified about
	Component.onCompleted: {
		// Load the persistent notification history
		loadNotificationHistory()
		
		// Clear _activeNotifications - notification IDs from previous session are invalid
		// Events that were already notified are tracked in _notificationHistory
		_activeNotifications = {}
	}
}
