import Foundation

enum GlassesWiFiMode: Int {
    case ap
    case p2p

    var title: String {
        switch self {
        case .ap:
            return "AP"
        case .p2p:
            return "P2P"
        }
    }

    var host: String {
        switch self {
        case .ap:
            return "192.168.1.254"
        case .p2p:
            return "192.168.49.207"
        }
    }
}

enum GlassesLEDBrightness: UInt8 {
    case low = 0x30
    case medium = 0x31
    case high = 0x32

    var title: String {
        switch self {
        case .low:
            return "低"
        case .medium:
            return "中"
        case .high:
            return "高"
        }
    }
}

enum GlassesPresetCommand {
    case setLEDBrightness(GlassesLEDBrightness)
    case setRecordDuration(seconds: UInt16)
    case setWearDetection(enabled: Bool)
    case setVoiceCommand(enabled: Bool)
    case resetFactorySettings
    case syncTime(Date)
    case getBattery
    case takePhoto(highDefinition: Bool)
    case startRecord
    case stopRecord
    case openWiFi(GlassesWiFiMode)
    case getThumbnailCount
    case getDeviceStatus
    case getSwitchStatus
    case getVersion
    case getProjectAndCustomer
    case getLiveSupport
    case getQuickVolumeSupport
    case getCurrentVolume

    var displayName: String {
        switch self {
        case .setLEDBrightness(let level):
            return "设置 LED \(level.title)"
        case .setRecordDuration(let seconds):
            return "设置录像时长 \(seconds)s"
        case .setWearDetection(let enabled):
            return enabled ? "开启佩戴检测" : "关闭佩戴检测"
        case .setVoiceCommand(let enabled):
            return enabled ? "开启语音命令" : "关闭语音命令"
        case .resetFactorySettings:
            return "恢复出厂设置"
        case .syncTime:
            return "同步手机时间"
        case .getBattery:
            return "获取电量"
        case .takePhoto(let highDefinition):
            return highDefinition ? "拍照并回传高清图" : "拍照"
        case .startRecord:
            return "开始录像"
        case .stopRecord:
            return "停止录像"
        case .openWiFi(let mode):
            return "打开 Wi-Fi (\(mode.title))"
        case .getThumbnailCount:
            return "获取缩略图数量"
        case .getDeviceStatus:
            return "获取设备状态"
        case .getSwitchStatus:
            return "获取开关状态"
        case .getVersion:
            return "获取设备版本"
        case .getProjectAndCustomer:
            return "获取项目/客户名"
        case .getLiveSupport:
            return "查询直播支持"
        case .getQuickVolumeSupport:
            return "查询快捷音量支持"
        case .getCurrentVolume:
            return "获取当前音量"
        }
    }

    var commandID: UInt8 {
        switch self {
        case .setLEDBrightness:
            return 0x01
        case .setRecordDuration:
            return 0x02
        case .setWearDetection:
            return 0x04
        case .setVoiceCommand:
            return 0x06
        case .resetFactorySettings:
            return 0x14
        case .syncTime:
            return 0x59
        case .getBattery:
            return 0x17
        case .takePhoto:
            return 0x22
        case .startRecord:
            return 0x23
        case .stopRecord:
            return 0x24
        case .openWiFi:
            return 0x39
        case .getThumbnailCount:
            return 0x40
        case .getDeviceStatus:
            return 0x45
        case .getSwitchStatus:
            return 0x48
        case .getVersion:
            return 0x55
        case .getProjectAndCustomer:
            return 0x64
        case .getLiveSupport:
            return 0x66
        case .getQuickVolumeSupport:
            return 0x68
        case .getCurrentVolume:
            return 0x69
        }
    }

    var payload: Data {
        switch self {
        case .setLEDBrightness(let level):
            return Data([level.rawValue])
        case .setRecordDuration(let seconds):
            return Data([UInt8((seconds >> 8) & 0xFF), UInt8(seconds & 0xFF)])
        case .setWearDetection(let enabled), .setVoiceCommand(let enabled):
            return Data([enabled ? 0x31 : 0x30])
        case .resetFactorySettings:
            return Data([0x00])
        case .syncTime(let date):
            return GlassesPacketCodec.timePayload(for: date)
        case .getBattery:
            return Data([0x00])
        case .takePhoto(let highDefinition):
            return Data([highDefinition ? 0x31 : 0x30])
        case .startRecord, .stopRecord, .getThumbnailCount, .getDeviceStatus,
             .getSwitchStatus, .getLiveSupport, .getQuickVolumeSupport,
             .getCurrentVolume:
            return Data([0x00])
        case .openWiFi(let mode):
            return Data([mode == .ap ? 0x30 : 0x31])
        case .getVersion, .getProjectAndCustomer:
            return Data([0x00])
        }
    }
}

enum GlassesPacketChannel: Equatable {
    case appCommand
    case deviceCommand
    case fileTransfer

    var title: String {
        switch self {
        case .appCommand:
            return "APP->BLE"
        case .deviceCommand:
            return "BLE->APP"
        case .fileTransfer:
            return "FILE"
        }
    }
}

struct GlassesPacket {
    let channel: GlassesPacketChannel
    let rawData: Data
    let commandID: UInt8
    let payload: Data
    let checksum: UInt8

    var hexString: String {
        rawData.hexString
    }

    var summary: String {
        if channel == .fileTransfer {
            switch commandID {
            case 0x97:
                return payload.fileInfoDescription
            case 0x98:
                return payload.fileChunkDescription
            case 0x99:
                return "文件传输结束"
            default:
                return "文件通道 cmd=0x\(String(format: "%02X", commandID)) payload=\(payload.hexString)"
            }
        }

        switch commandID {
        case 0x17:
            return payload.batteryStatusDescription
        case 0x25:
            let wifiName = payload.readableASCII ?? payload.hexString
            return "收到 Wi-Fi 名称: \(wifiName)"
        case 0x42:
            let count = payload.uint16Value
            return "缩略图数量更新: \(count)"
        case 0x45:
            return payload.actionSyncDescription
        case 0x48:
            return payload.switchStatusDescription
        case 0x46:
            return "语音数据: \(payload.count) bytes"
        case 0x49:
            return "设备放弃本次 AI 识别"
        case 0x51:
            return "设备请求取消 AI 播报"
        case 0x52:
            return "高清图传输失败"
        case 0x53:
            let charging = payload.count > 0 && payload[0] == 0x01 ? "充电中" : "未充电"
            let battery = payload.count > 1 ? "\(payload[1])%" : "未知"
            return "电量上报: \(battery), \(charging)"
        case 0x54:
            let description: String
            switch payload.first ?? 0xFF {
            case 0x00:
                description = "ISP 正在拍照"
            case 0x01:
                description = "ISP 正在录像"
            case 0x02:
                description = "ISP 正在录音"
            case 0x03:
                description = "ISP 正在导入模式"
            default:
                description = "ISP 状态未知"
            }
            return description
        case 0x95:
            return "功能位: \(payload.featureDescription)"
        case 0x96:
            return (payload.first ?? 0x00) == 0x01 ? "ISP OTA 成功" : "ISP OTA 失败"
        case 0x97:
            return "开始语音上传"
        case 0x99:
            return "结束语音上传"
        case 0x55:
            return payload.versionDescription
        case 0x64:
            return payload.projectAndCustomerDescription
        case 0x66:
            return (payload.first ?? 0x00) == 0x01 ? "设备支持直播" : "设备不支持直播"
        case 0x68:
            return (payload.first ?? 0x00) == 0x01 ? "设备支持快捷调音量" : "设备不支持快捷调音量"
        case 0x69:
            return payload.volumeDescription
        default:
            return "cmd=0x\(String(format: "%02X", commandID)) payload=\(payload.hexString)"
        }
    }
}

enum GlassesPacketCodec {
    static let appCommandHeader = Data([0xAB, 0x55])
    static let deviceCommandHeader = Data([0xAC, 0x55])
    static let fileTransferHeader = Data([0x52, 0x58])

    // 协议文档存在 OCR 丢失，这里先按“尾部等于头部翻转”实现，便于和设备联调。
    static let appCommandFooter = Data([0x55, 0xAB])
    static let deviceCommandFooter = Data([0x55, 0xAC])
    static let fileTransferFooter = Data([0x58, 0x52])

    static func packet(for preset: GlassesPresetCommand) -> Data {
        packet(commandID: preset.commandID, payload: preset.payload)
    }

    static func packet(commandID: UInt8, payload: Data) -> Data {
        // 厂家补充协议说明：长度为 2 字节，内容为 “指令(1) + 数据(N) + 校验(1)”。
        // 当某命令无数据时，当前仍按文档备注补 0x00，便于设备兼容。
        let normalizedPayload = payload.isEmpty ? Data([0x00]) : payload
        let length = UInt16(1 + normalizedPayload.count + 1)
        let checksum = checksum(commandID: commandID, payload: normalizedPayload)
        var data = Data()
        data.append(appCommandHeader)
        data.append(UInt8((length >> 8) & 0xFF))
        data.append(UInt8(length & 0xFF))
        data.append(commandID)
        data.append(normalizedPayload)
        data.append(checksum)
        return data
    }

    static func checksum(commandID: UInt8, payload: Data) -> UInt8 {
        let total = Int(commandID) + payload.reduce(0) { $0 + Int($1) }
        return UInt8(total & 0xFF)
    }

    static func timePayload(for date: Date) -> Data {
        let calendar = Calendar(identifier: .gregorian)
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        let year = UInt16(max(components.year ?? 2000, 2000))
        let yearHigh = UInt8((year >> 8) & 0xFF)
        let yearLow = UInt8(year & 0xFF)
        return Data([
            yearHigh,
            yearLow,
            UInt8(components.month ?? 1),
            UInt8(components.day ?? 1),
            UInt8(components.hour ?? 0),
            UInt8(components.minute ?? 0),
            UInt8(components.second ?? 0)
        ])
    }

    static func decodePackets(from buffer: inout Data) -> [GlassesPacket] {
        var packets: [GlassesPacket] = []

        while let headerMatch = nextHeader(in: buffer) {
            if headerMatch.index > 0 {
                buffer.removeFirst(headerMatch.index)
            }

            guard let packet = decodeSinglePacket(from: &buffer, channel: headerMatch.channel) else {
                break
            }
            packets.append(packet)
        }

        if buffer.count > 2048 {
            buffer.removeAll(keepingCapacity: true)
        }

        return packets
    }

    private static func nextHeader(in data: Data) -> (index: Int, channel: GlassesPacketChannel)? {
        let bytes = [UInt8](data)
        guard bytes.count >= 2 else { return nil }

        for index in 0..<(bytes.count - 1) {
            let pair = (bytes[index], bytes[index + 1])
            switch pair {
            case (0xAB, 0x55):
                return (index, .appCommand)
            case (0xAC, 0x55):
                return (index, .deviceCommand)
            case (0x52, 0x58):
                return (index, .fileTransfer)
            default:
                continue
            }
        }
        return nil
    }

    private static func decodeSinglePacket(from buffer: inout Data, channel: GlassesPacketChannel) -> GlassesPacket? {
        switch channel {
        case .appCommand, .deviceCommand:
            return decodeCommandPacket(from: &buffer, channel: channel)
        case .fileTransfer:
            return decodeFilePacket(from: &buffer)
        }
    }

    private static func decodeCommandPacket(from buffer: inout Data, channel: GlassesPacketChannel) -> GlassesPacket? {
        guard buffer.count >= 6 else { return nil }
        let bytes = [UInt8](buffer)
        let length = Int(bytes[2]) << 8 | Int(bytes[3])
        let bodyTotalLength = 2 + 2 + length
        guard buffer.count >= bodyTotalLength else { return nil }

        var totalLength = bodyTotalLength
        if buffer.count >= bodyTotalLength + 2 {
            let footerBytes = Array(bytes[bodyTotalLength..<(bodyTotalLength + 2)])
            let expectedFooter = channel == .appCommand ? [UInt8](appCommandFooter) : [UInt8](deviceCommandFooter)
            if footerBytes == expectedFooter {
                totalLength += 2
            }
        }

        let rawData = buffer.prefix(totalLength)
        let commandID = bytes[4]
        let checksum = bytes[bodyTotalLength - 1]
        let payloadRange = 5..<(bodyTotalLength - 1)
        let payload = payloadRange.isEmpty ? Data() : Data(bytes[payloadRange])

        buffer.removeFirst(totalLength)

        return GlassesPacket(
            channel: channel,
            rawData: Data(rawData),
            commandID: commandID,
            payload: payload,
            checksum: checksum
        )
    }

    private static func decodeFilePacket(from buffer: inout Data) -> GlassesPacket? {
        guard buffer.count >= 9 else { return nil }
        let bytes = [UInt8](buffer)
        let length = Int(bytes[2]) << 8 | Int(bytes[3])
        let totalLength = 2 + 2 + length + 2
        guard buffer.count >= totalLength else { return nil }

        let rawData = buffer.prefix(totalLength)
        let commandID = bytes[4]
        let checksum = bytes[totalLength - 3]
        let payloadRange = 5..<(totalLength - 3)
        let payload = payloadRange.isEmpty ? Data() : Data(bytes[payloadRange])

        buffer.removeFirst(totalLength)

        return GlassesPacket(
            channel: .fileTransfer,
            rawData: Data(rawData),
            commandID: commandID,
            payload: payload,
            checksum: checksum
        )
    }
}

extension Data {
    var hexString: String {
        map { String(format: "%02X", $0) }.joined(separator: " ")
    }

    var readableASCII: String? {
        if let string = String(data: self, encoding: .utf8), !string.isEmpty {
            return string
        }
        if let string = String(data: self, encoding: .ascii), !string.isEmpty {
            return string
        }
        return nil
    }

    var uint16Value: Int {
        let bytes = [UInt8](self.prefix(2))
        guard bytes.count == 2 else { return 0 }
        return Int(bytes[0]) << 8 | Int(bytes[1])
    }

    var featureDescription: String {
        let bytes = [UInt8](self)
        guard !bytes.isEmpty else { return "无" }
        var features: [String] = []
        if bytes.indices.contains(0) && (bytes[0] & 0x01) != 0 {
            features.append("支持直播")
        }
        if bytes.indices.contains(0) && (bytes[0] & 0x02) != 0 {
            features.append("支持快捷调音量")
        }
        return features.isEmpty ? "无已知功能位" : features.joined(separator: "、")
    }

    var batteryStatusDescription: String {
        let bytes = [UInt8](self)
        guard bytes.count >= 3 else { return "电量回复: \(hexString)" }

        let batteryValue: String
        if let ascii = String(bytes: bytes[0...1], encoding: .ascii), Int(ascii) != nil {
            batteryValue = "\(ascii)%"
        } else {
            batteryValue = "\(bytes[0]) \(bytes[1])"
        }
        let charging = bytes[2] == 0x01 ? "充电中" : "未充电"
        return "设备电量: \(batteryValue), \(charging)"
    }

    var actionSyncDescription: String {
        let labels = ["拍照", "录音", "录像", "音量大", "音量小", "点头", "摇头", "音乐播放", "佩戴"]
        let bytes = [UInt8](self)
        guard !bytes.isEmpty else { return "设备状态同步: 无数据" }

        var active: [String] = []
        for (index, label) in labels.enumerated() where bytes.indices.contains(index) {
            if bytes[index] == 0x01 {
                active.append(label)
            }
        }

        return active.isEmpty ? "设备状态同步: 无动作" : "设备状态同步: " + active.joined(separator: "、")
    }

    var switchStatusDescription: String {
        let bytes = [UInt8](self)
        guard bytes.count >= 8 else { return "开关状态: \(hexString)" }

        let led: String
        switch bytes[0] {
        case 0x30:
            led = "低"
        case 0x31:
            led = "中"
        case 0x32:
            led = "高"
        default:
            led = "未知(\(String(format: "%02X", bytes[0])))"
        }

        let duration = Int(bytes[1]) << 8 | Int(bytes[2])
        let wear = bytes[3] == 0x31 ? "开" : "关"
        let voice = bytes[4] == 0x31 ? "开" : "关"
        let gesture = String(format: "0x%02X", bytes[5])
        let orientation = bytes[6] == 0x31 ? "横拍" : "竖拍"
        let language = bytes[7] == 0x01 ? "英文" : "中文"

        return "开关状态: LED=\(led), 录像时长=\(duration)s, 佩戴检测=\(wear), 语音命令=\(voice), 手势=\(gesture), 方向=\(orientation), 语音=\(language)"
    }

    var versionDescription: String {
        let bytes = [UInt8](self)
        guard bytes.count >= 7 else { return "版本信息: \(hexString)" }
        return "版本信息: bt_v\(bytes[0]).\(bytes[1]).\(bytes[2]), isp_v\(bytes[3]).\(bytes[4]).\(bytes[5]), hw_v\(bytes[6])"
    }

    var projectAndCustomerDescription: String {
        let bytes = [UInt8](self)
        guard bytes.count >= 8 else { return "项目/客户名: \(hexString)" }

        let projectData = Data(bytes[0..<4])
        let customerData = Data(bytes[4..<8])
        let project = projectData.readableASCII ?? projectData.hexString
        let customer = customerData.readableASCII ?? customerData.hexString
        return "项目名: \(project), 客户名: \(customer)"
    }

    var volumeDescription: String {
        let bytes = [UInt8](self)
        guard bytes.count >= 3 else { return "当前音量: \(hexString)" }
        return "当前音量: 系统=\(bytes[0]), 媒体=\(bytes[1]), 通话=\(bytes[2])"
    }

    var fileInfoDescription: String {
        let bytes = [UInt8](self)
        guard bytes.count >= 5 else { return "文件信息: \(hexString)" }

        let totalLength = Int(bytes[0]) << 24 | Int(bytes[1]) << 16 | Int(bytes[2]) << 8 | Int(bytes[3])
        let type: String
        switch bytes[4] {
        case 0x01:
            type = "图片缩略图"
        case 0x02:
            type = "高清图"
        case 0x03:
            type = "视频缩略图"
        default:
            type = "未知(\(String(format: "%02X", bytes[4])))"
        }
        return "文件信息: 类型=\(type), 总长度=\(totalLength) bytes"
    }

    var fileChunkDescription: String {
        let bytes = [UInt8](self)
        guard bytes.count >= 4 else { return "文件数据: \(hexString)" }
        let address = Int(bytes[0]) << 24 | Int(bytes[1]) << 16 | Int(bytes[2]) << 8 | Int(bytes[3])
        let chunkLength = bytes.count - 4
        return "文件数据: 偏移=\(address), 数据长度=\(chunkLength) bytes"
    }

    init?(hexString: String) {
        let cleaned = hexString
            .replacingOccurrences(of: "0x", with: "", options: .caseInsensitive)
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "\n", with: "")
            .replacingOccurrences(of: "\t", with: "")

        guard cleaned.count.isMultiple(of: 2), !cleaned.isEmpty else {
            return nil
        }

        var bytes: [UInt8] = []
        bytes.reserveCapacity(cleaned.count / 2)

        var index = cleaned.startIndex
        while index < cleaned.endIndex {
            let nextIndex = cleaned.index(index, offsetBy: 2)
            let pair = cleaned[index..<nextIndex]
            guard let byte = UInt8(pair, radix: 16) else {
                return nil
            }
            bytes.append(byte)
            index = nextIndex
        }

        self.init(bytes)
    }
}
