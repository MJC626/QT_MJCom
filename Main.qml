import QtQuick
import QtQuick.Controls

ApplicationWindow {
    id: root
    visible: true
    width: 600
    height: 705
    title: qsTr("串口助手")

    property int maxLines: 100
    property string bufferText: ""
    property bool autoScroll: true
    property real lastScrollPosition: 0

    function getCurrentDateTime() {
        var now = new Date();
        return now.toLocaleString(Qt.locale(), "yyyy-MM-dd hh:mm:ss");
    }

    Timer {
        id: updateTimer
        interval: 100 // Update every 100ms
        repeat: true
        running: true
        onTriggered: {
            if (bufferText !== "") {
                var scrollAtBottom = isScrollAtBottom()
                var currentPosition = scrollView.ScrollBar.vertical.position

                receiveArea.append(bufferText)
                trimOldData()

                if (autoScroll || scrollAtBottom) {
                    forceRefresh()
                } else {
                    // Maintain the scroll position
                    scrollView.ScrollBar.vertical.position = currentPosition
                }

                bufferText = ""
            }
        }
    }

    function isScrollAtBottom() {
        var scrollBar = scrollView.ScrollBar.vertical
        return (scrollBar.position + scrollBar.size >= 0.99)
    }

    Column {
        spacing: 10
        padding: 20

        // 扫描串口按钮
        Button {
            text: "扫描端口"
            onClicked: {
                portSelector.model = serial.scanPorts();
            }
        }

        // 串口选择器
        ComboBox {
            id: portSelector
            width: 200
        }

        // 波特率选择器
        ComboBox {
            id: baudRateSelector
            width: 200
            model: ["9600", "19200", "38400", "57600", "115200"]
        }

        // 数据位选择器
        ComboBox {
            id: dataBitsSelector
            width: 200
            model: ["8", "7"]
        }

        // 停止位选择器
        ComboBox {
            id: stopBitsSelector
            width: 200
            model: ["1", "2"]
        }

        // 校验位选择器
        ComboBox {
            id: paritySelector
            width: 200
            model: ["None", "Even", "Odd"]
        }

        // 接收数据显示区域
        // 接收数据显示区域
        Rectangle {
            width: 560
            height: 200
            border.color: "black"

            ScrollView {
                id: scrollView
                anchors.fill: parent
                clip: true
                ScrollBar.vertical.policy: ScrollBar.AsNeeded

                TextArea {
                    id: receiveArea
                    width: scrollView.width
                    readOnly: true
                    wrapMode: TextArea.Wrap
                    textFormat: TextEdit.PlainText
                }
            }
        }


        // 发送数据输入区域
        TextArea {
            id: sendArea
            width: 560
            height: 100
            placeholderText: "输入16进制数据，例如: 01 04 00 00 00 02 71 CB"
        }

        // 自动发送时间间隔输入框
        TextField {
            id: intervalField
            width: 200
            placeholderText: "输入自动发送间隔 (ms)"
        }

        Row {
            spacing: 10

            Button {
                text: "打开"
                onClicked: serial.openPort(
                    portSelector.currentText,
                    baudRateSelector.currentText,
                    dataBitsSelector.currentText,
                    stopBitsSelector.currentText,
                    paritySelector.currentText
                )
            }

            Button {
                text: "关闭"
                onClicked: serial.closePort()
            }

            Button {
                text: "发送"
                onClicked: {
                    let hexData = sendArea.text.trim();
                    serial.sendData(hexData);
                    sendArea.text = "";
                }
            }
        }

        Row {
            spacing: 10

            Button {
                text: "开始自动发送"
                onClicked: {
                    let hexData = sendArea.text.trim();
                    let interval = parseInt(intervalField.text);
                    if (!isNaN(interval) && hexData !== "") {
                        serial.startAutoSend(hexData, interval);
                    }
                }
            }

            Button {
                text: "停止自动发送"
                onClicked: serial.stopAutoSend()
            }
        }

        // Auto-scroll toggle
        CheckBox {
            id: autoScrollCheckBox
            text: "自动滚动"
            checked: autoScroll
            onCheckedChanged: {
                autoScroll = checked
                if (autoScroll) {
                    forceRefresh()
                } else {
                    lastScrollPosition = scrollView.ScrollBar.vertical.position
                }
            }
        }

        // Auto-clean controls
        Row {
                    spacing: 10
                    Label {
                        text: "最大行数:"
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    TextField {
                        id: maxLinesField
                        width: 100
                        text: maxLines.toString()
                        validator: IntValidator {
                            bottom: 10
                            top: 1000
                        }
                        onEditingFinished: {
                            if (acceptableInput) {
                                maxLines = parseInt(text)
                                trimOldData()
                            } else {
                                text = maxLines.toString()
                            }
                        }
                    }
                }

                Button {
                    text: "清空接收区"
                    onClicked: clearReceiveArea()
                }
            }

    Connections {
        target: serial
        function onDataReceived(data) {
            var timestamp = getCurrentDateTime();
            bufferText += "\n[接收] " + timestamp + " " + data;
        }
        function onDataSent(data) {
            var timestamp = getCurrentDateTime();
            bufferText += "\n[发送] " + timestamp + " " + data;
        }
    }

    function trimOldData() {
            var lines = receiveArea.text.split('\n')
            if (lines.length > maxLines) {
                lines = lines.slice(-maxLines)
                receiveArea.text = lines.join('\n')
                if (autoScroll) {
                    forceRefresh()
                }
            }
        }

    function forceRefresh() {
           receiveArea.cursorPosition = receiveArea.length
           scrollView.ScrollBar.vertical.position = 1.0 - scrollView.ScrollBar.vertical.size
       }

    function clearReceiveArea() {
        receiveArea.clear()
        bufferText = ""
        forceRefresh()
    }
}
