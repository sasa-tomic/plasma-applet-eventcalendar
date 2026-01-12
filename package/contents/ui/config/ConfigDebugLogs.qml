import QtQuick 2.0
import QtQuick.Controls 1.0
import QtQuick.Layouts 1.0
import org.kde.kirigami 2.0 as Kirigami
import org.kde.plasma.core 2.0 as PlasmaCore

import ".."
import "../lib"

ColumnLayout {
	id: page
	Layout.fillWidth: true
	Layout.fillHeight: true

	property string logOutput: ""
	property string errorOutput: ""
	property bool isLoading: false
	property string logFilter: "eventcalendar"
	property int maxLines: 500
	property bool autoFetched: false

	ExecUtil {
		id: execUtil
	}

	function fetchLogs() {
		page.isLoading = true
		page.logOutput = i18n("Loading...")
		page.errorOutput = ""
		
		var scriptPath = plasmoid.file("", "scripts/fetchlogs.py")
		
		var cmd = [
			'python3',
			scriptPath
		]
		
		if (logFilter && logFilter.length > 0 && !noFilterCheckbox.checked) {
			cmd.push('--filter', logFilter)
		} else {
			cmd.push('--no-filter')
		}
		
		cmd.push('--lines', '' + maxLines)
		
		if (customCommandField.text && customCommandField.text.length > 0) {
			cmd.push('--command', customCommandField.text)
		}
		
		execUtil.exec(cmd, function(cmd, exitCode, exitStatus, stdout, stderr) {
			page.isLoading = false
			page.logOutput = stdout
			page.errorOutput = stderr
		})
	}

	function copyToClipboard(textField) {
		textField.selectAll()
		textField.copy()
		textField.deselect()
	}

	Component.onCompleted: {
		if (!autoFetched) {
			autoFetched = true
			fetchLogs()
		}
	}

	// Compact toolbar row
	RowLayout {
		Layout.fillWidth: true
		spacing: Kirigami.Units.smallSpacing

		Button {
			text: page.isLoading ? i18n("Loading...") : i18n("Refresh")
			iconName: "view-refresh"
			enabled: !page.isLoading
			onClicked: fetchLogs()
		}

		Button {
			text: i18n("Copy")
			iconName: "edit-copy"
			enabled: page.logOutput.length > 0 && !page.isLoading
			onClicked: copyToClipboard(textArea)
		}

		Button {
			text: i18n("Clear")
			iconName: "edit-clear"
			onClicked: {
				page.logOutput = ""
				page.errorOutput = ""
			}
		}

		Item { width: Kirigami.Units.largeSpacing }

		Label { text: i18n("Filter:") }
		TextField {
			id: filterField
			Layout.preferredWidth: 100
			text: page.logFilter
			onTextChanged: page.logFilter = text
		}
		CheckBox {
			id: noFilterCheckbox
			text: i18n("All")
		}

		Label { text: i18n("Lines:") }
		SpinBox {
			id: maxLinesSpinBox
			Layout.preferredWidth: 70
			minimumValue: 50
			maximumValue: 5000
			value: page.maxLines
			onValueChanged: page.maxLines = value
		}

		Item { Layout.fillWidth: true }

		Label {
			visible: page.logOutput.length > 0 && !page.isLoading
			text: page.logOutput.split('\n').length + " lines"
			opacity: 0.7
		}
	}

	// Custom command row
	RowLayout {
		Layout.fillWidth: true
		spacing: Kirigami.Units.smallSpacing

		CheckBox {
			id: customCommandCheckbox
			text: i18n("Custom command:")
		}
		TextField {
			id: customCommandField
			Layout.fillWidth: true
			enabled: customCommandCheckbox.checked
			placeholderText: "journalctl -b0 _COMM=plasmashell --no-pager"
		}
	}

	// Error display
	Rectangle {
		Layout.fillWidth: true
		Layout.preferredHeight: errorTextArea.contentHeight + 16
		visible: page.errorOutput.length > 0
		color: "#20ff0000"
		border.color: "#cc0000"
		border.width: 1
		radius: 3

		RowLayout {
			anchors.fill: parent
			anchors.margins: 4
			spacing: Kirigami.Units.smallSpacing

			TextArea {
				id: errorTextArea
				Layout.fillWidth: true
				Layout.fillHeight: true
				readOnly: true
				wrapMode: TextEdit.Wrap
				font.family: "monospace"
				font.pointSize: 9
				textColor: "#cc0000"
				text: page.errorOutput
				selectByMouse: true
				backgroundVisible: false
				frameVisible: false
			}

			Button {
				Layout.alignment: Qt.AlignTop
				text: i18n("Copy")
				onClicked: copyToClipboard(errorTextArea)
			}
		}
	}

	// Log output area - fill all remaining space
	TextArea {
		id: textArea
		Layout.fillWidth: true
		Layout.fillHeight: true
		readOnly: true
		wrapMode: TextEdit.NoWrap
		font.family: "monospace"
		font.pointSize: 9
		text: page.logOutput || i18n("Loading logs...")
		selectByMouse: true
	}
}
