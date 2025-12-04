import QtQuick 2.0
import org.kde.plasma.core 2.0 as PlasmaCore

import "LocaleFuncs.js" as LocaleFuncs
import "./calendars"

CalendarManager {
	id: upcomingEvents

	property int upcomingEventRange: 90 // minutes
	property int minutesBeforeReminding: plasmoid.configuration.eventReminderMinutesBefore // minutes

	// Track events we've already sent reminders/notifications for to avoid duplicates
	// Using explicit object to avoid QML property mutation issues
	property var _notificationTracking: ({
		reminded: {},
		notified: {}
	})
	function hasReminded(eventUid) { return !!_notificationTracking.reminded[eventUid] }
	function hasNotified(eventUid) { return !!_notificationTracking.notified[eventUid] }
	function markReminded(eventUid, expiresAt) { _notificationTracking.reminded[eventUid] = expiresAt }
	function markNotified(eventUid, expiresAt) { _notificationTracking.notified[eventUid] = expiresAt }

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
		var deltaText = LocaleFuncs.durationShortFormat(minutes * 60)
		var summaryText = i18nc("%1 = 15 minutes", "Starting in %1", deltaText)
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
		if (plasmoid.configuration.eventReminderNotificationPersistent) {
			args.expireTimeout = 0 // 0 = EXPIRES_NEVER in libnotify
		}
		notificationManager.notify(args)
	}

	function sendEventStartingNotification(eventItem) {
		var args = {
			appName: i18n("Event Calendar"),
			appIcon: "view-calendar-upcoming-events",
			summary: eventItem.summary,
			body: LocaleFuncs.formatEventDuration(eventItem, {
				relativeDate: timeModel.currentTime,
				clock24h: appletConfig.clock24h,
			}),
			soundFile: plasmoid.configuration.eventStartingSfxEnabled ? plasmoid.configuration.eventStartingSfxPath : '',
		}
		if (plasmoid.configuration.eventStartingNotificationPersistent) {
			args.expireTimeout = 0 // 0 = EXPIRES_NEVER in libnotify
		}
		notificationManager.notify(args)
	}

	function getEventUniqueId(eventItem) {
		// Create a unique ID for tracking notifications
		return eventItem.calendarId + '_' + eventItem.id + '_' + eventItem.startDateTime.getTime()
	}

	function cleanupOldTracking() {
		// Remove tracking entries for events that have already started (reminders)
		// or already ended (notifications)
		var now = timeModel.currentTime.getTime()
		for (var eventUid in _notificationTracking.reminded) {
			// Clean up reminders after event starts
			if (_notificationTracking.reminded[eventUid] < now) {
				delete _notificationTracking.reminded[eventUid]
			}
		}
		for (var eventUid in _notificationTracking.notified) {
			// Clean up notifications after event ends (stored as endDateTime)
			if (_notificationTracking.notified[eventUid] < now) {
				delete _notificationTracking.notified[eventUid]
			}
		}
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
}
