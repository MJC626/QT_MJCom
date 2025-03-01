import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

ApplicationWindow {
    id: root
    visible: true
    width: 600
    height: 755
    title: qsTr("串口助手")

    property int maxLines: 100
    property string bufferText: ""
    property bool autoScroll: true
    property real lastScrollPosition: 0
    property bool displayHex: true  // 显示模式：true为HEX，false为ASCII
    property bool sendHex: true     // 发送模式：true为HEX，false为ASCII

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
        Row {
            spacing: 10
            Label {
                text: "串口:"
                anchors.verticalCenter: parent.verticalCenter
            }
            ComboBox {
                id: portSelector
                width: 200
            }
        }

        // 波特率选择器
        Row {
            spacing: 10
            Label {
                text: "波特率:"
                anchors.verticalCenter: parent.verticalCenter
            }
            ComboBox {
                id: baudRateSelector
                width: 200
                model: ["9600", "19200", "38400", "57600", "115200"]
                currentIndex: 4  // 默认选择115200
            }
        }

        // 数据位选择器
        Row {
            spacing: 10
            Label {
                text: "数据位:"
                anchors.verticalCenter: parent.verticalCenter
            }
            ComboBox {
                id: dataBitsSelector
                width: 200
                model: ["8", "7"]
            }
        }

        // 停止位选择器
        Row {
            spacing: 10
            Label {
                text: "停止位:"
                anchors.verticalCenter: parent.verticalCenter
            }
            ComboBox {
                id: stopBitsSelector
                width: 200
                model: ["1", "2"]
            }
        }

        // 校验位选择器
        Row {
            spacing: 10
            Label {
                text: "校验位:"
                anchors.verticalCenter: parent.verticalCenter
            }
            ComboBox {
                id: paritySelector
                width: 200
                model: ["None", "Even", "Odd"]
            }
        }

        // 数据显示格式选择
        RowLayout {
            spacing: 10

            Label {
                text: "显示格式:"
            }

            RadioButton {
                id: displayHexRadio
                text: "HEX"
                checked: displayHex
                onCheckedChanged: {
                    if (checked) {
                        displayHex = true
                    }
                }
            }

            RadioButton {
                id: displayAsciiRadio
                text: "ASCII"
                checked: !displayHex
                onCheckedChanged: {
                    if (checked) {
                        displayHex = false
                    }
                }
            }
        }

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

        // 数据发送格式选择
        RowLayout {
            spacing: 10

            Label {
                text: "发送格式:"
            }

            RadioButton {
                id: sendHexRadio
                text: "HEX"
                checked: sendHex
                onCheckedChanged: {
                    if (checked) {
                        sendHex = true
                        sendArea.placeholderText = "输入16进制数据，例如: 01 04 00 00 00 02 71 CB"
                    }
                }
            }

            RadioButton {
                id: sendAsciiRadio
                text: "ASCII"
                checked: !sendHex
                onCheckedChanged: {
                    if (checked) {
                        sendHex = false
                        sendArea.placeholderText = "输入ASCII文本"
                    }
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
            text: "1000"  // 默认为1000ms
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
                    let data = sendArea.text.trim();
                    if (data !== "") {
                        serial.sendData(data, sendHex);
                    }
                }
            }
        }

        Row {
            spacing: 10

            Button {
                text: "开始自动发送"
                onClicked: {
                    let data = sendArea.text.trim();
                    let interval = parseInt(intervalField.text);
                    if (!isNaN(interval) && data !== "") {
                        serial.startAutoSend(data, interval, sendHex);
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

        // 修改后的接收数据处理
        function onDataReceived(hexData, asciiData) {
            var timestamp = getCurrentDateTime();
            var displayData;

            // 根据当前显示模式选择要显示的数据格式
            if (displayHex) {
                displayData = hexData;
            } else {
                displayData = asciiData;
            }

            // 确保数据不为空
            if (displayData.trim() !== "") {
                bufferText += "\n[接收] " + timestamp + " " + displayData;
            }
        }

        // 发送数据处理
        function onDataSent(data, isHex) {
            var timestamp = getCurrentDateTime();
            var displayData = data;

            // 如果显示模式和发送模式不一致，需要转换
            if (displayHex && !isHex) {
                // ASCII转HEX显示
                var result = "";
                for (var i = 0; i < data.length; i++) {
                    var hex = data.charCodeAt(i).toString(16).toUpperCase();
                    if (hex.length < 2) {
                        hex = "0" + hex;
                    }
                    result += hex + " ";
                }
                displayData = result.trim();
            } else if (!displayHex && isHex) {
                // HEX转ASCII显示（仅用于显示）
                try {
                    var chars = [];
                    var hexValues = data.split(" ");
                    for (var j = 0; j < hexValues.length; j++) {
                        if (hexValues[j].trim() !== "") {
                            var val = parseInt(hexValues[j], 16);
                            if (val >= 32 && val <= 126) { // 可打印ASCII字符
                                chars.push(String.fromCharCode(val));
                            } else {
                                chars.push(".");  // 不可打印字符用点代替
                            }
                        }
                    }
                    displayData = chars.join("");
                } catch (e) {
                    displayData = "[无法转换为ASCII]";
                }
            }

            bufferText += "\n[发送] " + timestamp + " " + displayData;
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