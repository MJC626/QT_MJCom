#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QSerialPort>
#include <QSerialPortInfo>
#include <QTcpSocket>
#include <QTcpServer>
#include <QUdpSocket>
#include <QTimer>
#include <QFile>
#include <QTextStream>
#include <QThread>
#include <QMutex>
#include <QWaitCondition>
#include <QIcon>


// Lua头文件
extern "C" {
#include <lua.h>
#include <lauxlib.h>
#include <lualib.h>
}

int nres = 0;  // 用于接收返回值数量


// SerialHandler 类用于处理串口和TCP UDP操作
class SerialHandler : public QObject {
    Q_OBJECT
    Q_PROPERTY(QString currentScript READ getCurrentScript WRITE setCurrentScript NOTIFY currentScriptChanged)
    bool hasNewData = false;//标志变量

public:
    explicit SerialHandler(QObject *parent = nullptr) : QObject(parent) {
        // 连接串口信号和槽
        connect(&serial, &QSerialPort::readyRead, this, &SerialHandler::readSerialData);

        // 连接TCP信号和槽
        connect(&tcpSocket, &QTcpSocket::readyRead, this, &SerialHandler::readTcpData);
        connect(&tcpSocket, &QTcpSocket::connected, this, &SerialHandler::onTcpConnected);
        connect(&tcpSocket, &QTcpSocket::disconnected, this, &SerialHandler::onTcpDisconnected);
        connect(&tcpSocket, &QTcpSocket::errorOccurred, this, &SerialHandler::onTcpError);

        // 连接 TCP 服务器的信号和槽
        connect(&tcpServer, &QTcpServer::newConnection, this, &SerialHandler::onNewClientConnected);

        // 连接 UDP 信号和槽
        connect(&udpSocket, &QUdpSocket::readyRead, this, &SerialHandler::readUdpData);

        // 创建协程恢复定时器
        connect(&coroutineTimer, &QTimer::timeout, this, &SerialHandler::resumeCoroutine);

        // 创建等待响应超时定时器
        connect(&responseTimer, &QTimer::timeout, this, &SerialHandler::handleResponseTimeout);

        // 初始化Lua
        initLua();
    }

    ~SerialHandler() {
        // 清理Lua状态
        if (L) {
            lua_close(L);
            L = nullptr;
        }
    }

    // 脚本访问方法
    QString getCurrentScript() const {
        return currentScript;
    }

    void setCurrentScript(const QString &script) {
        if (currentScript != script) {
            currentScript = script;
            emit currentScriptChanged();
        }
    }

    // 打开串口
    Q_INVOKABLE void openPort(const QString &portName, const QString &baudRate,
                              const QString &dataBits, const QString &stopBits,
                              const QString &parity) {
        // 关闭可能已经打开的TCP连接
        if (tcpSocket.state() == QTcpSocket::ConnectedState) {
            tcpSocket.disconnectFromHost();
        }

        // 关闭TCP服务器
        if (tcpServer.isListening()) {
            stopTcpServer();
        }

        // 关闭UDP连接
        if (currentMode == ModeUdp) {
            stopUdp();
        }

        serial.setPortName(portName);
        serial.setBaudRate(baudRate.toInt());
        serial.setDataBits(static_cast<QSerialPort::DataBits>(dataBits.toInt()));
        serial.setStopBits(static_cast<QSerialPort::StopBits>(stopBits.toInt()));
        serial.setParity(parity == "None" ? QSerialPort::NoParity :
                             (parity == "Even" ? QSerialPort::EvenParity :
                                  QSerialPort::OddParity));

        // 尝试打开串口
        if (serial.open(QIODevice::ReadWrite)) {
            qDebug() << "Port opened successfully!";
            isPortOpen = true;
            currentMode = ModeSerial;
            emit connectionStatusChanged(true, "串口已连接: " + portName);
        } else {
            qDebug() << "Failed to open port!";
            emit connectionStatusChanged(false, "串口连接失败: " + serial.errorString());
        }
    }

    // 关闭串口
    Q_INVOKABLE void closePort() {
        if (serial.isOpen()) {
            serial.close();
            qDebug() << "Port closed!";
            isPortOpen = false;
            if (currentMode == ModeSerial) {
                currentMode = ModeNone;
                emit connectionStatusChanged(false, "串口已关闭");
            }
        }
    }

    // 连接到TCP服务器
    Q_INVOKABLE void connectToTcpServer(const QString &host, int port) {
        // 关闭可能已经打开的串口
        if (serial.isOpen()) {
            serial.close();
            isPortOpen = false;
        }

        // 关闭TCP服务器
        if (tcpServer.isListening()) {
            stopTcpServer();
        }

        // 关闭UDP连接
        if (currentMode == ModeUdp) {
            stopUdp();
        }

        // 连接到TCP服务器
        tcpSocket.connectToHost(host, port);
        qDebug() << "Connecting to TCP server:" << host << ":" << port;
        emit connectionStatusChanged(false, "正在连接TCP服务器...");
    }


    // 断开TCP连接
    Q_INVOKABLE void disconnectFromTcpServer() {
        if (tcpSocket.state() == QTcpSocket::ConnectedState) {
            tcpSocket.disconnectFromHost();
            qDebug() << "Disconnected from TCP server";
            if (currentMode == ModeTcp) {
                currentMode = ModeNone;
                emit connectionStatusChanged(false, "TCP连接已关闭");
            }
        }
    }

    // 扫描可用串口
    Q_INVOKABLE QStringList scanPorts() {
        QStringList ports;
        const auto serialPortInfos = QSerialPortInfo::availablePorts();
        for (const QSerialPortInfo &serialPortInfo : serialPortInfos) {
            ports << serialPortInfo.portName();
        }
        return ports;
    }

    // 获取TCP连接状态
    Q_INVOKABLE bool isTcpConnected() {
        return tcpSocket.state() == QTcpSocket::ConnectedState;
    }

    //启动 TCP 服务器
    Q_INVOKABLE bool startTcpServer(int port) {
        // 关闭可能已经打开的串口
        if (serial.isOpen()) {
            serial.close();
            isPortOpen = false;
        }

        // 关闭TCP客户端连接
        if (tcpSocket.state() == QTcpSocket::ConnectedState) {
            tcpSocket.disconnectFromHost();
        }

        // 关闭UDP连接
        if (currentMode == ModeUdp) {
            stopUdp();
        }

        if (tcpServer.isListening()) {
            tcpServer.close();
        }

        if (tcpServer.listen(QHostAddress::Any, port)) {
            qDebug() << "TCP Server started on port:" << port;
            currentMode = ModeTcpServer;
            emit connectionStatusChanged(true, "TCP 服务器已启动: " + QString::number(port));
            return true;
        } else {
            qDebug() << "Failed to start TCP Server!";
            emit connectionStatusChanged(false, "TCP 服务器启动失败: " + tcpServer.errorString());
            return false;
        }
    }


    //向所有客户端发送数据
    Q_INVOKABLE void sendTcpServerData(const QString &data, bool isHex) {
        QByteArray byteArray = isHex ? hexStringToByteArray(data) : data.toUtf8();
        for (QTcpSocket *client : clients) {
            if (client->state() == QAbstractSocket::ConnectedState) {
                client->write(byteArray);
            }
        }
        qDebug() << "Sent data to clients:" << data;
    }

    //停止 TCP 服务器
    Q_INVOKABLE void stopTcpServer() {
        for (QTcpSocket *client : clients) {
            client->disconnectFromHost();
        }
        clients.clear();
        tcpServer.close();
        qDebug() << "TCP Server stopped!";
        emit connectionStatusChanged(false, "TCP 服务器已关闭");
    }

    // 发送数据 (支持HEX和ASCII，串口和TCP和UDP)
    Q_INVOKABLE void sendData(const QString &data, bool isHex, const QString &host = "", int port = 0) {
        QByteArray byteArray = isHex ? hexStringToByteArray(data) : data.toUtf8();
        bool sent = false;

        if (currentMode == ModeSerial && serial.isOpen()) {
            serial.write(byteArray);
            sent = true;
        } else if (currentMode == ModeTcp && tcpSocket.state() == QTcpSocket::ConnectedState) {
            tcpSocket.write(byteArray);
            sent = true;
        } else if (currentMode == ModeTcpServer) { // TCP 服务器模式
            sendTcpServerData(data, isHex);
            sent = true;
        } else if (currentMode == ModeUdp) { // UDP 模式
            QString targetHost = host.isEmpty() ? udpRemoteHost : host;
            int targetPort = (port == 0) ? udpRemotePort : port;

            if (targetHost.isEmpty() || targetPort == 0) {
                qDebug() << "Error: UDP target host or port is invalid!";
                return;
            }

            sendUdpData(data, isHex, targetHost, targetPort);
            sent = true;
        }

        if (sent) {
            // qDebug() << "Sent data:" << (isHex ? data : QString::fromUtf8(byteArray.toHex(' ')));
            emit dataSent(data, isHex);
        }
    }


    //绑定 UDP 端口
    Q_INVOKABLE bool startUdp(int localport, const QString &remoteHost, int remoteport) {
        // 关闭可能已经打开的串口
        if (serial.isOpen()) {
            serial.close();
            isPortOpen = false;
        }

        // 关闭TCP客户端连接
        if (tcpSocket.state() == QTcpSocket::ConnectedState) {
            tcpSocket.disconnectFromHost();
        }

        // 关闭TCP服务器
        if (tcpServer.isListening()) {
            stopTcpServer();
        }

        // 关闭已有的UDP连接
        if (udpSocket.state() != QAbstractSocket::UnconnectedState) {
            udpSocket.close();
        }

        if (udpSocket.bind(QHostAddress::Any, localport)) {
            udpRemotePort = remoteport;
            udpRemoteHost = remoteHost; // 记录远程 IP
            qDebug() << "UDP listening on port:" << localport << "Remote:" << remoteHost << ":" << remoteport;
            currentMode = ModeUdp;
            emit connectionStatusChanged(true, "UDP 监听端口: " + QString::number(localport));
            return true;
        } else {
            qDebug() << "Failed to start UDP listener!";
            currentMode = ModeNone;
            emit connectionStatusChanged(false, "UDP 监听失败: " + udpSocket.errorString());
            return false;
        }
    }
    // 停止UDP监听
    Q_INVOKABLE void stopUdp() {
        if (currentMode == ModeUdp) {
            udpSocket.close();
            currentMode = ModeNone;
            qDebug() << "UDP listener stopped!";
            emit connectionStatusChanged(false, "UDP监听已停止");
        }
    }

    Q_INVOKABLE void sendUdpData(const QString &data, bool isHex, const QString &host, int port) {
        QByteArray byteArray = isHex ? hexStringToByteArray(data) : data.toUtf8();
        QHostAddress targetAddress(host);

        if (targetAddress.isNull()) {
            qDebug() << "Invalid UDP target address!";
            return;
        }

        qint64 bytesSent = udpSocket.writeDatagram(byteArray, targetAddress, port);
        if (bytesSent > 0) {
            qDebug() << "Sent UDP data to" << host << ":" << port << "->" << data;
        } else {
            qDebug() << "Failed to send UDP data!";
        }
    }
    // === Lua脚本相关方法 ===

    // 执行Lua脚本
    Q_INVOKABLE QString executeLuaScript(const QString &script) {
        if (!L) {
            return "Lua环境未初始化";
        }

        // 保存当前脚本内容
        currentScript = script;

        // 重置协程状态
        isCoroutineRunning = false;
        waitingForResponse = false;

        // 创建协程
        createLuaCoroutine(script);

        // 启动协程
        return resumeMainCoroutine();
    }

    // 加载Lua脚本文件
    Q_INVOKABLE QString loadLuaScriptFile(const QString &filePath) {
        QFile file(filePath);
        if (!file.open(QIODevice::ReadOnly | QIODevice::Text)) {
            return "无法打开文件: " + filePath;
        }

        QTextStream in(&file);
        QString script = in.readAll();
        file.close();

        // 执行脚本
        return executeLuaScript(script);
    }

    // 保存Lua脚本到文件
    Q_INVOKABLE bool saveLuaScriptToFile(const QString &script, const QString &filePath) {
        QFile file(filePath);
        if (!file.open(QIODevice::WriteOnly | QIODevice::Text)) {
            return false;
        }

        QTextStream out(&file);
        out << script;
        file.close();
        return true;
    }

    // 停止脚本方法
    Q_INVOKABLE void stopLuaScript() {
        stopCoroutine(); // 停止协程
    }


private:
    enum ConnectionMode {
        ModeNone,
        ModeSerial,    // 串口模式
        ModeTcp,        // TCP client模式
        ModeTcpServer, // TCP server模式
        ModeUdp        // UDP 模式
    };

    bool isPortOpen = false;  // 串口是否打开
    ConnectionMode currentMode = ModeNone;  // 当前连接模式
    int udpRemotePort = 0; // 存储udp端口号
    QString udpRemoteHost; // 存储远程IP 地址

    // Lua相关
    lua_State *L = nullptr;    // Lua状态
    lua_State *co = nullptr;   // 当前协程
    QString currentScript;     // 当前脚本内容
    QTimer scriptTimer;        // 脚本定时器
    QTimer coroutineTimer;     // 协程恢复定时器
    QTimer responseTimer;      // 响应超时定时器
    QByteArray lastReceivedData; // 最后接收的数据
    QByteArray expectedPattern; // 期望接收的数据模式

    bool isCoroutineRunning = false; // 协程是否在运行
    bool waitingForResponse = false; // 是否在等待响应
    int responseTimeout = 1000;      // 默认响应超时时间(毫秒)

private slots:
    // 读取串口数据
    void readSerialData() {
        QByteArray rawData = serial.readAll();
        lastReceivedData = rawData;  // 保存最后接收的数据供Lua使用
        hasNewData = true;  // 设置标志位
        processReceivedData(rawData);

        // 如果有等待响应的协程，检查是否收到期望的数据
        if (waitingForResponse && isCoroutineRunning) {
            checkAndResumeCoroutine();
        }
    }

    // 读取TCP数据
    void readTcpData() {
        QByteArray rawData = tcpSocket.readAll();
        lastReceivedData = rawData;  // 保存最后接收的数据供Lua使用
        hasNewData = true;  // 设置标志位
        processReceivedData(rawData);

        // 如果有等待响应的协程，检查是否收到期望的数据
        if (waitingForResponse && isCoroutineRunning) {
            checkAndResumeCoroutine();
        }
    }

    // 处理TCP连接成功
    void onTcpConnected() {
        qDebug() << "Connected to TCP server!";
        currentMode = ModeTcp;
        emit connectionStatusChanged(true, "TCP服务器已连接");
    }

    // 处理TCP断开连接
    void onTcpDisconnected() {
        qDebug() << "Disconnected from TCP server!";
        if (currentMode == ModeTcp) {
            currentMode = ModeNone;
            emit connectionStatusChanged(false, "TCP连接已断开");
        }
    }

    // 处理TCP错误
    void onTcpError(QAbstractSocket::SocketError socketError) {
        qDebug() << "TCP Socket error:" << socketError << tcpSocket.errorString();
        emit connectionStatusChanged(false, "TCP错误: " + tcpSocket.errorString());
    }

    //TCP Server相关
    void onNewClientConnected() {
        QTcpSocket *clientSocket = tcpServer.nextPendingConnection();
        if (clientSocket) {
            clients.append(clientSocket);
            connect(clientSocket, &QTcpSocket::readyRead, this, &SerialHandler::readTcpServerData);
            connect(clientSocket, &QTcpSocket::disconnected, this, &SerialHandler::onClientDisconnected);
            qDebug() << "New client connected!";
            currentMode = ModeTcpServer;
            emit connectionStatusChanged(true, "客户端已连接");
        }
    }
    void onClientDisconnected() {
        QTcpSocket *client = qobject_cast<QTcpSocket *>(sender());
        if (client) {
            clients.removeAll(client);
            client->deleteLater();
            qDebug() << "Client disconnected!";
            currentMode = ModeNone;
            emit connectionStatusChanged(false, "客户端已断开连接");
        }
    }
    void readTcpServerData() {
        QTcpSocket *client = qobject_cast<QTcpSocket *>(sender());
        if (client) {
            QByteArray data = client->readAll();
            hasNewData = true;  // 设置标志位
            qDebug() << "Received from client:" << data;
            processReceivedData(data);
        }
    }
    //UDP
    void readUdpData() {
        while (udpSocket.hasPendingDatagrams()) {
            QByteArray buffer;
            QHostAddress sender;
            quint16 senderPort;

            buffer.resize(udpSocket.pendingDatagramSize());
            udpSocket.readDatagram(buffer.data(), buffer.size(), &sender, &senderPort);
            hasNewData = true;  // 设置标志位
            qDebug() << "Received UDP data from" << sender.toString() << ":" << senderPort << " -> " << buffer;
            processReceivedData(buffer);
        }
    }
    // 执行计划的脚本
    void executeScheduledScript() {
        executeLuaScript(currentScript);
    }

    // 恢复协程执行
    void resumeCoroutine() {
        if (isCoroutineRunning && co) {
            int result = lua_resume(co, NULL, 0, &nres);
            handleCoroutineResult(result);
        }
    }

    // 处理响应超时
    void handleResponseTimeout() {
        if (waitingForResponse && isCoroutineRunning) {
            emit luaOutput("响应超时");
            waitingForResponse = false;

            // 恢复协程，但将超时状态返回给Lua
            lua_pushboolean(co, 0); // 超时返回false
            int result = lua_resume(co, NULL, 1, &nres);
            handleCoroutineResult(result);
        }
    }

signals:
    void currentScriptChanged();
    // 数据相关信号
    void dataReceived(const QString &hexData, const QString &asciiData);
    void dataSent(const QString &data, bool isHex);  // 数据发送信号
    // 连接状态信号
    void connectionStatusChanged(bool connected, const QString &message);
    // 脚本状态信号
    void scriptSchedulerStatusChanged(bool running, const QString &message);
    // Lua脚本输出信号
    void luaOutput(const QString &output);

private:
    // 处理收到的数据（通用）
    void processReceivedData(const QByteArray &rawData) {
        // 将原始数据转换为十六进制字符串格式，方便在QML中处理
        QString hexData;
        for (char byte : rawData) {
            hexData += QString("%1 ").arg(static_cast<quint8>(byte), 2, 16, QLatin1Char('0')).toUpper();
        }

        // 同时传递ASCII格式，用于ASCII显示模式
        QString asciiData = QString::fromUtf8(rawData);

        emit dataReceived(hexData.trimmed(), asciiData);
    }

    // 将十六进制字符串转换为字节数组
    QByteArray hexStringToByteArray(const QString &hexString) {
        QByteArray result;
        QString hexStr = hexString.simplified().remove(' '); // 删除所有空格

        // 确保字符串长度是偶数
        if (hexStr.length() % 2 != 0) {
            hexStr.append('0');
        }

        // 每两个字符转换为一个字节
        for (int i = 0; i < hexStr.length(); i += 2) {
            QString byteStr = hexStr.mid(i, 2);
            bool ok;
            char byte = static_cast<char>(byteStr.toInt(&ok, 16));
            if (ok) {
                result.append(byte);
            }
        }

        return result;
    }

    // 初始化Lua环境
    void initLua() {
        // 创建Lua状态
        L = luaL_newstate();
        if (!L) {
            qDebug() << "Failed to create Lua state";
            return;
        }

        // 打开Lua标准库
        luaL_openlibs(L);

        // 注册自定义函数
        lua_register(L, "send", lua_send);
        lua_register(L, "sendHex", lua_sendHex);
        lua_register(L, "sleep", lua_sleep);
        lua_register(L, "print", lua_print);
        lua_register(L, "getLastData", lua_getLastData);
        lua_register(L, "setResponseTimeout", lua_setResponseTimeout);

        // 设置全局指针，方便在静态函数中访问类实例
        lua_pushlightuserdata(L, this);
        lua_setglobal(L, "__SerialHandler");
    }

    // 创建Lua协程
    void createLuaCoroutine(const QString &script) {
        // 如果已经有一个协程在运行，先停止它
        stopCoroutine();

        // 创建新的协程
        co = lua_newthread(L);
        if (!co) {
            emit luaOutput("无法创建Lua协程");
            return;
        }

        // 加载脚本到协程
        int error = luaL_loadstring(co, script.toUtf8().constData());
        if (error) {
            QString errorMsg = QString("Lua错误: %1").arg(lua_tostring(co, -1));
            emit luaOutput(errorMsg);
            lua_pop(co, 1);  // 弹出错误消息
            co = nullptr;
            return;
        }
    }

    // 恢复主协程执行
    QString resumeMainCoroutine() {
        if (!co) {
            return "协程未初始化";
        }

        isCoroutineRunning = true;

        // 恢复协程执行
        int result = lua_resume(co, NULL, 0, &nres);

        return handleCoroutineResult(result);
    }

    // 处理协程执行结果
    QString handleCoroutineResult(int result) {
        if (result == LUA_OK) {
            // 协程执行完成
            isCoroutineRunning = false;
            waitingForResponse = false;
            responseTimer.stop();
            co = nullptr;
            return "脚本执行完成";
        } else if (result == LUA_YIELD) {
            // 协程被挂起，等待后续恢复
            return "脚本执行挂起";
        } else {
            // 发生错误
            QString errorMsg = QString("Lua错误: %1").arg(lua_tostring(co, -1));
            emit luaOutput(errorMsg);
            lua_pop(co, 1);  // 弹出错误消息

            isCoroutineRunning = false;
            waitingForResponse = false;
            responseTimer.stop();
            co = nullptr;
            return errorMsg;
        }
    }

    // 停止当前协程
    void stopCoroutine() {
        if (isCoroutineRunning) {
            isCoroutineRunning = false;
            waitingForResponse = false;
            responseTimer.stop();
            coroutineTimer.stop();
            co = nullptr;
            emit luaOutput("协程已停止");
        }
    }

    // 检查是否收到期望的数据并恢复协程
    void checkAndResumeCoroutine() {
        if (!isCoroutineRunning || !waitingForResponse || !co) {
            return;
        }

        // 如果expectedPattern为空，任何数据都会触发恢复
        if (expectedPattern.isEmpty()) {
            responseTimer.stop();
            waitingForResponse = false;

            // 恢复协程，传递收到的数据
            QString hexData;
            for (const auto& byte : std::as_const(lastReceivedData)) {
                hexData += QString("%1 ").arg(static_cast<quint8>(byte), 2, 16, QLatin1Char('0')).toUpper();
            }

            lua_pushboolean(co, 1); // 成功返回true
            lua_pushstring(co, hexData.trimmed().toUtf8().constData()); // 返回接收到的数据

            int result = lua_resume(co, NULL, 2, &nres);
            handleCoroutineResult(result);
            return;
        }

        // 检查数据是否与期望模式匹配
        bool matches = true;
        for (int i = 0; i < expectedPattern.size(); i++) {
            if (i >= lastReceivedData.size() || expectedPattern[i] != lastReceivedData[i]) {
                matches = false;
                break;
            }
        }

        if (matches) {
            responseTimer.stop();
            waitingForResponse = false;

            // 恢复协程，传递匹配成功的状态
            lua_pushboolean(co, 1); // 成功返回true

            QString hexData;
            for (const auto& byte : std::as_const(lastReceivedData)) {
                hexData += QString("%1 ").arg(static_cast<quint8>(byte), 2, 16, QLatin1Char('0')).toUpper();
            }
            lua_pushstring(co, hexData.trimmed().toUtf8().constData()); // 返回接收到的数据

            int result = lua_resume(co, NULL, 2, &nres);
            handleCoroutineResult(result);
        }
    }

    // Lua API静态函数 - 获取SerialHandler实例
    static SerialHandler* getSerialHandler(lua_State *L) {
        lua_getglobal(L, "__SerialHandler");
        SerialHandler* handler = static_cast<SerialHandler*>(lua_touserdata(L, -1));
        lua_pop(L, 1);
        return handler;
    }

    // Lua API - 发送ASCII文本
    static int lua_send(lua_State *L) {
        SerialHandler* handler = getSerialHandler(L);
        if (!handler) return 0;

        const char* data = luaL_checkstring(L, 1);
        handler->sendData(QString(data), false); // ASCII模式
        return 0;
    }

    // Lua API - 发送HEX数据
    static int lua_sendHex(lua_State *L) {
        SerialHandler* handler = getSerialHandler(L);
        if (!handler) return 0;

        const char* data = luaL_checkstring(L, 1);
        handler->sendData(QString(data), true); // HEX模式
        return 0;
    }

    // Lua API - 等待指定毫秒
    static int lua_sleep(lua_State *L) {
        SerialHandler* handler = getSerialHandler(L);
        if (!handler) return 0;

        int ms = luaL_checkinteger(L, 1);

        // 在协程模式下，使用QTimer延迟执行而不是阻塞
        if (handler->isCoroutineRunning) {
            handler->coroutineTimer.setSingleShot(true);
            handler->coroutineTimer.start(ms);
            return lua_yield(L, 0); // 挂起协程
        } else {
            // 非协程模式，使用传统的阻塞睡眠
            QThread::msleep(ms);
            return 0;
        }
    }

    // Lua API - 打印输出
    static int lua_print(lua_State *L) {
        SerialHandler* handler = getSerialHandler(L);
        if (!handler) return 0;

        int nargs = lua_gettop(L);
        QString output;
        for (int i = 1; i <= nargs; i++) {
            if (lua_isstring(L, i)) {
                output += QString::fromUtf8(lua_tostring(L, i));
            } else if (lua_isnumber(L, i)) {
                output += QString::number(lua_tonumber(L, i));
            } else if (lua_isboolean(L, i)) {
                output += lua_toboolean(L, i) ? "true" : "false";
            } else {
                output += "nil";
            }
            if (i < nargs) {
                output += " ";
            }
        }
        emit handler->luaOutput(output);
        return 0;
    }

    // Lua API - 获取最后接收的数据（二进制数据）
    static int lua_getLastData(lua_State *L) {
        SerialHandler* handler = getSerialHandler(L);
        if (!handler) {
            lua_pushlstring(L, "", 0);  // 返回空字节串
            return 1;
        }

        // 检查是否有新数据
        if (!handler->hasNewData) {
            lua_pushlstring(L, "", 0);
            return 1;
        }

        // 获取数据
        const char* data = handler->lastReceivedData.constData();
        int size = handler->lastReceivedData.size();

        // 重置标志位
        handler->hasNewData = false;

        // 直接返回二进制数据
        lua_pushlstring(L, data, size);
        return 1;
    }

    // Lua API - 设置响应超时时间
    static int lua_setResponseTimeout(lua_State *L) {
        SerialHandler* handler = getSerialHandler(L);
        if (!handler) return 0;

        int timeout = luaL_checkinteger(L, 1);
        if (timeout > 0) {
            handler->responseTimeout = timeout;
        }

        return 0;
    }

private:
    QSerialPort serial;          // 串口对象
    QTcpSocket tcpSocket;        // TCP Socket
    QTcpServer tcpServer;        // TCP Server
    QList<QTcpSocket*> clients;  // 存储连接的客户端
    QUdpSocket udpSocket;        // UDP Socket
};

int main(int argc, char *argv[]) {
    QGuiApplication app(argc, argv);
    app.setWindowIcon(QIcon(":/MJCom.ico"));
    QQmlApplicationEngine engine;

    // 创建 SerialHandler 实例并设置为 QML 上下文属性
    SerialHandler serialHandler;
    engine.rootContext()->setContextProperty("serial", &serialHandler);

    // 加载 QML 文件
    const QUrl url("qrc:/Main.qml");
    QObject::connect(&engine, &QQmlApplicationEngine::objectCreated,
                     &app, [url](QObject *obj, const QUrl &objUrl) {
                         if (!obj && url == objUrl)
                             QCoreApplication::exit(-1);
                     }, Qt::QueuedConnection);

    engine.load(url);

    return app.exec();
}

#include "main.moc"
