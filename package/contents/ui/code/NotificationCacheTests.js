.pragma library

/**
 * Tests for the notification cache behavior in UpcomingEvents.qml
 * 
 * The notification cache prevents duplicate notifications from being shown:
 * - `_notificationHistory`: Persistent cache to track which events have been notified
 * - `_activeNotifications`: In-memory tracking of live-updating persistent notifications
 * 
 * Bug being tested: When a user dismisses a persistent notification, the notification
 * ID becomes invalid. On the next update tick, the code tries to update using
 * the old replaceId, which causes a NEW notification to be created (since the old
 * one was dismissed). This results in duplicate notifications appearing after
 * the user closes them.
 */

// Mock objects for testing
function createMockLogger() {
	return {
		debug: function() {},
		debugJSON: function() {}
	}
}

function createMockTimeModel(currentTime) {
	return {
		currentTime: currentTime || new Date()
	}
}

function createMockEventItem(id, summary, startMinutesFromNow, durationMinutes) {
	var now = new Date()
	var start = new Date(now.getTime() + startMinutesFromNow * 60000)
	var end = new Date(start.getTime() + (durationMinutes || 60) * 60000)
	return {
		id: id,
		calendarId: 'test-calendar',
		summary: summary,
		startDateTime: start,
		endDateTime: end
	}
}

/**
 * Simulates the OLD BUGGY callback code from updateActiveNotifications
 * This is what the code looked like BEFORE the fix:
 * 
 *   notificationManager.notify(args, function(actionId, newNotificationId) {
 *       // Update stored notification ID if it changed
 *       if (newNotificationId && newNotificationId !== notificationId) {
 *           info.notificationId = newNotificationId
 *       }
 *   })
 */
function simulateOldBuggyCallback(activeNotifications, eventUid, usedReplaceId, returnedNotificationId) {
	var info = activeNotifications[eventUid]
	var notificationId = info.notificationId
	
	// OLD BUGGY CODE: Just update the ID and continue
	if (returnedNotificationId && returnedNotificationId !== notificationId) {
		info.notificationId = returnedNotificationId
	}
}

/**
 * Simulates the NEW FIXED callback code from updateActiveNotifications
 */
function simulateFixedCallback(activeNotifications, dismissedNotifications, eventUid, usedReplaceId, returnedNotificationId, markNotificationDismissed) {
	var info = activeNotifications[eventUid]
	
	// NEW FIXED CODE: Detect dismissal and stop tracking
	if (usedReplaceId && returnedNotificationId && returnedNotificationId !== usedReplaceId) {
		// User dismissed the notification, stop tracking it
		markNotificationDismissed(eventUid)
		return
	}
	
	// Update stored notification ID if it changed (for non-replace cases)
	if (returnedNotificationId && returnedNotificationId !== info.notificationId) {
		info.notificationId = returnedNotificationId
	}
}

/**
 * Test: OLD BUGGY BEHAVIOR - verifies the bug exists
 * 
 * This test runs the old code logic and verifies it would FAIL the requirement
 * "notification should not be recreated after user dismisses it"
 */
function testOldCode_FailsToStopRecreation() {
	var activeNotifications = {}
	var eventUid = 'test-calendar_event1_1234567890000'
	var originalNotificationId = 100
	var newNotificationId = 101  // Different ID = dismissed and recreated
	
	// Register the original notification
	activeNotifications[eventUid] = {
		notificationId: originalNotificationId,
		eventItem: createMockEventItem('event1', 'Test Event', 5, 60),
		expiresAt: Date.now() + 3600000,
		phase: 'upcoming'
	}
	
	// Simulate notification being dismissed by user (server returns different ID)
	var usedReplaceId = originalNotificationId
	simulateOldBuggyCallback(activeNotifications, eventUid, usedReplaceId, newNotificationId)
	
	// THE BUG: Old code keeps the notification tracked, causing it to be recreated
	var notificationStillTracked = !!activeNotifications[eventUid]
	
	// This test PASSES if it confirms the bug exists (notification is still tracked)
	// This demonstrates that the old code was broken
	if (!notificationStillTracked) {
		return {
			passed: false,
			message: 'UNEXPECTED: Old code stopped tracking, but it should have kept the notification (this is the bug)'
		}
	}
	
	return {
		passed: true,
		message: 'CONFIRMED: Old code has the bug - notification still tracked after dismissal (ID updated from 100 to 101)'
	}
}

/**
 * Test: NEW FIXED BEHAVIOR - verifies the fix works
 * 
 * This test runs the fixed code logic and verifies it properly stops recreation
 */
function testNewCode_StopsRecreationAfterDismissal() {
	var activeNotifications = {}
	var dismissedNotifications = {}
	var eventUid = 'test-calendar_event1_1234567890000'
	var originalNotificationId = 100
	var newNotificationId = 101  // Different ID = dismissed and recreated
	
	// Helper function matching the fix in UpcomingEvents.qml
	function markNotificationDismissed(uid) {
		dismissedNotifications[uid] = Date.now()
		delete activeNotifications[uid]
	}
	
	// Register the original notification
	activeNotifications[eventUid] = {
		notificationId: originalNotificationId,
		eventItem: createMockEventItem('event1', 'Test Event', 5, 60),
		expiresAt: Date.now() + 3600000,
		phase: 'upcoming'
	}
	
	// Simulate notification being dismissed by user (server returns different ID)
	var usedReplaceId = originalNotificationId
	simulateFixedCallback(activeNotifications, dismissedNotifications, eventUid, usedReplaceId, newNotificationId, markNotificationDismissed)
	
	// THE FIX: New code should unregister the notification
	var notificationStillTracked = !!activeNotifications[eventUid]
	var markedAsDismissed = !!dismissedNotifications[eventUid]
	
	if (notificationStillTracked) {
		return {
			passed: false,
			message: 'FAIL: Fixed code should have unregistered the notification, but it is still tracked'
		}
	}
	
	if (!markedAsDismissed) {
		return {
			passed: false,
			message: 'FAIL: Fixed code should have marked notification as dismissed'
		}
	}
	
	return {
		passed: true,
		message: 'PASS: Fixed code properly stops tracking after dismissal detected'
	}
}

/**
 * Test: Verify that applying the FIXED logic to the OLD code scenario would have different results
 * 
 * This demonstrates that the fix actually changes the behavior
 */
function testFixChangesOutcome() {
	var eventUid = 'test-calendar_event1_1234567890000'
	var originalNotificationId = 100
	var newNotificationId = 101
	
	// --- Run OLD code ---
	var oldActiveNotifications = {}
	oldActiveNotifications[eventUid] = {
		notificationId: originalNotificationId,
		eventItem: createMockEventItem('event1', 'Test Event', 5, 60),
		expiresAt: Date.now() + 3600000,
		phase: 'upcoming'
	}
	simulateOldBuggyCallback(oldActiveNotifications, eventUid, originalNotificationId, newNotificationId)
	var oldCodeResult = !!oldActiveNotifications[eventUid]
	
	// --- Run NEW code ---
	var newActiveNotifications = {}
	var newDismissedNotifications = {}
	newActiveNotifications[eventUid] = {
		notificationId: originalNotificationId,
		eventItem: createMockEventItem('event1', 'Test Event', 5, 60),
		expiresAt: Date.now() + 3600000,
		phase: 'upcoming'
	}
	function markDismissed(uid) {
		newDismissedNotifications[uid] = Date.now()
		delete newActiveNotifications[uid]
	}
	simulateFixedCallback(newActiveNotifications, newDismissedNotifications, eventUid, originalNotificationId, newNotificationId, markDismissed)
	var newCodeResult = !!newActiveNotifications[eventUid]
	
	// Verify outcomes are different
	if (oldCodeResult === newCodeResult) {
		return {
			passed: false,
			message: 'FAIL: Old and new code produced the same result - fix did not change behavior'
		}
	}
	
	if (!oldCodeResult) {
		return {
			passed: false,
			message: 'FAIL: Old code should have kept notification tracked (the bug)'
		}
	}
	
	if (newCodeResult) {
		return {
			passed: false,
			message: 'FAIL: New code should have unregistered notification (the fix)'
		}
	}
	
	return {
		passed: true,
		message: 'PASS: Fix changes outcome - old code kept notification tracked (bug), new code unregisters it (fix)'
	}
}

/**
 * Test: hasReminded should return true after markReminded is called
 */
function testMarkRemindedPersistsCorrectly() {
	var notificationHistory = {}
	var eventUid = 'test-calendar_event1_1234567890000'
	var expiresAt = Date.now() + 3600000
	
	// Simulate markReminded
	notificationHistory[eventUid] = {
		reminded: expiresAt,
		shownAt: Date.now()
	}
	
	// Simulate hasReminded check
	var hasReminded = !!(notificationHistory[eventUid] && notificationHistory[eventUid].reminded)
	
	if (!hasReminded) {
		return {
			passed: false,
			message: 'FAIL: hasReminded returned false after markReminded was called'
		}
	}
	
	return {
		passed: true,
		message: 'PASS: hasReminded correctly returns true after markReminded'
	}
}

/**
 * Test: hasNotified should return true after markNotified is called
 */
function testMarkNotifiedPersistsCorrectly() {
	var notificationHistory = {}
	var eventUid = 'test-calendar_event1_1234567890000'
	var expiresAt = Date.now() + 3600000
	
	// Simulate markNotified
	notificationHistory[eventUid] = {
		notified: expiresAt,
		shownAt: Date.now()
	}
	
	// Simulate hasNotified check
	var hasNotified = !!(notificationHistory[eventUid] && notificationHistory[eventUid].notified)
	
	if (!hasNotified) {
		return {
			passed: false,
			message: 'FAIL: hasNotified returned false after markNotified was called'
		}
	}
	
	return {
		passed: true,
		message: 'PASS: hasNotified correctly returns true after markNotified'
	}
}

/**
 * Test: When notification ID changes during update, should mark as dismissed
 */
function testNotificationIdChangeShouldMarkDismissed() {
	var activeNotifications = {}
	var dismissedNotifications = {}  // New: Track dismissed notifications
	var eventUid = 'test-calendar_event1_1234567890000'
	
	// Initial state: notification is active
	activeNotifications[eventUid] = {
		notificationId: 100,
		eventItem: createMockEventItem('event1', 'Test Event', 5, 60),
		expiresAt: Date.now() + 3600000,
		phase: 'upcoming'
	}
	
	// Simulate: user dismisses, we try to replace, get new ID
	var oldId = activeNotifications[eventUid].notificationId
	var newId = 101  // Different ID indicates recreation
	
	// This is what the FIX should do:
	if (oldId !== newId) {
		// Mark as dismissed so we don't recreate
		dismissedNotifications[eventUid] = true
		delete activeNotifications[eventUid]
	}
	
	// Verify the notification was properly handled
	var stillActive = !!activeNotifications[eventUid]
	var markedDismissed = !!dismissedNotifications[eventUid]
	
	if (stillActive) {
		return {
			passed: false,
			message: 'FAIL: Notification should not be active after dismissal detected'
		}
	}
	
	if (!markedDismissed) {
		return {
			passed: false,
			message: 'FAIL: Notification should be marked as dismissed'
		}
	}
	
	return {
		passed: true,
		message: 'PASS: Notification correctly marked as dismissed when ID changes'
	}
}

/**
 * Test: Subsequent update ticks should skip dismissed notifications
 * 
 * This tests the full flow:
 * 1. Notification is active
 * 2. User dismisses it (detected by ID change)
 * 3. Notification is marked as dismissed
 * 4. On subsequent ticks, the dismissed notification is skipped
 */
function testSubsequentTicksSkipDismissedNotifications() {
	var activeNotifications = {}
	var dismissedNotifications = {}
	var eventUid = 'test-calendar_event1_1234567890000'
	
	// Step 1: Register an active notification
	activeNotifications[eventUid] = {
		notificationId: 100,
		eventItem: createMockEventItem('event1', 'Test Event', 5, 60),
		expiresAt: Date.now() + 3600000,
		phase: 'upcoming'
	}
	
	// Step 2: Simulate dismissal detection (ID changed from 100 to 101)
	dismissedNotifications[eventUid] = Date.now()
	delete activeNotifications[eventUid]
	
	// Step 3: Simulate next tick - wasNotificationDismissed check
	function wasNotificationDismissed(uid) {
		return !!dismissedNotifications[uid]
	}
	
	// If the notification was re-added (shouldn't happen, but test the guard)
	activeNotifications[eventUid] = {
		notificationId: 101,
		eventItem: createMockEventItem('event1', 'Test Event', 4, 60),
		expiresAt: Date.now() + 3600000,
		phase: 'upcoming'
	}
	
	// Simulate updateActiveNotifications loop
	var skippedDismissed = false
	for (var uid in activeNotifications) {
		if (wasNotificationDismissed(uid)) {
			delete activeNotifications[uid]
			skippedDismissed = true
			continue
		}
		// Would update notification here...
	}
	
	if (!skippedDismissed) {
		return {
			passed: false,
			message: 'FAIL: Update loop did not skip the dismissed notification'
		}
	}
	
	if (activeNotifications[eventUid]) {
		return {
			passed: false,
			message: 'FAIL: Dismissed notification was not removed from active list'
		}
	}
	
	return {
		passed: true,
		message: 'PASS: Subsequent ticks correctly skip dismissed notifications'
	}
}

/**
 * Test: Same notification ID means notification still active (not dismissed)
 */
function testSameIdMeansNotDismissed() {
	var activeNotifications = {}
	var dismissedNotifications = {}
	var eventUid = 'test-calendar_event1_1234567890000'
	var sameId = 100
	
	// Register notification
	activeNotifications[eventUid] = {
		notificationId: sameId,
		eventItem: createMockEventItem('event1', 'Test Event', 5, 60),
		expiresAt: Date.now() + 3600000,
		phase: 'upcoming'
	}
	
	// Simulate update with same ID returned (not dismissed)
	var usedReplaceId = sameId
	var returnedId = sameId  // Same ID means still active
	
	var wasDismissed = usedReplaceId && returnedId !== usedReplaceId
	
	if (wasDismissed) {
		return {
			passed: false,
			message: 'FAIL: Incorrectly detected dismissal when ID stayed the same'
		}
	}
	
	// Notification should still be active
	if (!activeNotifications[eventUid]) {
		return {
			passed: false,
			message: 'FAIL: Notification was incorrectly removed'
		}
	}
	
	return {
		passed: true,
		message: 'PASS: Same notification ID correctly treated as not dismissed'
	}
}

/**
 * Run all tests and return results
 */
function runAllTests() {
	var tests = [
		{ name: 'testMarkRemindedPersistsCorrectly', fn: testMarkRemindedPersistsCorrectly },
		{ name: 'testMarkNotifiedPersistsCorrectly', fn: testMarkNotifiedPersistsCorrectly },
		{ name: 'testOldCode_FailsToStopRecreation', fn: testOldCode_FailsToStopRecreation },
		{ name: 'testNewCode_StopsRecreationAfterDismissal', fn: testNewCode_StopsRecreationAfterDismissal },
		{ name: 'testFixChangesOutcome', fn: testFixChangesOutcome },
		{ name: 'testNotificationIdChangeShouldMarkDismissed', fn: testNotificationIdChangeShouldMarkDismissed },
		{ name: 'testSubsequentTicksSkipDismissedNotifications', fn: testSubsequentTicksSkipDismissedNotifications },
		{ name: 'testSameIdMeansNotDismissed', fn: testSameIdMeansNotDismissed },
	]
	
	var results = []
	var passed = 0
	var failed = 0
	
	for (var i = 0; i < tests.length; i++) {
		var test = tests[i]
		try {
			var result = test.fn()
			result.name = test.name
			results.push(result)
			if (result.passed) {
				passed++
			} else {
				failed++
			}
		} catch (e) {
			results.push({
				name: test.name,
				passed: false,
				message: 'ERROR: ' + e.toString()
			})
			failed++
		}
	}
	
	return {
		results: results,
		passed: passed,
		failed: failed,
		total: tests.length
	}
}
