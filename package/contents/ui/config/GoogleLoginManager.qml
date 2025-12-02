import QtQuick 2.0
import org.kde.plasma.core 2.0 as PlasmaCore

import "../lib"
import "../lib/Requests.js" as Requests

Item {
	id: session

	Logger {
		id: logger
		showDebug: plasmoid.configuration.debugging
	}

	ExecUtil {
		id: execUtil
	}

	// Active Session
	readonly property bool isLoggedIn: !!plasmoid.configuration.accessToken
	readonly property bool needsRelog: {
		if (plasmoid.configuration.accessToken && plasmoid.configuration.latestClientId != plasmoid.configuration.sessionClientId) {
			return true
		} else if (!plasmoid.configuration.accessToken && plasmoid.configuration.access_token) {
			return true
		} else {
			return false
		}
	}

	// Data
	property var m_calendarList: ConfigSerializedString {
		id: m_calendarList
		configKey: 'calendarList'
		defaultValue: []
	}
	property alias calendarList: m_calendarList.value

	property var m_calendarIdList: ConfigSerializedString {
		id: m_calendarIdList
		configKey: 'calendarIdList'
		defaultValue: []

		function serialize() {
			plasmoid.configuration[configKey] = value.join(',')
		}
		function deserialize() {
			value = configValue.split(',')
		}
	}
	property alias calendarIdList: m_calendarIdList.value

	property var m_tasklistList: ConfigSerializedString {
		id: m_tasklistList
		configKey: 'tasklistList'
		defaultValue: []
	}
	property alias tasklistList: m_tasklistList.value

	property var m_tasklistIdList: ConfigSerializedString {
		id: m_tasklistIdList
		configKey: 'tasklistIdList'
		defaultValue: []

		function serialize() {
			plasmoid.configuration[configKey] = value.join(',')
		}
		function deserialize() {
			value = configValue.split(',')
		}
	}
	property alias tasklistIdList: m_tasklistIdList.value


	//--- Signals
	signal newAccessToken()
	signal sessionReset()
	signal error(string err)
	signal authorizationStarted()
	signal authorizationComplete()


	//--- OAuth Server State
	property int oauthServerPort: 0
	property bool oauthInProgress: false
	property string oauthTempFile: '/tmp/plasma-eventcalendar-oauth-' + Date.now() + '.json'

	//--- Loopback OAuth Flow
	function getAuthorizationCodeUrl(redirectUri) {
		var url = 'https://accounts.google.com/o/oauth2/v2/auth'
		url += '?scope=' + encodeURIComponent('https://www.googleapis.com/auth/calendar https://www.googleapis.com/auth/tasks')
		url += '&response_type=code'
		url += '&redirect_uri=' + encodeURIComponent(redirectUri)
		url += '&client_id=' + encodeURIComponent(plasmoid.configuration.latestClientId)
		return url
	}

	function startLoopbackAuth() {
		logger.debug('Starting loopback OAuth flow')
		oauthInProgress = true
		authorizationStarted()

		// Start the Python OAuth server in background and capture port immediately
		var scriptPath = Qt.resolvedUrl('../../scripts/oauth_server.py')
		// Convert file:// URL to local path
		scriptPath = scriptPath.replace(/^file:\/\//, '')

		// Start server in background, writing output to temp file
		var startCmd = 'python3 -u ' + execUtil.wrapToken(scriptPath) + ' > ' + oauthTempFile + ' 2>&1 & echo $!'

		logger.debug('Starting OAuth server:', startCmd)

		execUtil.exec(startCmd, function(cmd, exitCode, exitStatus, stdout, stderr) {
			var serverPid = stdout.trim()
			logger.debug('OAuth server PID:', serverPid)

			if (!serverPid || exitCode !== 0) {
				oauthInProgress = false
				handleError('Failed to start OAuth server', null)
				authorizationComplete()
				return
			}

			// Wait a moment for the server to write the port
			Qt.createQmlObject('import QtQuick 2.0; Timer { interval: 500; repeat: false; running: true }', session).triggered.connect(function() {
				// Read the port from the temp file
				execUtil.exec('head -1 ' + oauthTempFile, function(cmd, exitCode, exitStatus, stdout, stderr) {
					logger.debug('Port file content:', stdout)

					try {
						var portData = JSON.parse(stdout.trim())
						oauthServerPort = portData.port
						logger.debug('OAuth server started on port:', oauthServerPort)

						// Construct the redirect URI and authorization URL
						var redirectUri = 'http://127.0.0.1:' + oauthServerPort
						var authUrl = getAuthorizationCodeUrl(redirectUri)

						logger.debug('Opening authorization URL:', authUrl)
						Qt.openUrlExternally(authUrl)

						// Now wait for the server process to complete
						waitForOAuthCompletion(serverPid)
					} catch (e) {
						logger.debug('Error reading port:', e, stdout)
						oauthInProgress = false
						handleError('Failed to read OAuth server port: ' + e, null)
						authorizationComplete()
						// Kill the server
						execUtil.exec('kill ' + serverPid, function() {})
					}
				})
			})
		})
	}

	function waitForOAuthCompletion(serverPid) {
		// Poll for server completion
		var checkCmd = 'ps -p ' + serverPid + ' > /dev/null && echo running || echo done'
		execUtil.exec(checkCmd, function(cmd, exitCode, exitStatus, stdout, stderr) {
			var status = stdout.trim()

			if (status === 'running') {
				// Still running, check again in 2 seconds
				Qt.createQmlObject('import QtQuick 2.0; Timer { interval: 2000; repeat: false; running: true }', session).triggered.connect(function() {
					waitForOAuthCompletion(serverPid)
				})
			} else {
				// Server completed, read the result
				execUtil.exec('cat ' + oauthTempFile, function(cmd, exitCode, exitStatus, stdout, stderr) {
					oauthInProgress = false

					logger.debug('OAuth server output:', stdout)

					try {
						var lines = stdout.trim().split('\n')
						if (lines.length >= 2) {
							var result = JSON.parse(lines[lines.length - 1])

							if (result.success && result.code) {
								logger.debug('Successfully received authorization code')
								var redirectUri = 'http://127.0.0.1:' + oauthServerPort
								fetchAccessToken(result.code, redirectUri)
							} else {
								var errorMsg = result.error || 'Unknown error'
								if (errorMsg === 'timeout') {
									handleError('Authorization timed out. Please try again.', null)
								} else {
									handleError('Authorization failed: ' + errorMsg, null)
								}
							}
						} else {
							handleError('OAuth server completed without result', null)
						}
					} catch (e) {
						logger.debug('Error parsing OAuth result:', e)
						handleError('Failed to parse OAuth result: ' + e, null)
					}

					// Cleanup temp file
					execUtil.exec('rm -f ' + oauthTempFile, function() {})
					authorizationComplete()
				})
			}
		})
	}

	function fetchAccessToken(authorizationCode, redirectUri) {
		var url = 'https://oauth2.googleapis.com/token'

		Requests.post({
			url: url,
			data: {
				client_id: plasmoid.configuration.latestClientId,
				client_secret: plasmoid.configuration.latestClientSecret,
				code: authorizationCode,
				grant_type: 'authorization_code',
				redirect_uri: redirectUri,
			},
		}, function(err, data, xhr) {
			logger.debug('/token Response', data)

			// Check for errors
			if (err) {
				handleError(err, null)
				return
			}
			try {
				data = JSON.parse(data)
			} catch (e) {
				handleError('Error parsing /token data as JSON', null)
				return
			}
			if (data && data.error) {
				handleError(err, data)
				return
			}

			// Ready
			updateAccessToken(data)
		})
	}

	function updateAccessToken(data) {
		plasmoid.configuration.sessionClientId = plasmoid.configuration.latestClientId
		plasmoid.configuration.sessionClientSecret = plasmoid.configuration.latestClientSecret
		plasmoid.configuration.accessToken = data.access_token
		plasmoid.configuration.accessTokenType = data.token_type
		plasmoid.configuration.accessTokenExpiresAt = Date.now() + data.expires_in * 1000
		plasmoid.configuration.refreshToken = data.refresh_token
		newAccessToken()
	}

	onNewAccessToken: updateData()

	function updateData() {
		updateCalendarList()
		updateTasklistList()
	}

	function updateCalendarList() {
		logger.debug('updateCalendarList')
		logger.debug('accessToken', plasmoid.configuration.accessToken)
		fetchGCalCalendars({
			accessToken: plasmoid.configuration.accessToken,
		}, function(err, data, xhr) {
			// Check for errors
			if (err || data.error) {
				handleError(err, data)
				return
			}
			m_calendarList.value = data.items
		})
	}

	function fetchGCalCalendars(args, callback) {
		var url = 'https://www.googleapis.com/calendar/v3/users/me/calendarList'
		Requests.getJSON({
			url: url,
			headers: {
				"Authorization": "Bearer " + args.accessToken,
			}
		}, function(err, data, xhr) {
			// console.log('fetchGCalCalendars.response', err, data, xhr && xhr.status)
			if (!err && data && data.error) {
				return callback('fetchGCalCalendars error', data, xhr)
			}
			logger.debugJSON('fetchGCalCalendars.response.data', data)
			callback(err, data, xhr)
		})
	}

	function updateTasklistList() {
		logger.debug('updateTasklistList')
		logger.debug('accessToken', plasmoid.configuration.accessToken)
		fetchGoogleTasklistList({
			accessToken: plasmoid.configuration.accessToken,
		}, function(err, data, xhr) {
			// Check for errors
			if (err || data.error) {
				handleError(err, data)
				return
			}
			m_tasklistList.value = data.items
		})
	}

	function fetchGoogleTasklistList(args, callback) {
		var url = 'https://www.googleapis.com/tasks/v1/users/@me/lists'
		Requests.getJSON({
			url: url,
			headers: {
				"Authorization": "Bearer " + args.accessToken,
			}
		}, function(err, data, xhr) {
			console.log('fetchGoogleTasklistList.response', err, data, xhr && xhr.status)
			if (!err && data && data.error) {
				return callback('fetchGoogleTasklistList error', data, xhr)
			}
			logger.debugJSON('fetchGoogleTasklistList.response.data', data)
			callback(err, data, xhr)
		})
	}

	function logout() {
		plasmoid.configuration.sessionClientId = ''
		plasmoid.configuration.sessionClientSecret = ''
		plasmoid.configuration.accessToken = ''
		plasmoid.configuration.accessTokenType = ''
		plasmoid.configuration.accessTokenExpiresAt = 0
		plasmoid.configuration.refreshToken = ''

		// Delete relevant data
		// TODO: only target google calendar data
		// TODO: Make a signal?
		plasmoid.configuration.agendaNewEventLastCalendarId = ''
		calendarList = []
		calendarIdList = []
		tasklistList = []
		tasklistIdList = []
		sessionReset()
	}

	// https://developers.google.com/calendar/v3/errors
	function handleError(err, data) {
		if (data && data.error && data.error_description) {
			var errorMessage = '' + data.error + ' (' + data.error_description + ')'
			session.error(errorMessage)
		} else if (data && data.error && data.error.message && typeof data.error.code !== "undefined") {
			var errorMessage = '' + data.error.message + ' (' + data.error.code + ')'
			session.error(errorMessage)
		} else if (err) {
			session.error(err)
		}
	}
}
