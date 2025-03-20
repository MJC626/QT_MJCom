import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Window

Item {
    id: root
    width: parent.width
    height: parent.height

    // 存储解析后的数据
    property var parsedData: []
    property string currentKey: ""  // 当前选中的寄存器类型和地址组合键
    property var knownKeys: []      // 已知的寄存器类型和地址组合键列表
    property var valueLabels: ({})  // 存储用户自定义的值标签
    property var valueUnits: ({})   // 存储用户自定义的值单位
    property var valueFormulas: ({})   // 存储用户自定义的数学公式

    function setData(text) {
        if (!text || text.trim() === "") return
        parseData(text)
        updateVisualization()
    }

    function forceUpdate() {
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

    // 应用数学公式到值
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

            var result = numValue
            // 支持简单的数学公式
            if (formula.startsWith("X") || formula.startsWith("x")) {
                var factor = parseFloat(formula.substring(1))
                if (!isNaN(factor)) {
                    result = numValue * factor
                }
            } else if (formula.startsWith("+")) {
                var addend = parseFloat(formula.substring(1))
                if (!isNaN(addend)) {
                    result = numValue + addend
                }
            } else if (formula.startsWith("-")) {
                var subtrahend = parseFloat(formula.substring(1))
                if (!isNaN(subtrahend)) {
                    result = numValue - subtrahend
                }
            } else if (formula.startsWith("/")) {
                var divisor = parseFloat(formula.substring(1))
                if (!isNaN(divisor) && divisor !== 0) {
                    result = numValue / divisor
                }
            }

            // 格式化结果，最多保留两位小数
            return result.toFixed(2).replace(/\.00$/, "")
        } catch (e) {
            console.error("公式应用失败: ", e)
            return value
        }
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

        // 初始化当前键的标签和单位对象
        if (!valueLabels[currentKey]) {
            valueLabels[currentKey] = {}
        }

        if (!valueUnits[currentKey]) {
            valueUnits[currentKey] = {}
        }

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

            // 获取标签和单位，如果没有则为空
            var label1 = valueLabels[currentKey][addr1Hex] || ""
            var label2 = valueLabels[currentKey][addr2Hex] || ""
            var unit1 = valueUnits[currentKey][addr1Hex] || ""
            var unit2 = valueUnits[currentKey][addr2Hex] || ""

            dataListModel.append({
                address1: addr1Hex,
                value1: value1,
                rawValue1: rawValue1,
                address2: addr2Hex,
                value2: value2,
                rawValue2: rawValue2,
                hasSecondColumn: idx2 < valuesCount,
                label1: label1,
                label2: label2,
                unit1: unit1,
                unit2: unit2,
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

    // 保存自定义标签、单位和公式的函数
    function saveLabelUnitAndFormula(address, label, unit, formula) {
        if (!valueLabels[currentKey]) {
            valueLabels[currentKey] = {}
        }
        if (!valueUnits[currentKey]) {
            valueUnits[currentKey] = {}
        }
        if (!valueFormulas[currentKey]) {
            valueFormulas[currentKey] = {}
        }

        valueLabels[currentKey][address] = label
        valueUnits[currentKey][address] = unit
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

                            Text {
                                id: valueText1
                                anchors.centerIn: parent
                                text: {
                                    var displayText = ""
                                    if (model.label1) {
                                        displayText = model.label1 + ": "
                                    }
                                    displayText += model.value1
                                    if (model.unit1) {
                                        displayText += " " + model.unit1
                                    }
                                    return displayText
                                }
                                font.family: "Courier New"
                                color: model.value1 === "ON" ? "green" :
                                       model.value1 === "OFF" ? "red" : "black"
                            }

                            MouseArea {
                                anchors.fill: parent
                                onDoubleClicked: {
                                    labelEditor.address = model.address1
                                    labelEditor.labelText = model.label1
                                    labelEditor.unitText = model.unit1
                                    labelEditor.formulaText = model.formula1
                                    labelEditor.valueText = model.rawValue1
                                    labelEditor.open()
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

                            Text {
                                id: valueText2
                                anchors.centerIn: parent
                                text: {
                                    if (!model.hasSecondColumn) return ""

                                    var displayText = ""
                                    if (model.label2) {
                                        displayText = model.label2 + ": "
                                    }
                                    displayText += model.value2
                                    if (model.unit2) {
                                        displayText += " " + model.unit2
                                    }
                                    return displayText
                                }
                                font.family: "Courier New"
                                color: model.value2 === "ON" ? "green" :
                                       model.value2 === "OFF" ? "red" : "black"
                            }

                            MouseArea {
                                anchors.fill: parent
                                enabled: model.hasSecondColumn
                                onDoubleClicked: {
                                    if (model.hasSecondColumn) {
                                        labelEditor.address = model.address2
                                        labelEditor.labelText = model.label2
                                        labelEditor.unitText = model.unit2
                                        labelEditor.formulaText = model.formula2
                                        labelEditor.valueText = model.rawValue2
                                        labelEditor.open()
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

    // 标签编辑对话框
    Dialog {
        id: labelEditor
        title: "编辑值标签与公式"
        modal: true
        width: 360
        height: 280
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        anchors.centerIn: Overlay.overlay

        property string address: ""
        property string labelText: ""
        property string unitText: ""
        property string formulaText: ""
        property string valueText: ""

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 10
            spacing: 10

            Label {
                text: "地址: " + labelEditor.address
                Layout.fillWidth: true
            }

            Label {
                text: "原始值: " + labelEditor.valueText
                Layout.fillWidth: true
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 5

                Label {
                    text: "自定义标签:"
                }

                TextField {
                    id: labelField
                    Layout.fillWidth: true
                    placeholderText: ""
                    text: labelEditor.labelText
                }
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
                    placeholderText: "支持X,+,-,/"
                    text: labelEditor.formulaText
                }

                Label {
                    text: "计算后:"
                    visible: formulaField.text.trim() !== "" &&
                             labelEditor.valueText !== "ON" &&
                             labelEditor.valueText !== "OFF"
                }

                Label {
                    id: previewLabel
                    text: {
                        if (formulaField.text.trim() === "" ||
                            labelEditor.valueText === "ON" ||
                            labelEditor.valueText === "OFF") {
                            return ""
                        }

                        return applyFormula(labelEditor.valueText, formulaField.text)
                    }
                    visible: formulaField.text.trim() !== "" &&
                             labelEditor.valueText !== "ON" &&
                             labelEditor.valueText !== "OFF"
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 5

                Label {
                    text: "单位符号:"
                }

                TextField {
                    id: unitField
                    Layout.preferredWidth: 60
                    placeholderText: ""
                    text: labelEditor.unitText
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignRight
                spacing: 10

                Button {
                    text: "取消"
                    onClicked: labelEditor.close()
                }

                Button {
                    text: "确定"
                    onClicked: {
                        saveLabelUnitAndFormula(labelEditor.address, labelField.text, unitField.text, formulaField.text)
                        updateVisualization()
                        labelEditor.close()
                    }
                }
            }
        }

        // 预览计算结果的逻辑
        Connections {
            target: formulaField
            function onTextChanged() {
                if (labelEditor.valueText !== "ON" && labelEditor.valueText !== "OFF") {
                    previewLabel.text = applyFormula(labelEditor.valueText, formulaField.text)
                }
            }
        }
    }
}
