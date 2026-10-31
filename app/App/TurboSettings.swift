import UIKit

enum TurboSettings {
    static let flags: [(String, WritableKeyPath<PGTurboConfig, Bool>)] = [
        ("Bật turbo / backfire (thử nghiệm)", \.enabled),
        ("Lắp nâng cấp turbo khi lên xe", \.forceTurbo),
        ("Anti-lag: giữ boost khi nhả ga", \.antiLag),
        ("Lửa bô", \.effects), ("Âm thanh bô", \.sound),
        ("Tiếng nổ lớn khi nhả ga", \.loudOffThrottle),
        ("Giới hạn boost theo số", \.gearBoost), ("Đồng hồ boost trên màn hình", \.dial)]
    static let values: [(String, WritableKeyPath<PGTurboConfig, Float>)] = [
        ("RPM bắt đầu spool (0–1)", \.spoolStart), ("RPM đạt boost tối đa", \.spoolEnd),
        ("Boost chân không (−0,95–0)", \.minBoost), ("Boost tối đa (0–5)", \.maxBoost),
        ("Tốc độ spool (0–1, không gồm 1)", \.spoolRate), ("Tốc độ giảm boost (0–1)", \.unspoolRate),
        ("RPM bắt đầu giảm boost", \.falloffRPM), ("Boost ở giới hạn vòng tua", \.falloffBoost),
        ("RPM tối thiểu anti-lag", \.minRPM), ("Âm lượng (0–1)", \.volume)]
    static var config: PGTurboConfig = {
        var c = PGTurboDefaultConfig(), d = UserDefaults.standard
        for (name, key) in flags where d.object(forKey: "Turbo2."+name) != nil { c[keyPath:key] = d.bool(forKey:"Turbo2."+name) }
        for (name, key) in values where d.object(forKey: "Turbo2."+name) != nil { c[keyPath:key] = d.float(forKey:"Turbo2."+name) }
        if let gears = d.array(forKey:"Turbo2.gears") as? [Float], gears.count == 10 {
            withUnsafeMutableBytes(of:&c.gears) { $0.copyBytes(from:gears.withUnsafeBytes { Array($0) }) }
        }
        c.soundSet = UInt32(min(2,max(0,d.integer(forKey:"Turbo2.soundSet"))))
        if d.object(forKey:"Turbo2.period") != nil { c.periodMS = UInt32(clamping:d.integer(forKey:"Turbo2.period")) }
        if d.object(forKey:"Turbo2.random") != nil { c.randomMS = UInt32(clamping:d.integer(forKey:"Turbo2.random")) }
        if d.object(forKey:"Turbo2.loud") != nil { c.loudIntervalMS = UInt32(clamping:d.integer(forKey:"Turbo2.loud")) }
        return c
    }()
    @discardableResult static func apply() -> Bool {
        guard PGSetTurboConfig(config) else { return false }
        let d=UserDefaults.standard
        for (name,key) in flags { d.set(config[keyPath:key],forKey:"Turbo2."+name) }
        for (name,key) in values { d.set(config[keyPath:key],forKey:"Turbo2."+name) }
        let gears = withUnsafeBytes(of:config.gears) { Array($0.bindMemory(to:Float.self)) }
        d.set(gears,forKey:"Turbo2.gears");d.set(config.soundSet,forKey:"Turbo2.soundSet")
        d.set(config.periodMS,forKey:"Turbo2.period");d.set(config.randomMS,forKey:"Turbo2.random");d.set(config.loudIntervalMS,forKey:"Turbo2.loud")
        DispatchQueue.main.async { TurboHUD.shared.updateTimer() }
        return true
    }
}

final class TurboHUD {
    static let shared=TurboHUD()
    private var timer:Timer?
    private let label=UILabel()
    func updateTimer() {
        timer?.invalidate();timer=nil;label.removeFromSuperview()
        guard TurboSettings.config.enabled && TurboSettings.config.dial else { return }
        label.font = .monospacedDigitSystemFont(ofSize:12,weight:.medium)
        label.textColor = .white;label.backgroundColor=UIColor.black.withAlphaComponent(0.65)
        label.layer.cornerRadius=6;label.clipsToBounds=true;label.isUserInteractionEnabled=false
        label.textAlignment = .center;label.numberOfLines=2
        timer=Timer.scheduledTimer(withTimeInterval:0.25,repeats:true) { [weak self] _ in self?.refresh() }
    }
    private func refresh() {
        var rpm:Float=0,boost:Float=0,gear:UInt32=0
        guard PGTurboTelemetry(&rpm,&boost,&gear) else { label.isHidden=true;return }
        if label.superview == nil,
           let scene=UIApplication.shared.connectedScenes.first(where:{$0.activationState == .foregroundActive}) as? UIWindowScene,
           let window=scene.windows.first(where:{$0.isKeyWindow}) {
            label.translatesAutoresizingMaskIntoConstraints=false;window.addSubview(label)
            NSLayoutConstraint.activate([label.leadingAnchor.constraint(equalTo:window.safeAreaLayoutGuide.leadingAnchor,constant:12),label.topAnchor.constraint(equalTo:window.safeAreaLayoutGuide.topAnchor,constant:12),label.widthAnchor.constraint(equalToConstant:180),label.heightAnchor.constraint(equalToConstant:42)])
        }
        label.text=String(format:"Turbo %.2f · Số %u\nRPM %.0f%%",boost,gear,rpm*100);label.isHidden=false
    }
}

final class TurboSettingsViewController:UITableViewController {
    init(){super.init(style:.insetGrouped);title="Turbo và lửa bô"}
    required init?(coder:NSCoder){fatalError()}
    override func numberOfSections(in tableView:UITableView)->Int{5}
    override func tableView(_ tableView:UITableView,numberOfRowsInSection section:Int)->Int{
        [TurboSettings.flags.count,TurboSettings.values.count,10,3,2][section]
    }
    override func tableView(_ tableView:UITableView,titleForHeaderInSection section:Int)->String?{
        ["Chức năng", "Turbo / anti-lag", "Boost số 1–10", "Khoảng nghỉ (ms)", "Âm thanh / khôi phục"][section]
    }
    override func tableView(_ tableView:UITableView,cellForRowAt indexPath:IndexPath)->UITableViewCell{
        let cell=UITableViewCell(style:.value1,reuseIdentifier:nil),c=TurboSettings.config,r=indexPath.row
        switch indexPath.section {
        case 0:
            let (title,key)=TurboSettings.flags[r];cell.textLabel?.text=title
            let toggle=UISwitch();toggle.isOn=c[keyPath:key]
            toggle.addAction(UIAction { [weak self] _ in
                let old=TurboSettings.config;TurboSettings.config[keyPath:key]=toggle.isOn
                self?.save(old)
            },for:.valueChanged);cell.accessoryView=toggle
        case 1: let (title,key)=TurboSettings.values[r];cell.textLabel?.text=title;cell.detailTextLabel?.text=String(c[keyPath:key])
        case 2:
            cell.textLabel?.text="Số \(r+1)";cell.detailTextLabel?.text=withUnsafeBytes(of:c.gears){String($0.bindMemory(to:Float.self)[r])}
        case 3:cell.textLabel?.text=["Chu kỳ nổ (ít nhất 100 ms)","Khoảng ngẫu nhiên","Khoảng nổ lớn"][r];cell.detailTextLabel?.text=String([c.periodMS,c.randomMS,c.loudIntervalMS][r])
        default:cell.textLabel?.text=r==0 ? "Bộ âm thanh" : "Khôi phục mặc định (tắt)";if r==0{cell.detailTextLabel?.text=["backfire","Default","Default-Old"][Int(c.soundSet)]}
        }
        return cell
    }
    private func save(_ old:PGTurboConfig){
        if !TurboSettings.apply(){TurboSettings.config=old
            let alert=UIAlertController(title:"Thông số không hợp lệ",message:"RPM kết thúc phải lớn hơn RPM bắt đầu; tốc độ spool phải nhỏ hơn 1; boost tối đa 5; chu kỳ tối thiểu 100 ms.",preferredStyle:.alert)
            alert.addAction(UIAlertAction(title:"Đóng",style:.cancel));present(alert,animated:true)
        };tableView.reloadData()
    }
    override func tableView(_ tableView:UITableView,didSelectRowAt p:IndexPath){
        tableView.deselectRow(at:p,animated:true);guard p.section>0 else{return}
        let old=TurboSettings.config
        if p.section==4 {
            if p.row==1{TurboSettings.config=PGTurboDefaultConfig();save(old);return}
            let alert=UIAlertController(title:"Bộ âm thanh",message:nil,preferredStyle:.alert)
            for (i,name) in ["backfire","Default","Default-Old"].enumerated(){alert.addAction(UIAlertAction(title:name,style:.default){[weak self] _ in TurboSettings.config.soundSet=UInt32(i);self?.save(old)})}
            alert.addAction(UIAlertAction(title:"Hủy",style:.cancel));present(alert,animated:true);return
        }
        let alert=UIAlertController(title:"Nhập thông số",message:"Dùng dấu chấm cho phần thập phân.",preferredStyle:.alert)
        alert.addTextField{$0.keyboardType = .numbersAndPunctuation;$0.text=tableView.cellForRow(at:p)?.detailTextLabel?.text}
        alert.addAction(UIAlertAction(title:"Lưu",style:.default){[weak self] _ in
            guard let text=alert.textFields?.first?.text,let number=Float(text.replacingOccurrences(of:",",with:".")),number.isFinite else{return}
            switch p.section {
            case 1:TurboSettings.config[keyPath:TurboSettings.values[p.row].1]=number
            case 2:withUnsafeMutableBytes(of:&TurboSettings.config.gears){$0.bindMemory(to:Float.self)[p.row]=number}
            default:
                guard number>=0 && number<=10000 else{return}
                if p.row==0{TurboSettings.config.periodMS=UInt32(number)}else if p.row==1{TurboSettings.config.randomMS=UInt32(number)}else{TurboSettings.config.loudIntervalMS=UInt32(number)}
            };self?.save(old)
        });alert.addAction(UIAlertAction(title:"Hủy",style:.cancel));present(alert,animated:true)
    }
    override func tableView(_ tableView:UITableView,titleForFooterInSection section:Int)->String?{
        section==0 ? "Bản chuyển native thử nghiệm dành cho xe người chơi đang lái, dùng nâng cấp turbo của xe. Bật lắp turbo rồi lên xe lại nếu xe chưa có turbo. Thông số áp dụng ngay. Chưa kiểm chứng trên iPhone. Đồng hồ là HUD của bản port; DashHook, menu F10, preset theo biển số và NPC chưa được chuyển. Xe thiếu bone exhaust sẽ không có hiệu ứng bô. Việc lắp nâng cấp turbo sẽ giữ trên xe ngay cả khi tắt tính năng." : nil
    }
}
