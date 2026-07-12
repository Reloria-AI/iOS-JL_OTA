//
//  ViewController.swift
//  JLAssistOTADemo
//
//  Created by EzioChan on 2025/11/26.
//
import UIKit
import RxSwift
import RxCocoa
import SnapKit
import CoreBluetooth

/// 基于眼镜协议的最小调试页面：扫描、连接、发 BLE 指令、查看日志，以及测试 Wi-Fi 文件列表。
class ViewController: UIViewController {

    private let subTableView = UITableView(frame: .zero, style: .plain)
    private let scrollView = UIScrollView()
    private let contentView = UIView()
    private let contentStack = UIStackView()
    private let stateLabel = UILabel()
    private let latestPacketLabel = UILabel()
    private let modeControl = UISegmentedControl(items: ["AP", "P2P"])
    private let rawHexField = UITextField()
    private let logTextView = UITextView()

    private lazy var scanBtn = makeButton("扫描")
    private lazy var disconnectBtn = makeButton("断开")
    private lazy var clearLogBtn = makeButton("清空日志")
    private lazy var syncTimeBtn = makeButton("同步时间")
    private lazy var getBatteryBtn = makeButton("取电量")
    private lazy var getVersionBtn = makeButton("取版本")
    private lazy var takePhotoBtn = makeButton("拍照")
    private lazy var hdPhotoBtn = makeButton("高清拍照")
    private lazy var startRecordBtn = makeButton("开始录像")
    private lazy var stopRecordBtn = makeButton("停止录像")
    private lazy var openApBtn = makeButton("开 AP")
    private lazy var openP2PBtn = makeButton("开 P2P")
    private lazy var getFileCountBtn = makeButton("缩略图数")
    private lazy var getDeviceStatusBtn = makeButton("设备状态")
    private lazy var getSwitchStatusBtn = makeButton("开关状态")
    private lazy var getFeaturesBtn = makeButton("直播支持")
    private lazy var getVolumeBtn = makeButton("当前音量")
    private lazy var getProjectBtn = makeButton("项目名")
    private lazy var fetchFilesBtn = makeButton("拉文件列表")
    private lazy var sendRawBtn = makeButton("发原始 Hex")

    private let disposeBag = DisposeBag()

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "AI Glasses Demo"
        setupUI()
        setupLayout()
        setupBind()
        bindAction()
    }

    private func setupUI() {
        view.backgroundColor = .systemBackground

        stateLabel.font = .preferredFont(forTextStyle: .headline)
        stateLabel.numberOfLines = 0
        stateLabel.text = "蓝牙初始化中"

        latestPacketLabel.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        latestPacketLabel.textColor = .secondaryLabel
        latestPacketLabel.numberOfLines = 0
        latestPacketLabel.text = "最近一包: 暂无数据"

        modeControl.selectedSegmentIndex = 1

        rawHexField.borderStyle = .roundedRect
        rawHexField.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        rawHexField.placeholder = "输入 Hex，如 AB 55 03 17 00 17 55 AB"
        rawHexField.autocorrectionType = .no
        rawHexField.autocapitalizationType = .allCharacters

        logTextView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        logTextView.isEditable = false
        logTextView.layer.cornerRadius = 10
        logTextView.layer.borderColor = UIColor.systemGray4.cgColor
        logTextView.layer.borderWidth = 1
        logTextView.text = "等待日志..."

        contentStack.axis = .vertical
        contentStack.spacing = 12

        subTableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        subTableView.tableFooterView = UIView()
        subTableView.rowHeight = 48
        subTableView.layer.cornerRadius = 10
        subTableView.layer.borderColor = UIColor.systemGray4.cgColor
        subTableView.layer.borderWidth = 1

        view.addSubview(scrollView)
        scrollView.addSubview(contentView)
        contentView.addSubview(contentStack)

        contentStack.addArrangedSubview(stateLabel)
        contentStack.addArrangedSubview(latestPacketLabel)
        contentStack.addArrangedSubview(makeRow([scanBtn, disconnectBtn, clearLogBtn]))
        contentStack.addArrangedSubview(makeSectionTitle("扫描结果"))
        contentStack.addArrangedSubview(subTableView)
        contentStack.addArrangedSubview(makeRow([syncTimeBtn, getBatteryBtn, getVersionBtn]))
        contentStack.addArrangedSubview(makeRow([takePhotoBtn, hdPhotoBtn, startRecordBtn]))
        contentStack.addArrangedSubview(makeRow([stopRecordBtn, getDeviceStatusBtn, getSwitchStatusBtn]))
        contentStack.addArrangedSubview(makeRow([openApBtn, openP2PBtn, getFileCountBtn]))
        contentStack.addArrangedSubview(makeRow([getFeaturesBtn, getVolumeBtn, getProjectBtn]))
        contentStack.addArrangedSubview(makeWiFiRow())
        contentStack.addArrangedSubview(makeSectionTitle("手动发包"))
        contentStack.addArrangedSubview(makeRawSendRow())
        contentStack.addArrangedSubview(makeSectionTitle("日志"))
        contentStack.addArrangedSubview(logTextView)
    }

    private func setupLayout() {
        scrollView.snp.makeConstraints { make in
            make.edges.equalTo(view.safeAreaLayoutGuide)
        }

        contentView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
            make.width.equalTo(scrollView.snp.width)
        }

        contentStack.snp.makeConstraints { make in
            make.edges.equalToSuperview().inset(16)
        }

        subTableView.snp.makeConstraints { make in
            make.height.equalTo(180)
        }

        logTextView.snp.makeConstraints { make in
            make.height.equalTo(260)
        }
    }

    private func setupBind() {
        BleManager.shared.discoverPeripheralsSubject
            .bind(to: subTableView.rx.items(cellIdentifier: "cell")) { _, peripheral, cell in
                cell.textLabel?.numberOfLines = 2
                cell.textLabel?.font = .systemFont(ofSize: 13)
                cell.textLabel?.text = "\(peripheral.name ?? "Unnamed")\n\(peripheral.identifier.uuidString)"
                if peripheral.identifier == BleManager.shared.currentPeripheral?.identifier {
                    cell.accessoryType = .checkmark
                } else {
                    cell.accessoryType = .none
                }
            }
            .disposed(by: disposeBag)

        BleManager.shared.connectionStateSubject
            .asDriver()
            .drive(onNext: { [weak self] text in
                self?.stateLabel.text = text
            })
            .disposed(by: disposeBag)

        BleManager.shared.latestPacketHexSubject
            .asDriver()
            .drive(onNext: { [weak self] hex in
                self?.latestPacketLabel.text = "最近一包: \(hex)"
                if self?.rawHexField.text?.isEmpty ?? true {
                    self?.rawHexField.text = hex
                }
            })
            .disposed(by: disposeBag)

        BleManager.shared.logLinesSubject
            .asDriver()
            .drive(onNext: { [weak self] lines in
                guard let self else { return }
                self.logTextView.text = lines.joined(separator: "\n")
                let range = NSRange(location: max(self.logTextView.text.count - 1, 0), length: 0)
                self.logTextView.scrollRangeToVisible(range)
            })
            .disposed(by: disposeBag)
    }

    private func bindAction() {
        scanBtn.rx.tap
            .subscribe(onNext: {
                BleManager.shared.startScan()
            })
            .disposed(by: disposeBag)

        disconnectBtn.rx.tap
            .subscribe(onNext: {
                guard let peripheral = BleManager.shared.currentPeripheral else {
                    BleManager.shared.appendExternalLog("当前没有已连接设备")
                    return
                }
                BleManager.shared.disconnect(peripheral: peripheral)
            })
            .disposed(by: disposeBag)

        clearLogBtn.rx.tap
            .subscribe(onNext: {
                BleManager.shared.clearLogs()
            })
            .disposed(by: disposeBag)

        syncTimeBtn.rx.tap
            .subscribe(onNext: {
                BleManager.shared.send(preset: .syncTime(Date()))
            })
            .disposed(by: disposeBag)

        getBatteryBtn.rx.tap
            .subscribe(onNext: {
                BleManager.shared.send(preset: .getBattery)
            })
            .disposed(by: disposeBag)

        getVersionBtn.rx.tap
            .subscribe(onNext: {
                BleManager.shared.send(preset: .getVersion)
            })
            .disposed(by: disposeBag)

        takePhotoBtn.rx.tap
            .subscribe(onNext: {
                BleManager.shared.send(preset: .takePhoto(highDefinition: false))
            })
            .disposed(by: disposeBag)

        hdPhotoBtn.rx.tap
            .subscribe(onNext: {
                BleManager.shared.send(preset: .takePhoto(highDefinition: true))
            })
            .disposed(by: disposeBag)

        startRecordBtn.rx.tap
            .subscribe(onNext: {
                BleManager.shared.send(preset: .startRecord)
            })
            .disposed(by: disposeBag)

        stopRecordBtn.rx.tap
            .subscribe(onNext: {
                BleManager.shared.send(preset: .stopRecord)
            })
            .disposed(by: disposeBag)

        openApBtn.rx.tap
            .subscribe(onNext: {
                BleManager.shared.send(preset: .openWiFi(.ap))
            })
            .disposed(by: disposeBag)

        openP2PBtn.rx.tap
            .subscribe(onNext: {
                BleManager.shared.send(preset: .openWiFi(.p2p))
            })
            .disposed(by: disposeBag)

        getFileCountBtn.rx.tap
            .subscribe(onNext: {
                BleManager.shared.send(preset: .getThumbnailCount)
            })
            .disposed(by: disposeBag)

        getDeviceStatusBtn.rx.tap
            .subscribe(onNext: {
                BleManager.shared.send(preset: .getDeviceStatus)
            })
            .disposed(by: disposeBag)

        getSwitchStatusBtn.rx.tap
            .subscribe(onNext: {
                BleManager.shared.send(preset: .getSwitchStatus)
            })
            .disposed(by: disposeBag)

        getFeaturesBtn.rx.tap
            .subscribe(onNext: {
                BleManager.shared.send(preset: .getLiveSupport)
            })
            .disposed(by: disposeBag)

        getVolumeBtn.rx.tap
            .subscribe(onNext: {
                BleManager.shared.send(preset: .getCurrentVolume)
            })
            .disposed(by: disposeBag)

        getProjectBtn.rx.tap
            .subscribe(onNext: {
                BleManager.shared.send(preset: .getProjectAndCustomer)
            })
            .disposed(by: disposeBag)

        fetchFilesBtn.rx.tap
            .subscribe(onNext: { [weak self] in
                guard let self else { return }
                let mode = self.selectedWiFiMode
                BleManager.shared.appendExternalLog("尝试通过 \(mode.title) 模式拉取文件列表，主机 \(mode.host)")
                GlassesHTTPClient.shared.fetchFileList(mode: mode) { result in
                    DispatchQueue.main.async {
                        switch result {
                        case .success(let text):
                            BleManager.shared.appendExternalLog("HTTP 文件列表返回:\n\(text)")
                        case .failure(let error):
                            BleManager.shared.appendExternalLog("HTTP 文件列表失败: \(error.localizedDescription)")
                        }
                    }
                }
            })
            .disposed(by: disposeBag)

        sendRawBtn.rx.tap
            .subscribe(onNext: { [weak self] in
                guard let self, let text = self.rawHexField.text, !text.isEmpty else {
                    BleManager.shared.appendExternalLog("请先输入要发送的 Hex")
                    return
                }
                BleManager.shared.send(rawHex: text)
            })
            .disposed(by: disposeBag)

        subTableView.rx.modelSelected(CBPeripheral.self)
            .subscribe(onNext: { peripheral in
                if peripheral.identifier == BleManager.shared.currentPeripheral?.identifier {
                    BleManager.shared.disconnect(peripheral: peripheral)
                } else {
                    BleManager.shared.connect(peripheral: peripheral)
                }
            })
            .disposed(by: disposeBag)
    }

    private var selectedWiFiMode: GlassesWiFiMode {
        GlassesWiFiMode(rawValue: modeControl.selectedSegmentIndex) ?? .p2p
    }

    private func makeButton(_ title: String) -> UIButton {
        let button = UIButton(type: .system)
        button.setTitle(title, for: .normal)
        button.setTitleColor(.white, for: .normal)
        button.backgroundColor = .systemBlue
        button.layer.cornerRadius = 8
        button.titleLabel?.font = .systemFont(ofSize: 13, weight: .medium)
        button.snp.makeConstraints { make in
            make.height.equalTo(40)
        }
        return button
    }

    private func makeRow(_ views: [UIView]) -> UIStackView {
        let stack = UIStackView(arrangedSubviews: views)
        stack.axis = .horizontal
        stack.alignment = .fill
        stack.distribution = .fillEqually
        stack.spacing = 8
        return stack
    }

    private func makeSectionTitle(_ title: String) -> UILabel {
        let label = UILabel()
        label.text = title
        label.font = .preferredFont(forTextStyle: .subheadline)
        label.textColor = .secondaryLabel
        return label
    }

    private func makeWiFiRow() -> UIView {
        let container = UIView()
        let stack = UIStackView()
        stack.axis = .horizontal
        stack.spacing = 8
        stack.alignment = .center

        let modeLabel = UILabel()
        modeLabel.text = "HTTP 模式"
        modeLabel.font = .systemFont(ofSize: 13, weight: .medium)

        stack.addArrangedSubview(modeLabel)
        stack.addArrangedSubview(modeControl)
        stack.addArrangedSubview(fetchFilesBtn)

        container.addSubview(stack)
        stack.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }
        fetchFilesBtn.snp.makeConstraints { make in
            make.width.greaterThanOrEqualTo(96)
        }
        return container
    }

    private func makeRawSendRow() -> UIView {
        let container = UIView()
        container.addSubview(rawHexField)
        container.addSubview(sendRawBtn)

        rawHexField.snp.makeConstraints { make in
            make.leading.top.bottom.equalToSuperview()
            make.height.equalTo(40)
        }

        sendRawBtn.snp.makeConstraints { make in
            make.leading.equalTo(rawHexField.snp.trailing).offset(8)
            make.trailing.top.bottom.equalToSuperview()
            make.width.equalTo(110)
        }

        return container
    }
}


