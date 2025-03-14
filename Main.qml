import QtQuick
import QtQuick.Controls
import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts
import QtQuick.Controls.Fusion
import QtQuick.Dialogs

ApplicationWindow {
    id: root
    visible: true
    width: 900
    height: 700
    title: qsTr("通信助手")

    property int maxLines: 100 // 接收区最大行数
    property int scriptcurrentLines: 0
    property string bufferText: ""
    property bool autoScroll: true
    property real lastScrollPosition: 0
    property bool displayHex: true  // 显示模式：true为HEX，false为ASCII
    property bool sendHex: true     // 发送模式：true为HEX，false为ASCII
    property int connectionMode: 0   // 连接模式：0=串口,1=TCP客户端,2=TCP服务器,3=UDP
    property bool isConnected: false // 连接状态
    property string statusMessage: "未连接" // 状态消息

    // 文件选择框
    FileDialog {
        id: openScriptDialog
        title: "打开Lua脚本"
        nameFilters: ["Lua脚本 (*.lua)", "所有文件 (*)"]
        onAccepted: {
            var filePath = openScriptDialog.selectedFile.toString();

            if (Qt.platform.os === "windows") {
                filePath = filePath.replace("file:///", "");
            } else {
                filePath = filePath.replace("file://", "");
            }

            var result = serial.loadLuaScriptFile(filePath);

            scriptArea.text = serial.currentScript;

            appendScriptOutput("加载脚本结果: " + result);
        }
    }
    FileDialog {
        id: saveScriptDialog
        title: "保存Lua脚本"
        fileMode: FileDialog.SaveFile
        nameFilters: ["Lua脚本 (*.lua)", "所有文件 (*)"]

        onAccepted: {
            var rawPath = selectedFile.toString();
            var localPath = rawPath.replace(/^(file:\/{3})|(qrc:\/{3})/, ""); // 移除 URL 前缀
            localPath = decodeURIComponent(localPath); // 处理特殊字符

            var success = serial.saveLuaScriptToFile(scriptArea.text, localPath);
            appendScriptOutput(success ? "脚本已保存至：" + localPath : "保存失败，请检查路径和权限");
        }
    }

    function getCurrentDateTime() {
        var now = new Date();
        return now.toLocaleString(Qt.locale(), "yyyy-MM-dd hh:mm:ss");
    }

    Timer {
        id: updateTimer
        interval: 100 // 100ms更新
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
                    // 保持滚动位置
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

    // 主布局：左侧配置区域，右侧分为数据收发区域和脚本区域
    RowLayout {
        anchors.fill: parent
        anchors.margins: 8
        spacing: 8

        // 左侧配置区域
        Rectangle {
            Layout.preferredWidth: 250
            Layout.fillHeight: true
            border.color: "#cccccc"
            border.width: 1
            radius: 4

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 8
                spacing: 6

                // 标题
                Text {
                    Layout.alignment: Qt.AlignHCenter
                    text: "连接配置"
                    font.pixelSize: 16
                    font.bold: true
                }

                // 通信模式选择
                GroupBox {
                    Layout.fillWidth: true
                    title: "通信模式"
                    padding: 6

                    ColumnLayout {
                        anchors.fill: parent
                        spacing: 4
                        
                        RadioButton {
                            id: serialModeRadio
                            text: "串口"
                            checked: connectionMode === 0
                            onCheckedChanged: {
                                if (checked) {
                                    connectionMode = 0
                                    serialConfigGroup.visible = true
                                    tcpClientConfigGroup.visible = false
                                    tcpServerConfigGroup.visible = false
                                    udpConfigGroup.visible = false
                                }
                            }
                        }

                        RadioButton {
                            id: tcpClientModeRadio
                            text: "TCP客户端"
                            checked: connectionMode === 1
                            onCheckedChanged: {
                                if (checked) {
                                    connectionMode = 1
                                    serialConfigGroup.visible = false
                                    tcpClientConfigGroup.visible = true
                                    tcpServerConfigGroup.visible = false
                                    udpConfigGroup.visible = false
                                }
                            }
                        }

                        RadioButton {
                            id: tcpServerModeRadio
                            text: "TCP服务器"
                            checked: connectionMode === 2
                            onCheckedChanged: {
                                if (checked) {
                                    connectionMode = 2
                                    serialConfigGroup.visible = false
                                    tcpClientConfigGroup.visible = false
                                    tcpServerConfigGroup.visible = true
                                    udpConfigGroup.visible = false
                                }
                            }
                        }

                        RadioButton {
                            id: udpModeRadio
                            text: "UDP"
                            checked: connectionMode === 3
                            onCheckedChanged: {
                                if (checked) {
                                    connectionMode = 3
                                    serialConfigGroup.visible = false
                                    tcpClientConfigGroup.visible = false
                                    tcpServerConfigGroup.visible = false
                                    udpConfigGroup.visible = true
                                }
                            }
                        }
                    }
                }

                // 串口配置
                GroupBox {
                    id: serialConfigGroup
                    Layout.fillWidth: true
                    title: "串口配置"
                    visible: connectionMode === 0
                    padding: 6

                    ColumnLayout {
                        anchors.fill: parent
                        spacing: 6

                        // 扫描串口按钮
                        Button {
                            Layout.fillWidth: true
                            text: "扫描端口"
                            implicitHeight: 28
                            background: Rectangle {
                                color: parent.pressed ? "#007BFF" : "#0d6efd"
                                radius: 4
                            }
                            contentItem: Text {
                                text: parent.text
                                color: "white"
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                                font.pixelSize: 12
                            }
                            onClicked: {
                                portSelector.model = serial.scanPorts();
                            }
                        }

                        // 串口选择器 - 使用简洁紧凑的布局
                        GridLayout {
                            Layout.fillWidth: true
                            columns: 2
                            columnSpacing: 4
                            rowSpacing: 4

                            Label {
                                text: "串口:"
                                Layout.alignment: Qt.AlignRight
                                font.pixelSize: 12
                            }
                            ComboBox {
                                id: portSelector
                                Layout.fillWidth: true
                                implicitHeight: 24
                                font.pixelSize: 12
                            }

                            Label {
                                text: "波特率:"
                                Layout.alignment: Qt.AlignRight
                                font.pixelSize: 12
                            }
                            ComboBox {
                                id: baudRateSelector
                                Layout.fillWidth: true
                                implicitHeight: 24
                                model: ["9600", "19200", "38400", "57600", "115200"]
                                currentIndex: 4  // 默认选择115200
                                font.pixelSize: 12
                            }

                            Label {
                                text: "数据位:"
                                Layout.alignment: Qt.AlignRight
                                font.pixelSize: 12
                            }
                            ComboBox {
                                id: dataBitsSelector
                                Layout.fillWidth: true
                                implicitHeight: 24
                                model: ["8", "7"]
                                font.pixelSize: 12
                            }

                            Label {
                                text: "停止位:"
                                Layout.alignment: Qt.AlignRight
                                font.pixelSize: 12
                            }
                            ComboBox {
                                id: stopBitsSelector
                                Layout.fillWidth: true
                                implicitHeight: 24
                                model: ["1", "2"]
                                font.pixelSize: 12
                            }

                            Label {
                                text: "校验位:"
                                Layout.alignment: Qt.AlignRight
                                font.pixelSize: 12
                            }
                            ComboBox {
                                id: paritySelector
                                Layout.fillWidth: true
                                implicitHeight: 24
                                model: ["None", "Even", "Odd"]
                                font.pixelSize: 12
                            }
                        }
                    }
                }

                // TCP客户端配置
                GroupBox {
                    id: tcpClientConfigGroup
                    Layout.fillWidth: true
                    title: "TCP客户端配置"
                    visible: connectionMode === 1
                    padding: 6

                    GridLayout {
                        anchors.fill: parent
                        columns: 2
                        columnSpacing: 4
                        rowSpacing: 4

                        Label {
                            text: "服务器:"
                            Layout.alignment: Qt.AlignRight
                            font.pixelSize: 12
                        }
                        TextField {
                            id: tcpClientHostField
                            Layout.fillWidth: true
                            implicitHeight: 24
                            text: "127.0.0.1"
                            placeholderText: "输入ip"
                            font.pixelSize: 12
                        }

                        Label {
                            text: "端口:"
                            Layout.alignment: Qt.AlignRight
                            font.pixelSize: 12
                        }
                        TextField {
                            id: tcpClientPortField
                            Layout.fillWidth: true
                            implicitHeight: 24
                            text: "8080"
                            placeholderText: "端口号"
                            font.pixelSize: 12
                            validator: IntValidator {
                                bottom: 1
                                top: 65535
                            }
                        }
                    }
                }

                // TCP服务器配置
                GroupBox {
                    id: tcpServerConfigGroup
                    Layout.fillWidth: true
                    title: "TCP服务器配置"
                    visible: connectionMode === 2
                    padding: 6

                    GridLayout {
                        anchors.fill: parent
                        columns: 2
                        columnSpacing: 4
                        rowSpacing: 4

                        Label {
                            text: "监听端口:"
                            Layout.alignment: Qt.AlignRight
                            font.pixelSize: 12
                        }
                        TextField {
                            id: tcpServerPortField
                            Layout.fillWidth: true
                            implicitHeight: 24
                            text: "8080"
                            placeholderText: "端口号"
                            font.pixelSize: 12
                            validator: IntValidator {
                                bottom: 1
                                top: 65535
                            }
                        }
                    }
                }

                // UDP配置
                GroupBox {
                    id: udpConfigGroup
                    Layout.fillWidth: true
                    title: "UDP配置"
                    visible: connectionMode === 3
                    padding: 6

                    GridLayout {
                        anchors.fill: parent
                        columns: 2
                        columnSpacing: 4
                        rowSpacing: 4

                        Label {
                            text: "本地端口:"
                            Layout.alignment: Qt.AlignRight
                            font.pixelSize: 12
                        }
                        TextField {
                            id: udpLocalPortField
                            Layout.fillWidth: true
                            implicitHeight: 24
                            text: "8080"
                            placeholderText: "本地端口"
                            font.pixelSize: 12
                            validator: IntValidator {
                                bottom: 1
                                top: 65535
                            }
                        }

                        Label {
                            text: "目标地址:"
                            Layout.alignment: Qt.AlignRight
                            font.pixelSize: 12
                        }
                        TextField {
                            id: udpRemoteHostField
                            Layout.fillWidth: true
                            implicitHeight: 24
                            text: "127.0.0.1"
                            placeholderText: "目标IP地址"
                            font.pixelSize: 12
                        }

                        Label {
                            text: "目标端口:"
                            Layout.alignment: Qt.AlignRight
                            font.pixelSize: 12
                        }
                        TextField {
                            id: udpRemotePortField
                            Layout.fillWidth: true
                            implicitHeight: 24
                            text: "8081"
                            placeholderText: "目标端口"
                            font.pixelSize: 12
                            validator: IntValidator {
                                bottom: 1
                                top: 65535
                            }
                        }
                    }
                }

                // 数据格式区域 - 使用一个组合起来的GroupBox节省空间
                GroupBox {
                    Layout.fillWidth: true
                    title: "数据格式"
                    padding: 6

                    ColumnLayout {
                        anchors.fill: parent
                        spacing: 4

                        // 显示格式
                        RowLayout {
                            Layout.fillWidth: true

                            Label {
                                text: "显示:"
                                font.pixelSize: 12
                            }

                            RadioButton {
                                id: displayHexRadio
                                text: "HEX"
                                checked: displayHex
                                font.pixelSize: 12
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
                                font.pixelSize: 12
                                onCheckedChanged: {
                                    if (checked) {
                                        displayHex = false
                                    }
                                }
                            }
                        }

                        // 发送格式
                        RowLayout {
                            Layout.fillWidth: true

                            Label {
                                text: "发送:"
                                font.pixelSize: 12
                            }

                            RadioButton {
                                id: sendHexRadio
                                text: "HEX"
                                checked: sendHex
                                font.pixelSize: 12
                                onCheckedChanged: {
                                    if (checked) {
                                        sendHex = true
                                        sendArea.placeholderText = "输入16进制数据"
                                    }
                                }
                            }

                            RadioButton {
                                id: sendAsciiRadio
                                text: "ASCII"
                                checked: !sendHex
                                font.pixelSize: 12
                                onCheckedChanged: {
                                    if (checked) {
                                        sendHex = false
                                        sendArea.placeholderText = "输入ASCII文本"
                                    }
                                }
                            }
                        }
                    }
                }

                // 连接状态指示
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 24
                    color: isConnected ? "#d4edda" : "#f8d7da"
                    border.color: isConnected ? "#c3e6cb" : "#f5c6cb"
                    radius: 4

                    Text {
                        anchors.centerIn: parent
                        text: statusMessage
                        color: isConnected ? "#155724" : "#721c24"
                        font.pixelSize: 12
                    }
                }

                // 控制按钮
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    Button {
                        Layout.fillWidth: true
                        text: "连接"
                        implicitHeight: 28
                        background: Rectangle {
                            color: parent.pressed ? "#198754" : "#28a745"
                            radius: 4
                        }
                        contentItem: Text {
                            text: parent.text
                            color: "white"
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                            font.bold: true
                            font.pixelSize: 12
                        }
                        onClicked: {
                            switch(connectionMode) {
                            case 0: // 串口
                                serial.openPort(
                                            portSelector.currentText,
                                            baudRateSelector.currentText,
                                            dataBitsSelector.currentText,
                                            stopBitsSelector.currentText,
                                            paritySelector.currentText
                                            )
                                break;
                            case 1: // TCP客户端
                                if (tcpClientPortField.acceptableInput) {
                                    serial.connectToTcpServer(
                                                tcpClientHostField.text,
                                                parseInt(tcpClientPortField.text)
                                                )
                                }
                                break;
                            case 2: // TCP服务器
                                if (tcpServerPortField.acceptableInput) {
                                    serial.startTcpServer(
                                                tcpServerPortField.text,
                                                parseInt(tcpServerPortField.text)
                                                )
                                }
                                break;
                            case 3: // UDP
                                if (udpLocalPortField.acceptableInput && udpRemotePortField.acceptableInput) {
                                    serial.startUdp(
                                                parseInt(udpLocalPortField.text),
                                                udpRemoteHostField.text,
                                                parseInt(udpRemotePortField.text)
                                                )
                                }
                                break;
                            }
                        }
                    }

                    Button {
                        Layout.fillWidth: true
                        text: "断开"
                        implicitHeight: 28
                        background: Rectangle {
                            color: parent.pressed ? "#c82333" : "#dc3545"
                            radius: 4
                        }
                        contentItem: Text {
                            text: parent.text
                            color: "white"
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                            font.bold: true
                            font.pixelSize: 12
                        }
                        onClicked: {
                            switch(connectionMode) {
                            case 0: // 串口
                                serial.closePort()
                                break;
                            case 1: // TCP客户端
                                serial.disconnectFromTcpServer()
                                break;
                            case 2: // TCP服务器
                                serial.stopTcpServer()
                                break;
                            case 3: // UDP
                                serial.stopUdp()
                                break;
                            }
                        }
                    }
                }

                // 显示设置
                GroupBox {
                    Layout.fillWidth: true
                    title: "显示设置"
                    padding: 6

                    ColumnLayout {
                        anchors.fill: parent
                        spacing: 4

                        // 自动滚动
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 0

                            CheckBox {
                                id: autoScrollCheckBox
                                text: "自动滚动"
                                checked: autoScroll
                                font.pixelSize: 12
                                onCheckedChanged: {
                                    autoScroll = checked
                                    if (autoScroll) {
                                        forceRefresh()
                                    } else {
                                        lastScrollPosition = scrollView.ScrollBar.vertical.position
                                    }
                                }
                            }

                            Item { // 弹性间隔
                                Layout.fillWidth: true
                            }

                            Button {
                                text: "清空"
                                font.pixelSize: 12
                                implicitHeight: 24
                                implicitWidth: 60
                                background: Rectangle {
                                    color: parent.pressed ? "#5a6268" : "#6c757d"
                                    radius: 3
                                }
                                contentItem: Text {
                                    text: parent.text
                                    color: "white"
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                    font.pixelSize: 11
                                }
                                onClicked: clearReceiveArea()
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            Label {
                                text: "最大行数:"
                                font.pixelSize: 12
                            }
                            TextField {
                                id: maxLinesField
                                Layout.fillWidth: true
                                implicitHeight: 24
                                text: maxLines.toString()
                                font.pixelSize: 12
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
                    }
                }

                // 弹性空间，用于填充底部
                Item {
                    Layout.fillHeight: true
                }
            }
        }

        // 右侧数据收发区域
        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            border.color: "#cccccc"
            border.width: 1
            radius: 4

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 8
                spacing: 5

                // 选项卡
                TabBar {
                    id: tabBar
                    Layout.fillWidth: true

                    TabButton {
                        text: "数据收发"
                        font.pixelSize: 13
                    }
                    TabButton {
                        text: "Lua脚本"
                        font.pixelSize: 13
                    }
                }

                // 视图切换
                StackLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    currentIndex: tabBar.currentIndex

                    // 数据收发选项卡内容
                    ColumnLayout {
                        spacing: 8

                        // 接收数据显示区域
                        GroupBox {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            title: "接收区"
                            padding: 6

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
                                    font.family: "Courier New"
                                    font.pixelSize: 12
                                    background: Rectangle {
                                        color: "#f8f9fa"
                                    }
                                }
                            }
                        }

                        // 发送数据区域
                        GroupBox {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 150
                            title: "发送区"
                            padding: 6

                            ColumnLayout {
                                anchors.fill: parent
                                spacing: 8

                                TextArea {
                                    id: sendArea
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    placeholderText: "输入16进制数据"
                                    font.family: "Courier New"
                                    font.pixelSize: 12
                                    background: Rectangle {
                                        color: "#f8f9fa"
                                        border.color: "#ced4da"
                                        border.width: 1
                                        radius: 3
                                    }
                                }

                                Button {
                                    Layout.fillWidth: true
                                    text: "发送数据"
                                    implicitHeight: 32
                                    enabled: isConnected
                                    background: Rectangle {
                                        color: parent.enabled ? (parent.pressed ? "#0069d9" : "#0d6efd") : "#6c757d"
                                        radius: 4
                                    }
                                    contentItem: Text {
                                        text: parent.text
                                        color: "white"
                                        horizontalAlignment: Text.AlignHCenter
                                        verticalAlignment: Text.AlignVCenter
                                        font.bold: true
                                        font.pixelSize: 13
                                    }
                                    onClicked: {
                                        let data = sendArea.text.trim();
                                        if (data !== "") {
                                            serial.sendData(data, sendHex);
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // Lua脚本选项卡内容
                    ColumnLayout {
                        spacing: 8

                        Text {
                            Layout.alignment: Qt.AlignHCenter
                            text: "Lua脚本编辑器"
                            font.pixelSize: 16
                            font.bold: true
                        }

                        // 脚本控制按钮
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 6

                            Button {
                                text: "打开脚本"
                                implicitHeight: 28
                                implicitWidth: 80
                                font.pixelSize: 12
                                background: Rectangle {
                                    color: parent.pressed ? "#0069d9" : "#0d6efd"
                                    radius: 4
                                }
                                contentItem: Text {
                                    text: parent.text
                                    color: "white"
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                    font.pixelSize: 12
                                }
                                onClicked: openScriptDialog.open()
                            }

                            Button {
                                text: "保存脚本"
                                implicitHeight: 28
                                implicitWidth: 80
                                font.pixelSize: 12
                                background: Rectangle {
                                    color: parent.pressed ? "#138496" : "#17a2b8"
                                    radius: 4
                                }
                                contentItem: Text {
                                    text: parent.text
                                    color: "white"
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                    font.pixelSize: 12
                                }
                                onClicked: saveScriptDialog.open()
                            }

                            Button {
                                text: "执行"
                                implicitHeight: 28
                                implicitWidth: 80
                                font.pixelSize: 12
                                background: Rectangle {
                                    color: parent.pressed ? "#218838" : "#28a745"
                                    radius: 4
                                }
                                contentItem: Text {
                                    text: parent.text
                                    color: "white"
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                    font.pixelSize: 12
                                }
                                onClicked: {
                                    var result = serial.executeLuaScript(scriptArea.text);
                                    appendScriptOutput("[执行] " + result);
                                }
                            }

                            Button {
                                text: "停止"
                                implicitHeight: 28
                                implicitWidth: 80
                                font.pixelSize: 12
                                background: Rectangle {
                                    color: parent.pressed ? "#c82333" : "#dc3545"
                                    radius: 4
                                }
                                contentItem: Text {
                                    text: parent.text
                                    color: "white"
                                    horizontalAlignment: Text.AlignHCenter
                                    verticalAlignment: Text.AlignVCenter
                                    font.pixelSize: 12
                                }
                                onClicked: {
                                    serial.stopLuaScript();
                                    appendScriptOutput("[停止] 脚本已停止");
                                }
                            }

                            Item {
                                Layout.fillWidth: true
                            }
                        }

                        // 脚本编辑
                        GroupBox {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            title: "脚本编辑"
                            padding: 6

                            ScrollView {
                                id: scriptScrollView
                                anchors.fill: parent
                                clip: true

                                TextArea {
                                    id: scriptArea
                                    width: scriptScrollView.width
                                    font.family: "Courier New"
                                    font.pixelSize: 12
                                    placeholderText: "-- 输入Lua脚本\n-- 可用函数:\n-- send(text) - 发送ASCII文本\n-- sendHex(text) - 发送16进制数据\n-- sleep(ms) - 等待毫秒\n-- print(text) - 输出到控制台\n-- getLastData() - 获取最后接收的数据，返回二进制数据\n-- setResponseTimeout(ms) - 设置响应超时时间"
                                    wrapMode: TextArea.Wrap
                                    selectByMouse: true
                                    background: Rectangle {
                                        color: "#f8f9fa"
                                        border.color: "#ced4da"
                                        border.width: 1
                                        radius: 3
                                    }
                                }
                            }
                        }

                        // 脚本输出
                        GroupBox {
                            Layout.fillWidth: true
                            Layout.preferredHeight: 200
                            padding: 6
                            ColumnLayout {
                                anchors.fill: parent
                                spacing: 4
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 8
                                    Label {
                                        text: "脚本输出"
                                        font.pixelSize: 14
                                    }
                                    Label {
                                        text: "最大行数:"
                                        font.pixelSize: 12
                                    }
                                    TextField {
                                        id: maxLinesTextField
                                        text: "30"
                                        implicitHeight: 28
                                        implicitWidth: 80
                                        font.pixelSize: 12
                                        inputMethodHints: Qt.ImhDigitsOnly
                                    }
                                    Item {
                                        Layout.fillWidth: true
                                    } // 占位，使按钮靠右对齐
                                    Button {
                                        text: "清空输出"
                                        implicitHeight: 28
                                        Layout.preferredWidth: 100
                                        font.pixelSize: 12
                                        background: Rectangle {
                                            color: parent.pressed ? "#5a6268" : "#6c757d"
                                            radius: 4
                                        }
                                        contentItem: Text {
                                            text: parent.text
                                            color: "white"
                                            horizontalAlignment: Text.AlignHCenter
                                            verticalAlignment: Text.AlignVCenter
                                            font.pixelSize: 12
                                        }
                                        onClicked: scriptOutputArea.clear()
                                    }
                                }
                                ScrollView {
                                    id: outputScrollView
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    clip: true
                                    TextArea {
                                        id: scriptOutputArea
                                        width: outputScrollView.width
                                        readOnly: true
                                        selectByMouse: true
                                        wrapMode: TextArea.Wrap
                                        font.family: "Courier New"
                                        font.pixelSize: 12
                                        background: Rectangle {
                                            color: "#f8f9fa"
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    Connections {
        target: serial
        // 接收数据处理
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

            if (displayHex && !isHex) {
                // ASCII 转 HEX 显示
                var hexArray = [];
                for (var i = 0; i < data.length; i++) {
                    var code = data.charCodeAt(i);
                    var hex = code.toString(16).toUpperCase();
                    hex = hex.length < 2 ? '0' + hex : hex;
                    hexArray.push(hex);
                }
                displayData = hexArray.join(' ');
            } else if (!displayHex && isHex) {
                // HEX 转 ASCII 显示
                try {
                    var chars = [];
                    var hexValues = data.split(/\s+/).filter(function(h) { return h !== ''; });
                    for (var j = 0; j < hexValues.length; j++) {
                        var hexStr = hexValues[j];
                        if (!/^[0-9A-Fa-f]{1,2}$/.test(hexStr)) {
                            chars.push("？");
                            continue;
                        }
                        var val = parseInt(hexStr, 16);
                        val = val & 0xFF;
                        chars.push((val >= 32 && val <= 126) ? String.fromCharCode(val) : "？");
                    }
                    displayData = chars.join("");
                } catch (e) {
                    displayData = "[转换错误]";
                }
            } else if (isHex) {
                var cleanHex = data.replace(/\s+/g, '');
                var formattedHex = [];
                for (var k = 0; k < cleanHex.length; k += 2) {
                    if (k + 1 < cleanHex.length) {
                        formattedHex.push(cleanHex.substr(k, 2));
                    } else {
                        formattedHex.push(cleanHex.substr(k, 1));
                    }
                }
                displayData = formattedHex.join(' ');
            }

            // 更新显示缓冲区
            bufferText += "\n[发送] " + timestamp + " " + displayData;
        }

        function onConnectionStatusChanged(connected, message) {
            isConnected = connected;
            statusMessage = message;
        }

        function onLuaOutput(output) {
            appendScriptOutput("[输出] " + output);
        }

        function onCurrentScriptChanged() {
            scriptArea.text = serial.currentScript;
        }
    }

    function appendScriptOutput(text) {
        if (!scriptOutputArea.text) {
            scriptOutputArea.text = text;
            scriptcurrentLines = text.split('\n').length;
        } else {
            let lines = scriptOutputArea.text.split('\n');
            lines.push(text);
            let maxLines = parseInt(maxLinesTextField.text) || 100;
            if (lines.length > maxLines) {
                lines = lines.slice(lines.length - maxLines);
            }
            scriptOutputArea.text = lines.join('\n');
            scriptcurrentLines = lines.length;
        }
        scriptOutputArea.cursorPosition = scriptOutputArea.text.length;
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
