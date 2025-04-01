import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Window
import QtCharts

Item {
    id: root
    width: parent.width
    height: parent.height

    // 存储解析后的数据
    property var parsedData: []
    property string currentKey: ""  // 当前选中的寄存器类型和地址组合键
    property var knownKeys: []      // 已知的寄存器类型和地址组合键列表
    property var valueFormulas: ({})   // 存储用户自定义的数学公式

    // 曲线图数据属性
    property var dataHistory: ({})     // 存储每个地址的历史数据
    property var recordIntervals: ({}) // 存储每个地址的记录间隔

    // 卡尔曼滤波器参数
    property real kalmanP: 1.0
    property real kalmanX: 0.0
    property real kalmanQ: 0.01    // 过程噪声协方差
    property real kalmanR: 0.1     // 测量噪声协方差

    // 记录定时器
    Timer {
        id: recordTimer
        interval: 1000
        running: false
        repeat: true
        onTriggered: {
            if (chartWindow.visible && chartWindow.isRecording && chartWindow.currentItemId) {
                var currentValue = getCurrentValueById(chartWindow.currentItemId);
                if (currentValue !== null && currentValue !== "" && currentValue !== "ON" && currentValue !== "OFF") {
                    var numValue = parseFloat(currentValue);
                    if (!isNaN(numValue)) {
                        if (!dataHistory[chartWindow.currentItemId]) {
                            dataHistory[chartWindow.currentItemId] = {
                                data: [],
                                isRecording: true
                            };
                        }
                        dataHistory[chartWindow.currentItemId].data.push({
                            timestamp: new Date().getTime(),
                            value: numValue
                        });
                    }
                }
            }
        }
    }

    // 获取当前值的函数
    function getCurrentValueById(id) {
        // 解析ID格式 - 假设格式为"地址_列"，例如"0x0001_1"（第一列）或"0x0001_2"（第二列）
        var parts = id.split("_");
        if (parts.length !== 2) return null;

        var address = parts[0];
        var column = parseInt(parts[1]);

        // 查找对应的数据
        for (var i = 0; i < dataListModel.count; i++) {
            var item = dataListModel.get(i);
            if (column === 1 && item.address1 === address) {
                return item.value1;
            } else if (column === 2 && item.address2 === address) {
                return item.value2;
            }
        }
        return null;
    }

    // 卡尔曼滤波函数
    function kalmanFilter(measurement) {
        // 预测步骤
        kalmanP = kalmanP + kalmanQ;

        // 更新步骤
        const kalmanK = kalmanP / (kalmanP + kalmanR);  // 卡尔曼增益
        kalmanX = kalmanX + kalmanK * (measurement - kalmanX);
        kalmanP = (1 - kalmanK) * kalmanP;

        return kalmanX;
    }

    function setData(text) {
        if (!text || text.trim() === "") return
        parseData(text)
        updateVisualization()
    }

    function parseData(text) {
        parsedData = [];

        var lines = text.split('\n');
        for (var i = lines.length - 1; i >= 0; i--) {
            var line = lines[i]
            if (line.includes("[输出]")) {
                // 更新正则表达式以匹配所有格式
                var dataMatch = /\[输出\]\s+(.*?)\s+起始地址:(0x[0-9A-Fa-f]+)(?:\s+格式:(.*?))?\s+值:(.*)/
                var matches = line.match(dataMatch)

                if (matches) {
                    var dataType = matches[1]
                    var address = matches[2]
                    var format = matches[3] || ""  // 对于线圈状态和离散输入，format可能为空
                    var valuesStr = matches[4]

                    // 根据数据类型处理值
                    var values = []
                    if (dataType === "线圈状态" || dataType === "离散输入") {
                        values = valuesStr.split(',').map(function(item) {
                            return item.trim() === "1" ? true : false
                        })
                    } else {
                        values = valuesStr.split(',').map(function(item) {
                            return item.trim()
                        })
                    }

                    // 创建唯一键
                    var key = dataType + "_" + address

                    parsedData.push({
                        key: key,
                        type: dataType,
                        address: address,
                        format: format,
                        values: values
                    })
                }
            }
        }

        // 更新组合键下拉菜单
        updateKeysComboBox()
    }

    function updateKeysComboBox() {
        // 获取唯一的组合键列表
        var uniqueKeys = parsedData.reduce(function(keys, item) {
            if (!keys.includes(item.key)) {
                keys.push(item.key)
            }
            return keys
        }, [])

        // 检查是否有新的组合键
        var hasNewKeys = false
        for (var i = 0; i < uniqueKeys.length; i++) {
            if (!knownKeys.includes(uniqueKeys[i])) {
                hasNewKeys = true
                break
            }
        }

        if (knownKeys.length === 0 || hasNewKeys) {
            var currentSelection = dataTypeComboBox.currentText
            dataTypeComboBox.currentTextChanged.disconnect(onKeyChanged)

            knownKeys = uniqueKeys.slice()
            // 创建显示用的标签
            var displayLabels = knownKeys.map(function(key) {
                var item = parsedData.find(item => item.key === key)
                return item.type + " (" + item.address + ")"
            })

            dataTypeComboBox.model = displayLabels

            if (currentSelection && displayLabels.includes(currentSelection)) {
                dataTypeComboBox.currentIndex = displayLabels.indexOf(currentSelection)
            } else if (displayLabels.length > 0) {
                currentKey = knownKeys[0]
                dataTypeComboBox.currentIndex = 0
            }

            dataTypeComboBox.currentTextChanged.connect(onKeyChanged)
        }
    }

    function onKeyChanged() {
        var index = dataTypeComboBox.currentIndex
        if (index >= 0 && index < knownKeys.length) {
            var newKey = knownKeys[index]
            if (newKey !== currentKey) {
                currentKey = newKey
                updateVisualization()
            }
        }
    }

    // 公式计算函数，支持复杂表达式
    function applyFormula(value, formula) {
        if (!formula || formula.trim() === "" || value === "ON" || value === "OFF") {
            return value
        }

        try {
            // 转换为数字（如果是数字的话）
            var numValue = parseFloat(value)
            if (isNaN(numValue)) {
                return value
            }

            // 替换公式中的 'X' 为实际值
            var evalFormula = formula.replace(/X/gi, numValue.toString())
            var result

            // 解析和计算公式
            if (evalFormula.match(/^[\d\s\+\-\*\/\(\)\.]+$/)) {
                result = Function('"use strict"; return (' + evalFormula + ')')()
            } else {
                // 如果公式包含不安全字符，则尝试使用旧的简单公式处理方法
                result = processSimpleFormula(numValue, formula)
            }

            // 格式化结果，最多保留四位小数
            return result.toFixed(4).replace(/\.00$/, "")
        } catch (e) {
            console.error("公式应用失败: ", e)
            return value
        }
    }

    // 处理简单公式的备用方法
    function processSimpleFormula(value, formula) {
        if (formula.startsWith("X") || formula.startsWith("x")) {
            var factor = parseFloat(formula.substring(1))
            if (!isNaN(factor)) {
                return value * factor
            }
        } else if (formula.startsWith("+")) {
            var addend = parseFloat(formula.substring(1))
            if (!isNaN(addend)) {
                return value + addend
            }
        } else if (formula.startsWith("-")) {
            var subtrahend = parseFloat(formula.substring(1))
            if (!isNaN(subtrahend)) {
                return value - subtrahend
            }
        } else if (formula.startsWith("/")) {
            var divisor = parseFloat(formula.substring(1))
            if (!isNaN(divisor) && divisor !== 0) {
                return value / divisor
            }
        }
        return value
    }

    function updateVisualization() {
        if (parsedData.length === 0) return

        var dataSet = parsedData.find(function(item) {
            return item.key === currentKey
        })

        if (!dataSet) {
            if (parsedData.length > 0) {
                dataSet = parsedData[0]
                currentKey = dataSet.key

                var index = knownKeys.indexOf(currentKey)
                if (index >= 0 && index !== dataTypeComboBox.currentIndex) {
                    dataTypeComboBox.currentTextChanged.disconnect(onKeyChanged)
                    dataTypeComboBox.currentIndex = index
                    dataTypeComboBox.currentTextChanged.connect(onKeyChanged)
                }
            } else {
                return
            }
        }

        // 更新格式标签
        formatLabel.text = dataSet.format ? "格式: " + dataSet.format : ""

        // 更新数据列表
        updateDataList(dataSet)
    }

    function updateDataList(dataSet) {
        if (!dataSet || !dataSet.values) return

        var scrollPos = dataListView.contentY
        dataListModel.clear()

        var baseAddress = parseInt(dataSet.address, 16)
        var valuesCount = dataSet.values.length
        var rowCount = Math.ceil(valuesCount / 2)

        // 初始化当前键的公式对象
        if (!valueFormulas[currentKey]) {
            valueFormulas[currentKey] = {}
        }

        for (var j = 0; j < rowCount; j++) {
            var idx1 = j * 2
            var idx2 = j * 2 + 1

            var addr1 = baseAddress + idx1
            var addr1Hex = "0x" + addr1.toString(16).toUpperCase().padStart(4, '0')
            var rawValue1 = idx1 < valuesCount ? (dataSet.values[idx1] === true ? "ON" :
                         dataSet.values[idx1] === false ? "OFF" : dataSet.values[idx1]) : ""

            // 获取公式并应用
            var formula1 = valueFormulas[currentKey][addr1Hex] || ""
            var value1 = applyFormula(rawValue1, formula1)

            var addr2 = baseAddress + idx2
            var addr2Hex = "0x" + addr2.toString(16).toUpperCase().padStart(4, '0')
            var rawValue2 = idx2 < valuesCount ? (dataSet.values[idx2] === true ? "ON" :
                         dataSet.values[idx2] === false ? "OFF" : dataSet.values[idx2]) : ""

            // 获取公式并应用
            var formula2 = valueFormulas[currentKey][addr2Hex] || ""
            var value2 = applyFormula(rawValue2, formula2)

            dataListModel.append({
                address1: addr1Hex,
                value1: value1,
                rawValue1: rawValue1,
                address2: addr2Hex,
                value2: value2,
                rawValue2: rawValue2,
                hasSecondColumn: idx2 < valuesCount,
                formula1: formula1,
                formula2: formula2
            })
        }

        dataListView.contentY = scrollPos
    }

    function clearData() {
        parsedData = []
        knownKeys = []
        currentKey = ""
        formatLabel.text = ""
        dataListModel.clear()
        dataTypeComboBox.model = []
    }

    // 保存公式的函数
    function saveFormula(address, formula) {
        if (!valueFormulas[currentKey]) {
            valueFormulas[currentKey] = {}
        }
        valueFormulas[currentKey][address] = formula
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 10
        spacing: 10

        RowLayout {
            Layout.fillWidth: true
            spacing: 10

            Label {
                text: "寄存器类型和地址:"
                font.pixelSize: 14
            }

            ComboBox {
                id: dataTypeComboBox
                model: []
                Component.onCompleted: {
                    currentTextChanged.connect(onKeyChanged)
                }
            }

            Label {
                id: formatLabel
                text: ""
                font.pixelSize: 14
                visible: text !== ""
            }

            Item {
                Layout.fillWidth: true
            }

            Button {
                text: "清除数据"
                onClicked: clearData()
                Layout.preferredHeight: dataTypeComboBox.height
                Layout.preferredWidth: 80
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            color: "white"
            border.color: "#e0e0e0"
            border.width: 1

            ListModel {
                id: dataListModel
            }

            ListView {
                id: dataListView
                anchors.fill: parent
                anchors.margins: 5
                clip: true
                model: dataListModel
                boundsBehavior: Flickable.StopAtBounds
                flickDeceleration: 1500
                cacheBuffer: 1000

                header: Rectangle {
                    width: parent.width
                    height: 30
                    color: "#f0f0f0"

                    Row {
                        anchors.fill: parent

                        Rectangle {
                            width: parent.width * 0.15
                            height: parent.height
                            color: "transparent"
                            border.width: 1
                            border.color: "#d0d0d0"

                            Text {
                                anchors.centerIn: parent
                                text: "地址"
                                font.bold: true
                            }
                        }

                        Rectangle {
                            width: parent.width * 0.35
                            height: parent.height
                            color: "transparent"
                            border.width: 1
                            border.color: "#d0d0d0"

                            Text {
                                anchors.centerIn: parent
                                text: "值"
                                font.bold: true
                            }
                        }

                        Rectangle {
                            width: parent.width * 0.15
                            height: parent.height
                            color: "transparent"
                            border.width: 1
                            border.color: "#d0d0d0"

                            Text {
                                anchors.centerIn: parent
                                text: "地址"
                                font.bold: true
                            }
                        }

                        Rectangle {
                            width: parent.width * 0.35
                            height: parent.height
                            color: "transparent"
                            border.width: 1
                            border.color: "#d0d0d0"

                            Text {
                                anchors.centerIn: parent
                                text: "值"
                                font.bold: true
                            }
                        }
                    }
                }

                delegate: Rectangle {
                    width: dataListView.width
                    height: 30
                    color: index % 2 === 0 ? "#ffffff" : "#f8f8f8"

                    Row {
                        anchors.fill: parent

                        Rectangle {
                            width: parent.width * 0.15
                            height: parent.height
                            color: "transparent"
                            border.width: 1
                            border.color: "#e0e0e0"

                            Text {
                                anchors.centerIn: parent
                                text: model.address1
                                font.family: "Courier New"
                            }
                        }

                        Rectangle {
                            id: valueRect1
                            width: parent.width * 0.35
                            height: parent.height
                            color: "transparent"
                            border.width: 1
                            border.color: "#e0e0e0"

                            RowLayout {
                                anchors.fill: parent
                                anchors.margins: 2
                                spacing: 5

                                Text {
                                    id: valueText1
                                    Layout.fillWidth: true
                                    horizontalAlignment: Text.AlignHCenter
                                    text: model.value1
                                    font.family: "Courier New"
                                    color: model.value1 === "ON" ? "green" :
                                           model.value1 === "OFF" ? "red" : "black"
                                }

                                Button {
                                    id: chartButton1
                                    Layout.preferredHeight: parent.height - 4
                                    Layout.preferredWidth: height
                                    visible: model.value1 !== "" && model.value1 !== "ON" && model.value1 !== "OFF"
                                    text: "📈"
                                    font.pixelSize: 10
                                    onClicked: {
                                        var itemId = model.address1 + "_1";
                                        chartWindow.currentItemId = itemId;
                                        chartWindow.title = "地址 " + model.address1 + " 的数据曲线";
                                        chartWindow.recordInterval = recordIntervals[itemId] || 1000;
                                        chartWindow.isRecording = dataHistory[itemId] ? dataHistory[itemId].isRecording : false;
                                        chartWindow.show();
                                    }
                                }
                            }

                            MouseArea {
                                anchors.fill: parent
                                anchors.rightMargin: chartButton1.width + 10
                                onDoubleClicked: {
                                    formulaEditor.address = model.address1
                                    formulaEditor.formulaText = model.formula1
                                    formulaEditor.valueText = model.rawValue1
                                    formulaEditor.open()
                                }
                            }
                        }

                        Rectangle {
                            width: parent.width * 0.15
                            height: parent.height
                            color: "transparent"
                            border.width: 1
                            border.color: "#e0e0e0"

                            Text {
                                anchors.centerIn: parent
                                text: model.hasSecondColumn ? model.address2 : ""
                                font.family: "Courier New"
                            }
                        }

                        Rectangle {
                            id: valueRect2
                            width: parent.width * 0.35
                            height: parent.height
                            color: "transparent"
                            border.width: 1
                            border.color: "#e0e0e0"

                            RowLayout {
                                anchors.fill: parent
                                anchors.margins: 2
                                spacing: 5
                                enabled: model.hasSecondColumn

                                Text {
                                    id: valueText2
                                    Layout.fillWidth: true
                                    horizontalAlignment: Text.AlignHCenter
                                    text: model.hasSecondColumn ? model.value2 : ""
                                    font.family: "Courier New"
                                    color: model.value2 === "ON" ? "green" :
                                           model.value2 === "OFF" ? "red" : "black"
                                }

                                Button {
                                    id:chartButton2
                                    Layout.preferredHeight: parent.height - 4
                                    Layout.preferredWidth: height
                                    visible: model.hasSecondColumn && model.value2 !== "" &&
                                             model.value2 !== "ON" && model.value2 !== "OFF"
                                    text: "📈"
                                    font.pixelSize: 10
                                    onClicked: {
                                        var itemId = model.address2 + "_2";
                                        chartWindow.currentItemId = itemId;
                                        chartWindow.title = "地址 " + model.address2 + " 的数据曲线";
                                        chartWindow.recordInterval = recordIntervals[itemId] || 1000;
                                        chartWindow.isRecording = dataHistory[itemId] ? dataHistory[itemId].isRecording : false;
                                        chartWindow.show();
                                    }
                                }
                            }

                            MouseArea {
                                anchors.fill: parent
                                anchors.rightMargin: chartButton1.width + 10
                                enabled: model.hasSecondColumn
                                onDoubleClicked: {
                                    if (model.hasSecondColumn) {
                                        formulaEditor.address = model.address2
                                        formulaEditor.formulaText = model.formula2
                                        formulaEditor.valueText = model.rawValue2
                                        formulaEditor.open()
                                    }
                                }
                            }
                        }
                    }
                }

                ScrollBar.vertical: ScrollBar {
                    policy: ScrollBar.AsNeeded
                    interactive: true
                }
            }
        }
    }

    // 公式编辑对话框
    Dialog {
        id: formulaEditor
        title: "编辑数学公式"
        modal: true
        width: 400
        height: 200
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        anchors.centerIn: Overlay.overlay

        property string address: ""
        property string formulaText: ""
        property string valueText: ""

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 10
            spacing: 10

            Label {
                text: "地址: " + formulaEditor.address
                Layout.fillWidth: true
            }

            Label {
                text: "原始值: " + formulaEditor.valueText
                Layout.fillWidth: true
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 5

                Label {
                    text: "数学公式:"
                }

                TextField {
                    id: formulaField
                    Layout.fillWidth: true
                    placeholderText: "例如: (X-10)*3+10"
                    text: formulaEditor.formulaText
                }

                Label {
                    text: "计算后:"
                    visible: formulaField.text.trim() !== "" &&
                             formulaEditor.valueText !== "ON" &&
                             formulaEditor.valueText !== "OFF"
                }

                Label {
                    id: previewLabel
                    text: {
                        if (formulaField.text.trim() === "" ||
                            formulaEditor.valueText === "ON" ||
                            formulaEditor.valueText === "OFF") {
                            return ""
                        }

                        return applyFormula(formulaEditor.valueText, formulaField.text)
                    }
                    visible: formulaField.text.trim() !== "" &&
                             formulaEditor.valueText !== "ON" &&
                             formulaEditor.valueText !== "OFF"
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignRight
                spacing: 10

                Button {
                    text: "清除公式"
                    onClicked: {
                        formulaField.text = ""
                    }
                }

                Button {
                    text: "取消"
                    onClicked: formulaEditor.close()
                }

                Button {
                    text: "确定"
                    onClicked: {
                        saveFormula(formulaEditor.address, formulaField.text)
                        updateVisualization()
                        formulaEditor.close()
                    }
                }
            }
        }

        // 预览计算结果的逻辑
        Connections {
            target: formulaField
            function onTextChanged() {
                if (formulaEditor.valueText !== "ON" && formulaEditor.valueText !== "OFF") {
                    previewLabel.text = applyFormula(formulaEditor.valueText, formulaField.text)
                }
            }
        }
    }

    // 曲线图窗口
    Window {
        id: chartWindow
        width: 800
        height: 600
        visible: false
        title: "数据曲线图"

        property string currentItemId: ""  // 当前选中的项目ID
        property bool isRecording: false   // 是否正在记录
        property int recordInterval: 1000  // 记录间隔
        property bool useKalmanFilter: false // 是否使用卡尔曼滤波
        property int maxDataPoints: 100    // X轴最大数据点数
        property real kalmanQ: 0.01        // 卡尔曼滤波器 Q 值
        property real kalmanR: 0.1         // 卡尔曼滤波器 R 值

        // 卡尔曼滤波函数
        function kalmanFilter(measurement) {
            // 预测步骤
            kalmanP = kalmanP + kalmanQ;

            // 更新步骤
            const kalmanK = kalmanP / (kalmanP + kalmanR);  // 卡尔曼增益
            kalmanX = kalmanX + kalmanK * (measurement - kalmanX);
            kalmanP = (1 - kalmanK) * kalmanP;

            return kalmanX;
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 10
            spacing: 10

            // 控制面板
            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                Label { text: "记录间隔(ms):" }

                SpinBox {
                    id: intervalSpinBox
                    from: 100
                    to: 10000
                    stepSize: 100
                    value: chartWindow.recordInterval
                    onValueChanged: {
                        if (chartWindow.currentItemId) {
                            recordIntervals[chartWindow.currentItemId] = value;
                            recordTimer.interval = value;
                        }
                    }
                }

                Button {
                    text: chartWindow.isRecording ? "停止记录" : "开始记录"
                    onClicked: {
                        chartWindow.isRecording = !chartWindow.isRecording;
                        if (chartWindow.isRecording) {
                            if (!dataHistory[chartWindow.currentItemId]) {
                                dataHistory[chartWindow.currentItemId] = {
                                    data: [],
                                    isRecording: true
                                };
                            } else {
                                dataHistory[chartWindow.currentItemId].isRecording = true;
                            }
                            recordTimer.start();
                        } else {
                            if (dataHistory[chartWindow.currentItemId]) {
                                dataHistory[chartWindow.currentItemId].isRecording = false;
                            }
                            recordTimer.stop();
                        }
                    }
                }

                Button {
                    text: "清除数据"
                    onClicked: {
                        if (dataHistory[chartWindow.currentItemId]) {
                            dataHistory[chartWindow.currentItemId].data = [];
                            lineSeries.clear();
                        }
                    }
                }

                CheckBox {
                    text: "卡尔曼滤波"
                    checked: chartWindow.useKalmanFilter
                    onCheckedChanged: {
                        chartWindow.useKalmanFilter = checked;
                        // 重置卡尔曼滤波器状态
                        kalmanP = 1.0;
                        kalmanX = 0.0;
                    }
                }
            }

            // X轴数据点控制面板
            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                Label { text: "X轴最大点数:" }
                SpinBox {
                    id: maxPointsSpinBox
                    from: 10
                    to: 1000
                    stepSize: 10
                    value: chartWindow.maxDataPoints
                    onValueChanged: {
                        chartWindow.maxDataPoints = value;
                    }
                }
            }

            // 卡尔曼滤波参数控制面板
            RowLayout {
                Layout.fillWidth: true
                spacing: 10
                visible: chartWindow.useKalmanFilter

                Label { text: "Q值(过程噪声):" }
                SpinBox {
                    id: spinBoxQ
                    from: 1  // 对应 0.01
                    to: 10000  // 对应 100
                    stepSize: 1  // 对应 0.01
                    value: Math.round(chartWindow.kalmanQ * 100)
                    editable: true

                    property int decimals: 2
                    onValueModified: {
                        chartWindow.kalmanQ = value / 100;
                        // 重置滤波器状态
                        kalmanP = 1.0;
                        kalmanX = 0.0;
                    }

                    textFromValue: function(value, locale) {
                        return Number(value / 100).toLocaleString(locale, 'f', decimals)
                    }

                    valueFromText: function(text, locale) {
                        return Math.round(Number.fromLocaleString(locale, text) * 100)
                    }
                }

                Label { text: "R值(测量噪声):" }
                SpinBox {
                    id: spinBoxR
                    from: 1  // 对应 0.01
                    to: 10000  // 对应 100
                    stepSize: 1  // 对应 0.01
                    value: Math.round(chartWindow.kalmanR * 100)
                    editable: true

                    property int decimals: 2
                    onValueModified: {
                        chartWindow.kalmanR = value / 100;
                        // 重置滤波器状态
                        kalmanP = 1.0;
                        kalmanX = 0.0;
                    }

                    textFromValue: function(value, locale) {
                        return Number(value / 100).toLocaleString(locale, 'f', decimals)
                    }

                    valueFromText: function(text, locale) {
                        return Math.round(Number.fromLocaleString(locale, text) * 100)
                    }
                }
            }

            // 图表视图
            ChartView {
                id: chartView
                Layout.fillWidth: true
                Layout.fillHeight: true
                antialiasing: true

                DateTimeAxis {
                    id: axisX
                    format: "mm:ss"
                    titleText: "时间"
                }

                ValueAxis {
                    id: axisY
                    titleText: "值"
                }

                LineSeries {
                    id: lineSeries
                    axisX: axisX
                    axisY: axisY
                    name: chartWindow.title
                }
            }
        }

        // 图表更新定时器
        Timer {
            id: updateTimer
            interval: 300
            running: chartWindow.visible && chartWindow.isRecording
            repeat: true
            onTriggered: {
                if (chartWindow.currentItemId && dataHistory[chartWindow.currentItemId] && dataHistory[chartWindow.currentItemId].isRecording) {
                    const data = dataHistory[chartWindow.currentItemId].data;
                    lineSeries.clear();
                    if (data.length > 0) {
                        // 限制数据点数量
                        let displayData = data;
                        if (data.length > chartWindow.maxDataPoints) {
                            displayData = data.slice(data.length - chartWindow.maxDataPoints);
                        }

                        // 更新X轴范围
                        const firstTime = displayData[0].timestamp;
                        const lastTime = displayData[displayData.length - 1].timestamp;
                        axisX.min = new Date(firstTime);
                        axisX.max = new Date(lastTime);

                        // 更新Y轴范围
                        let minY = displayData[0].value;
                        let maxY = displayData[0].value;

                        // 绘制数据点
                        displayData.forEach(point => {
                            let value = point.value;
                            if (chartWindow.useKalmanFilter) {
                                value = chartWindow.kalmanFilter(value);
                            }
                            lineSeries.append(point.timestamp, value);
                            minY = Math.min(minY, value);
                            maxY = Math.max(maxY, value);
                        });

                        // 设置Y轴范围
                        if (minY === maxY) {
                            axisY.min = minY - 1;
                            axisY.max = maxY + 1;
                        } else {
                            const padding = (maxY - minY) * 0.1;
                            axisY.min = minY - padding;
                            axisY.max = maxY + padding;
                        }
                    }
                }
            }
        }
    }
}
