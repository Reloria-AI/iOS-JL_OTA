//
//  BleManager.swift
//  MiniSingleDemo
//
//  Created by EzioChan on 2025/11/24.
//

import Foundation
import CoreBluetooth
import RxSwift
import RxCocoa
import JLLogHelper
import JL_AdvParse
import JL_BLEKit

class BleManager: NSObject {

    static let shared = BleManager()

    let PRIMARY_SERVICE_UUID = "AA12"
    let FALLBACK_SERVICE_UUID = "AE00"
    let PRIMARY_CHARACTERISTIC_WRITE = "AA13"
    let FALLBACK_CHARACTERISTIC_WRITE = "AE01"
    let PRIMARY_CHARACTERISTIC_NOTIFY = "AA14"
    let FALLBACK_CHARACTERISTIC_NOTIFY = "AE02"
    let CHARACTERISTIC_IMAGE_DATA = "AA15"
    private let lastKnownPeripheralIdentifierKey = "GlassesLastPeripheralIdentifier"
    private lazy var targetServiceUUIDs: [CBUUID] = [
        CBUUID(string: PRIMARY_SERVICE_UUID),
        CBUUID(string: FALLBACK_SERVICE_UUID)
    ]
    private lazy var targetServiceUUIDStrings: Set<String> = Set(targetServiceUUIDs.map { $0.uuidString.uppercased() })
    private let writeCharacteristicUUIDs: Set<String> = ["AA13", "AE01"]
    private let notifyCharacteristicUUIDs: Set<String> = ["AA14", "AE02"]

    lazy var centralManager: CBCentralManager = {
        CBCentralManager(delegate: self, queue: nil)
    }()

    var discoverPeripherals: [CBPeripheral] = []
    var currentUUID: String = ""

    let discoverPeripheralsSubject = BehaviorRelay<[CBPeripheral]>(value: [])
    let subNotifyInitSubject = PublishSubject<CBPeripheral>()
    let subNotifySubject = PublishSubject<Data>()
    let disconnectSubject = PublishSubject<CBPeripheral>()
    let connectionStateSubject = BehaviorRelay<String>(value: "蓝牙初始化中")
    let latestPacketHexSubject = BehaviorRelay<String>(value: "暂无数据")
    let logLinesSubject = BehaviorRelay<[String]>(value: ["等待扫描设备"])

    // 保留 OTA 兼容对象，避免工程里其他示例代码编译报错。
    let assistManager = JL_Assist()

    private var reconnectUUID: String?
    private var reconnectMac: String?
    private var timer: Timer?
    private var timerCount = 0
    private var maxCount = 10
    private var scanStopWorkItem: DispatchWorkItem?
    private var packetBuffer = Data()

    private(set) var currentPeripheral: CBPeripheral?
    private var writeCharacteristic: CBCharacteristic?
    private var notifyCharacteristic: CBCharacteristic?
    private var imageDataCharacteristic: CBCharacteristic?

    private override init() {
        super.init()
        assistManager.mNeedPaired = false
        assistManager.mService = PRIMARY_SERVICE_UUID
        assistManager.mRcsp_W = PRIMARY_CHARACTERISTIC_WRITE
        assistManager.mRcsp_R = PRIMARY_CHARACTERISTIC_NOTIFY
        JLLogManager.logLevel(.DEBUG, content: "BleManager init")
    }

    func startScan() {
        guard centralManager.state == .poweredOn else {
            appendLog("蓝牙未开启，当前状态: \(bluetoothStateDescription(centralManager.state))")
            return
        }

        discoverPeripherals.removeAll()
        discoverPeripheralsSubject.accept([])
        appendLog("开始扫描，仅查找服务 \(PRIMARY_SERVICE_UUID)/\(FALLBACK_SERVICE_UUID) 的眼镜设备")
        connectionStateSubject.accept("扫描中...")

        preloadKnownPeripherals()
        centralManager.scanForPeripherals(withServices: targetServiceUUIDs, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        scanStopWorkItem?.cancel()

        let workItem = DispatchWorkItem { [weak self] in
            self?.stopScan()
        }
        scanStopWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 4, execute: workItem)
    }

    func stopScan() {
        centralManager.stopScan()
        appendLog("停止扫描")
    }

    func connect(peripheral: CBPeripheral) {
        appendLog("连接设备 \(peripheral.name ?? peripheral.identifier.uuidString)")
        connectionStateSubject.accept("连接中: \(peripheral.name ?? peripheral.identifier.uuidString)")
        centralManager.connect(peripheral, options: nil)
    }

    func disconnect(peripheral: CBPeripheral) {
        appendLog("主动断开 \(peripheral.name ?? peripheral.identifier.uuidString)")
        centralManager.cancelPeripheralConnection(peripheral)
    }

    func send(preset: GlassesPresetCommand) {
        let packet = GlassesPacketCodec.packet(for: preset)
        send(rawData: packet, description: preset.displayName)
    }

    func send(rawHex: String) {
        guard let data = Data(hexString: rawHex) else {
            appendLog("原始 Hex 非法: \(rawHex)")
            return
        }
        send(rawData: data, description: "手动原始发包")
    }

    func clearLogs() {
        logLinesSubject.accept(["日志已清空"])
    }

    func appendExternalLog(_ message: String) {
        appendLog(message)
    }

    func reConnectWithUUID(uuid: String) {
        reconnectUUID = uuid
        reconnectMac = nil
        appendLog("准备按 UUID 重连: \(uuid)")
        startScan()
        startTimeout()
    }

    func reConnectWithMac(mac: String) {
        reconnectUUID = nil
        reconnectMac = mac
        appendLog("准备按 MAC 重连: \(mac)")
        startScan()
        startTimeout()
    }

    private func send(rawData: Data, description: String) {
        guard let peripheral = currentPeripheral, let writeCharacteristic else {
            appendLog("发送失败，设备未就绪")
            return
        }

        let writeType: CBCharacteristicWriteType = writeCharacteristic.properties.contains(.writeWithoutResponse) ? .withoutResponse : .withResponse
        peripheral.writeValue(rawData, for: writeCharacteristic, type: writeType)
        latestPacketHexSubject.accept(rawData.hexString)
        appendLog("发送[\(description)] \(rawData.hexString)")
    }

    private func appendLog(_ message: String) {
        JLLogManager.logLevel(.DEBUG, content: message)
        var lines = logLinesSubject.value
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        lines.append("[\(formatter.string(from: Date()))] \(message)")
        if lines.count > 200 {
            lines.removeFirst(lines.count - 200)
        }
        logLinesSubject.accept(lines)
    }

    private func preloadKnownPeripherals() {
        let connected = centralManager.retrieveConnectedPeripherals(withServices: targetServiceUUIDs)
        if !connected.isEmpty {
            appendLog("发现系统已连接候选设备 \(connected.count) 个")
            connected.forEach { addOrUpdateDiscoveredPeripheral($0) }
        }

        if let uuidString = UserDefaults.standard.string(forKey: lastKnownPeripheralIdentifierKey),
           let uuid = UUID(uuidString: uuidString) {
            let remembered = centralManager.retrievePeripherals(withIdentifiers: [uuid])
            if !remembered.isEmpty {
                appendLog("找回上次连接过的眼镜 \(remembered.count) 个")
                remembered.forEach { addOrUpdateDiscoveredPeripheral($0) }
            }
        }
    }

    private func addOrUpdateDiscoveredPeripheral(_ peripheral: CBPeripheral) {
        discoverPeripherals.removeAll(where: { $0.identifier == peripheral.identifier })
        discoverPeripherals.append(peripheral)

        if let rememberedUUID = UserDefaults.standard.string(forKey: lastKnownPeripheralIdentifierKey) {
            discoverPeripherals.sort { lhs, rhs in
                let lhsRemembered = lhs.identifier.uuidString == rememberedUUID
                let rhsRemembered = rhs.identifier.uuidString == rememberedUUID
                if lhsRemembered != rhsRemembered {
                    return lhsRemembered
                }
                return (lhs.name ?? "") < (rhs.name ?? "")
            }
        } else {
            discoverPeripherals.sort { ($0.name ?? "") < ($1.name ?? "") }
        }

        discoverPeripheralsSubject.accept(discoverPeripherals)
    }

    private func resetConnectionContext() {
        packetBuffer.removeAll(keepingCapacity: true)
        currentPeripheral = nil
        writeCharacteristic = nil
        notifyCharacteristic = nil
        imageDataCharacteristic = nil
        currentUUID = ""
    }

    private func autoSyncTimeIfPossible() {
        appendLog("通知通道已就绪，自动发送手机时间")
        send(preset: .syncTime(Date()))
    }

    private func bluetoothStateDescription(_ state: CBManagerState) -> String {
        switch state {
        case .unknown:
            return "unknown"
        case .resetting:
            return "resetting"
        case .unsupported:
            return "unsupported"
        case .unauthorized:
            return "unauthorized"
        case .poweredOff:
            return "poweredOff"
        case .poweredOn:
            return "poweredOn"
        @unknown default:
            return "unknown-default"
        }
    }

    // MARK: timeout handler
    @objc private func timeoutHandler() {
        timerCount += 1
        if timerCount >= maxCount {
            timer?.invalidate()
            timer = nil
            timerCount = 0
            appendLog("连接超时")
            connectionStateSubject.accept("连接超时")
        }
    }

    private func startTimeout() {
        maxCount = 10
        timerCount = 0
        timer?.invalidate()
        timer = Timer.scheduledTimer(timeInterval: 1, target: self, selector: #selector(timeoutHandler), userInfo: nil, repeats: true)
        timer?.fire()
    }

    private func stopTimeout() {
        timer?.invalidate()
        timer = nil
        timerCount = 0
    }
}

extension BleManager: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        let description = bluetoothStateDescription(central.state)
        connectionStateSubject.accept("蓝牙状态: \(description)")
        appendLog("蓝牙状态更新: \(description)")
        assistManager.assistUpdate(central.state)
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        let displayName = peripheral.name ?? advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? "Unnamed"
        appendLog("发现设备: \(displayName) RSSI=\(RSSI)")

        addOrUpdateDiscoveredPeripheral(peripheral)

        if let reconnectUUID, peripheral.identifier.uuidString == reconnectUUID {
            self.reconnectUUID = nil
            stopScan()
            connect(peripheral: peripheral)
            return
        }

        if let reconnectMac,
           let advData = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data,
           JLAdvParse.otaBleMacAddress(reconnectMac, isEqualToCBAdvDataManufacturerData: advData) {
            self.reconnectMac = nil
            stopScan()
            connect(peripheral: peripheral)
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        appendLog("连接设备成功: \(peripheral.name ?? peripheral.identifier.uuidString)")
        connectionStateSubject.accept("已连接: \(peripheral.name ?? peripheral.identifier.uuidString)")
        currentUUID = peripheral.identifier.uuidString
        UserDefaults.standard.set(peripheral.identifier.uuidString, forKey: lastKnownPeripheralIdentifierKey)
        currentPeripheral = peripheral
        peripheral.delegate = self
        peripheral.discoverServices(nil)
        stopScan()
        stopTimeout()
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        appendLog("连接设备失败: \(error?.localizedDescription ?? "unknown error")")
        connectionStateSubject.accept("连接失败")
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        appendLog("断开设备连接: \(peripheral.name ?? peripheral.identifier.uuidString)")
        if let error {
            appendLog("断开原因: \(error.localizedDescription)")
        }
        resetConnectionContext()
        assistManager.assistDisconnectPeripheral(peripheral)
        connectionStateSubject.accept("已断开")
        disconnectSubject.onNext(peripheral)
    }
}

extension BleManager: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error {
            appendLog("发现服务失败: \(error.localizedDescription)")
            return
        }
        guard let services = peripheral.services else { return }

        for service in services {
            appendLog("发现服务: \(service.uuid.uuidString)")
            if targetServiceUUIDStrings.contains(service.uuid.uuidString.uppercased()) {
                appendLog("命中眼镜控制服务: \(service.uuid.uuidString)")
            }
            peripheral.discoverCharacteristics(nil, for: service)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let error {
            appendLog("发现特征失败: \(error.localizedDescription)")
            return
        }
        guard let characteristics = service.characteristics else { return }

        for characteristic in characteristics {
            let uuid = characteristic.uuid.uuidString.uppercased()
            appendLog("特征 \(uuid), properties=\(characteristic.properties.rawValue)")

            if writeCharacteristicUUIDs.contains(uuid) {
                writeCharacteristic = characteristic
            }
            if notifyCharacteristicUUIDs.contains(uuid) {
                notifyCharacteristic = characteristic
                peripheral.setNotifyValue(true, for: characteristic)
            }
            if uuid == CHARACTERISTIC_IMAGE_DATA {
                imageDataCharacteristic = characteristic
                if characteristic.properties.contains(.notify) || characteristic.properties.contains(.indicate) {
                    peripheral.setNotifyValue(true, for: characteristic)
                } else if characteristic.properties.contains(.read) {
                    appendLog("AA15 为读特征，当前等待业务命令触发读取")
                }
            }
        }

        if writeCharacteristic == nil {
            writeCharacteristic = characteristics.first(where: { $0.properties.contains(.write) || $0.properties.contains(.writeWithoutResponse) })
        }
        if notifyCharacteristic == nil {
            notifyCharacteristic = characteristics.first(where: { $0.properties.contains(.notify) || $0.properties.contains(.indicate) })
            if let notifyCharacteristic {
                peripheral.setNotifyValue(true, for: notifyCharacteristic)
            }
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error {
            appendLog("接收数据失败: \(error.localizedDescription)")
            return
        }
        guard let data = characteristic.value else { return }
        packetBuffer.append(data)
        subNotifySubject.onNext(data)
        appendLog("收到原始数据[\(characteristic.uuid.uuidString.uppercased())] \(data.hexString)")

        let packets = GlassesPacketCodec.decodePackets(from: &packetBuffer)
        if packets.isEmpty {
            latestPacketHexSubject.accept(data.hexString)
            return
        }

        for packet in packets {
            latestPacketHexSubject.accept(packet.hexString)
            appendLog("解析[\(packet.channel.title)] \(packet.summary)")
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        if let error {
            appendLog("订阅通知失败: \(error.localizedDescription)")
            return
        }

        guard characteristic.isNotifying else { return }
        appendLog("通知已开启: \(characteristic.uuid.uuidString)")
        connectionStateSubject.accept("通道就绪: \(peripheral.name ?? peripheral.identifier.uuidString)")
        subNotifyInitSubject.onNext(peripheral)
        autoSyncTimeIfPossible()
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error {
            appendLog("写入失败: \(error.localizedDescription)")
        } else {
            appendLog("写入成功: \(characteristic.uuid.uuidString)")
        }
    }

    func peripheralIsReady(toSendWriteWithoutResponse peripheral: CBPeripheral) {
        appendLog("外设已可继续写入")
        assistManager.assistDidReady()
    }
}
