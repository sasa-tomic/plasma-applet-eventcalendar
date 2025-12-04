import QtQuick 2.0
import org.kde.plasma.core 2.0 as PlasmaCore

import "LocaleFuncs.js" as LocaleFuncs
import "./calendars"

CalendarManager {
	id: upcomingEvents

	property int upcomingEventRange: 90 // minutes
	property int minutesBeforeReminding: plasmoid.configuration.eventReminderMinutesBefore // minutes

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
		notificationManager.notify({
			appName: i18n("Event Calendar"),
			appIcon: "view-calendar-upcoming-events",
			// expireTimeout: (minutes*60 - 1) * 1000, // timeout resets on hover so may last longer than event starts.
			summary: summaryText,
			body: bodyText,
			soundFile: plasmoid.configuration.eventReminderSfxEnabled ? plasmoid.configuration.eventReminderSfxPath : '',
		})
	}

	function sendEventStartingNotification(eventItem) {
		notificationManager.notify({
			appName: i18n("Event Calendar"),
			appIcon: "view-calendar-upcoming-events",
			// expireTimeout: 10000,
			summary: eventItem.summary,
			body: LocaleFuncs.formatEventDuration(eventItem, {
				relativeDate: timeModel.currentTime,
				clock24h: appletConfig.clock24h,
			}),
			soundFile: plasmoid.configuration.eventStartingSfxEnabled ? plasmoid.configuration.eventStartingSfxPath : '',
		})
	}

	function checkForEventsStarting() {
		var eventsChecked = 0
		var notificationsSent = 0
		for (var calendarId in eventsByCalendar) {
			var calendar = eventsByCalendar[calendarId]
			calendar.items.forEach(function(eventItem, index, calendarEventList) {
				eventsChecked++
				if (isEventStarting(eventItem)) {
					logger.debug('upcomingEvents: event starting now:', eventItem.summary, eventItem.startDateTime)
					if (plasmoid.configuration.eventStartingNotificationEnabled) {
						sendEventStartingNotification(eventItem)
						notificationsSent++
					} else {
						logger.debug('upcomingEvents: eventStartingNotificationEnabled is disabled')
					}
				} else if (shouldSendReminder(eventItem)) {
					logger.debug('upcomingEvents: sending reminder for:', eventItem.summary, minutesBeforeReminding, 'minutes before')
					if (plasmoid.configuration.eventReminderNotificationEnabled) {
						sendEventReminderNotification(eventItem, minutesBeforeReminding)
						notificationsSent++
					} else {
						logger.debug('upcomingEvents: eventReminderNotificationEnabled is disabled')
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
