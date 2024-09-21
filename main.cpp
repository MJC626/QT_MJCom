#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QSerialPort>
#include <QSerialPortInfo>
#include <QTimer>
#include <QDebug>

// SerialHandler 类用于处理串口操作
class SerialHandler : public QObject {
    Q_OBJECT

public:
    explicit SerialHandler(QObject *parent = nullptr) : QObject(parent) {
        // 连接信号和槽
        connect(&serial, &QSerialPort::readyRead, this, &SerialHandler::readData);
        connect(&autoSendTimer, &QTimer::timeout, this, &SerialHandler::autoSendData);
    }

    // 打开串口
    Q_INVOKABLE void openPort(const QString &portName, const QString &baudRate,
                              const QString &dataBits, const QString &stopBits,
                              const QString &parity) {
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
        } else {
            qDebug() << "Failed to open port!";
        }
    }

    // 关闭串口
    Q_INVOKABLE void closePort() {
        if (serial.isOpen()) {
            serial.close();
            qDebug() << "Port closed!";
            isPortOpen = false;
            stopAutoSend(); // 关闭自动发送
        }
    }

    // 发送数据
    Q_INVOKABLE void sendData(const QString &hexData) {
        if (serial.isOpen()) {
            QByteArray byteArray = hexStringToByteArray(hexData);
            serial.write(byteArray);
            qDebug() << "Sent data:" << hexData;
            emit dataSent(hexData);
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

    // 开始自动发送数据
    Q_INVOKABLE void startAutoSend(const QString &hexData, int interval) {
        this->autoSendDataStr = hexData;
        autoSendTimer.start(interval);
    }

    // 停止自动发送数据
    Q_INVOKABLE void stopAutoSend() {
        autoSendTimer.stop();
    }

private:
    bool isPortOpen = false;  // 串口是否打开
    QTimer autoSendTimer;     // 定时器用于自动发送
    QString autoSendDataStr;  // 自动发送的数据

private slots:
    // 读取串口数据
    void readData() {
        QByteArray data = serial.readAll();
        QString hexData;
        for (char byte : data) {
            hexData += QString::asprintf("%02X ", static_cast<unsigned char>(byte));
        }
        qDebug() << "Received data:" << hexData.trimmed();
        emit dataReceived(hexData.trimmed());
    }

    // 自动发送数据
    void autoSendData() {
        sendData(autoSendDataStr);
    }

signals:
    void dataReceived(const QString &data);  // 数据接收信号
    void dataSent(const QString &data);      // 数据发送信号

private:
    // 将十六进制字符串转换为字节数组
    QByteArray hexStringToByteArray(const QString &hexString) {
        QByteArray byteArray;
        QStringList hexList = hexString.split(' ');
        for (const QString &hex : hexList) {
            bool ok;
            char byte = hex.toInt(&ok, 16);
            if (ok) {
                byteArray.append(byte);
            }
        }
        return byteArray;
    }

private:
    QSerialPort serial;  // 串口对象
};

int main(int argc, char *argv[]) {
    QGuiApplication app(argc, argv);

    QQmlApplicationEngine engine;

    // 创建 SerialHandler 实例并设置为 QML 上下文属性
    SerialHandler serialHandler;
    engine.rootContext()->setContextProperty("serial", &serialHandler);

    // 加载 QML 文件
    const QUrl url(QStringLiteral("../../Main.qml"));
    QObject::connect(&engine, &QQmlApplicationEngine::objectCreated,
                     &app, [url](QObject *obj, const QUrl &objUrl) {
                         if (!obj && url == objUrl)
                             QCoreApplication::exit(-1);
                     }, Qt::QueuedConnection);

    engine.load(url);

    return app.exec();
}

#include "main.moc"
