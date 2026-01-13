import QtQuick 2.0
import org.kde.plasma.core 2.0 as PlasmaCore

import "LocaleFuncs.js" as LocaleFuncs
import "./calendars"

CalendarManager {
	id: upcomingEvents

	property int upcomingEventRange: 90 // minutes
	property int minutesBeforeReminding: plasmoid.configuration.eventReminderMinutesBefore // minutes

	// Persistent notification history to track which events have been notified
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

	function getEventUniqueId(eventItem) {
		return eventItem.calendarId + '_' + eventItem.id + '_' + eventItem.startDateTime.getTime()
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
	}

	function isUpcomingEvent(eventItem) {
		var dt = eventItem.startDateTime - timeModel.currentTime
		return -30 * 1000 <= dt && dt <= upcomingEventRange * 60 * 1000
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

	function isWithinReminderWindow(eventItem) {
		var now = timeModel.currentTime
		var msUntilStart = eventItem.startDateTime - now
		var reminderWindowMs = minutesBeforeReminding * 60 * 1000
		return msUntilStart > 0 && msUntilStart <= reminderWindowMs
	}

	function isEventStarting(eventItem) {
		return isSameMinute(timeModel.currentTime, eventItem.startDateTime)
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
		var upcomingEventsList = []
		for (var calendarId in eventsByCalendar) {
			var calendar = eventsByCalendar[calendarId]
			calendar.items.forEach(function(eventItem, index, calendarEventList) {
				if (isEventStarting(eventItem)) {
					eventsStarting.push(eventItem)
				} else if (isEventInProgress(eventItem)) {
					eventsInProgress.push(eventItem)
				} else if (isUpcomingEvent(eventItem)) {
					upcomingEventsList.push(eventItem)
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
			addEventList(lines, i18n("Upcoming Events"), upcomingEventsList)
		}

		if (lines.length >= 0) {
			var summary = i18n("Calendar")
			var bodyText = lines.join('<br />')

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

	// Send a reminder notification for an upcoming event
	// This is sent once at T-X minutes and not updated
	function sendEventReminderNotification(eventItem, minutes) {
		var summaryText = LocaleFuncs.formatEventCountdown(eventItem.startDateTime, timeModel.currentTime)

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

		// Persistent notifications stay until user closes them or event ends
		if (plasmoid.configuration.eventReminderNotificationPersistent) {
			args.expireTimeout = 0 // 0 = EXPIRES_NEVER in libnotify
			args.noWait = true // Don't block - just show and exit
		}

		notificationManager.notify(args)
		logger.debug('upcomingEvents: sent reminder notification for:', eventItem.summary)
	}

	// Send a "starting now" notification for an event
	// This is sent once at T-0 and not updated
	function sendEventStartingNotification(eventItem) {
		// Use emphasis for starting notifications
		var summaryText = LocaleFuncs.formatEventCountdown(eventItem.startDateTime, timeModel.currentTime, true)

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
			soundFile: plasmoid.configuration.eventStartingSfxEnabled ? plasmoid.configuration.eventStartingSfxPath : '',
			urgency: 'critical',
			loop: 3,
			loopDelay: 0.8,
		}

		// Persistent notifications stay until user closes them
		if (plasmoid.configuration.eventStartingNotificationPersistent) {
			args.expireTimeout = 0
			args.noWait = true // Don't block - just show and exit
		}

		notificationManager.notify(args)
		logger.debug('upcomingEvents: sent starting notification for:', eventItem.summary)
	}

	function checkForEventsStarting() {
		var eventsChecked = 0
		var notificationsSent = 0
		cleanupOldHistory()

		for (var calendarId in eventsByCalendar) {
			var calendar = eventsByCalendar[calendarId]
			calendar.items.forEach(function(eventItem, index, calendarEventList) {
				eventsChecked++
				var eventUid = getEventUniqueId(eventItem)

				// Check for "starting now" notifications (T-0)
				if (isEventStarting(eventItem) || (isEventInProgress(eventItem) && !hasNotified(eventUid))) {
					var isStartingNow = isEventStarting(eventItem)
					logger.debug('upcomingEvents:', isStartingNow ? 'event starting now:' : 'event in progress (catch-up):', eventItem.summary, eventItem.startDateTime)
					
					if (plasmoid.configuration.eventStartingNotificationEnabled && !hasNotified(eventUid)) {
						sendEventStartingNotification(eventItem)
						markNotified(eventUid, eventItem.endDateTime.getTime())
						notificationsSent++
					} else if (hasNotified(eventUid)) {
						logger.debug('upcomingEvents: already notified for:', eventItem.summary)
					} else {
						logger.debug('upcomingEvents: eventStartingNotificationEnabled is disabled')
					}
				}
				// Check for reminder notifications (T-X minutes)
				else if (plasmoid.configuration.eventReminderNotificationEnabled && !hasReminded(eventUid)) {
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
	}

	function syncWithEventModel() {
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

	Component.onCompleted: {
		loadNotificationHistory()
	}
}
