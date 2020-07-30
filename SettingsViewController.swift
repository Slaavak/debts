//
//  SettingsViewController.swift
//  debts
//
//  Created by Slava Korolevich on 7/5/19.
//  Copyright © 2019 Slava Korolevich. All rights reserved.
//

import UIKit
import CoreData

protocol SettingsViewControllerDelegate: class {
    func settingsViewController(_ viewController: SettingsViewController, didChangeCurrency currency: String?)
}

class SettingsViewController: BaseViewController, MainCurrencyViewControllerDelegate, UITableViewDelegate, UITableViewDataSource, ColorPaletteViewControllerDelegate {
    
    // MARK: - Nested Types
    
    enum Field {
        case baseCurrency
        case pallette
        case icloudSync
        case aboutUs
        case icloudSyncNow
        case suggestIdea
        case shareApplication
        case donate
    }
    
    class ViewModel {
        let field: Field
        let text: String?
        var textColor: UIColor?
        var subtitle: String?
        let accessoryView: UIView?
        let selectionStyle: UITableViewCell.SelectionStyle
        let image: UIImage?
        
        init(field: Field, text: String?, textColor: UIColor? = nil, subtitle: String?, accessoryView: UIView?, selectionStyle: UITableViewCell.SelectionStyle = .default, image: UIImage? = nil) {
            self.field = field
            self.text = text
            self.textColor = textColor
            self.subtitle = subtitle
            self.accessoryView = accessoryView
            self.selectionStyle = selectionStyle
            self.image = image
        }
    }
    
    // MARK: - Properties
    
    var displayingViewModels: [[ViewModel]] = []
    var allViewModels: [[ViewModel]] = []
    
    var selectedCurrency: String? = nil
    let context = DataStorage.shared.mainManagedObjectContext
    
    private let cellId = "cell"
    
    @IBOutlet weak var settingsTableView: UITableView!
    
    weak var delegate: SettingsViewControllerDelegate?
    
    // MARK: - UIViewController Lifecycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        title = Strings.Settings.title
        settingsTableView.delegate = self
        settingsTableView.dataSource = self
        settingsTableView.backgroundColor = .clear
        
        settingsTableView.separatorStyle = .singleLine
        let width = settingsTableView.frame.size.width * 0.04
        settingsTableView.separatorInset = UIEdgeInsets(top: 0, left: width, bottom: 0, right: width)
        
        selectedCurrency = DebtSharedInfo.getSharedInContext(context)?.mainCurrency ?? Strings.Settings.baseCurrencyNotSelected
        
        loadViewModels()
        reloadShowingViewModels()
        applyStyle()
        
        NotificationCenter.default.addObserver(forName: Cloud.accountStatusDidChange, object: nil, queue: .main) { notification in
            self.reloadShowingViewModels()
            self.settingsTableView.reloadData()
        }
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        settingsTableView.reloadData()
        mainTabBarController?.setTabBarHidden(true, animated: animated)
        addDefaultBackButtonIfNeeded()
    }
    
    // MARK: - View Models
    
    private func loadViewModels() {
        let iCloudSwitch = UISwitch()
        iCloudSwitch.addTarget(self, action: #selector(switchChangedValue(_:)), for: .valueChanged)
        iCloudSwitch.isOn = Cloud.instance.iCloudUserLevelEnabledAttribute.getValue() ?? true
        allViewModels = [[.init(field: .baseCurrency, text: Strings.Settings.baseCurrency, subtitle: selectedCurrency, accessoryView: UIImageView(image: ImageAsset.listArrow))],
                         [.init(field: .pallette, text: Strings.Settings.palette, subtitle: Style.paletteSetting.description, accessoryView: UIImageView(image: ImageAsset.listArrow)),
                          .init(field: .icloudSync, text: Strings.Settings.syncSetting, subtitle: nil, accessoryView: iCloudSwitch, selectionStyle: .none),
                          .init(field: .aboutUs, text: Strings.Settings.aboutTeam, subtitle: nil, accessoryView: UIImageView(image: ImageAsset.listArrow))],
                         [.init(field: .icloudSyncNow, text: Strings.Settings.syncAction, subtitle: nil, accessoryView: nil)],
                         [.init(field: .suggestIdea, text: Strings.Settings.suggestIdea, subtitle: nil, accessoryView: nil),
                          .init(field: .shareApplication, text: Strings.Settings.shareApplication, subtitle: nil, accessoryView: nil)],
                         [.init(field: .donate, text: Strings.Settings.donate, subtitle: nil, accessoryView: UIImageView(image: ImageAsset.listArrow), image: ImageAsset.donateIcon)],

        ]
    }
    
    private func reloadShowingViewModels() {
        var fieldsNotToShow: [Field] = []
        
        if !Cloud.instance.iCloudSystemLevelEnabled {
            fieldsNotToShow.append(.icloudSync)
            fieldsNotToShow.append(.icloudSyncNow)
        }
        if !EmailManager.instance.canSendEmail() {
            fieldsNotToShow.append(.suggestIdea)
        }
        
        if fieldsNotToShow.count == 0 {
            displayingViewModels = allViewModels
        } else {
            displayingViewModels.removeAll()
            for sectionArray in allViewModels {
                let filtered = sectionArray.filter({ !fieldsNotToShow.contains($0.field) })
                if filtered.count > 0 {
                    displayingViewModels.append(filtered)
                }
            }
        }
        
        Anal.Settings.screenReload(showICloud: Cloud.instance.iCloudSystemLevelEnabled, showEmail: EmailManager.instance.canSendEmail())
    }
    
    private func viewModelFor(field: Field) -> ViewModel? {
        return allViewModels.flatMap({ $0 }).first(where: { $0.field == field })
    }
    
    private func updateViewModelsStyle() {
        viewModelFor(field: .baseCurrency)?.textColor = Color.titleText
        viewModelFor(field: .pallette)?.textColor = Color.titleText
        
        if let icloudViewModel = viewModelFor(field: .icloudSync) {
            icloudViewModel.textColor = Color.titleText
            if let switchControl = icloudViewModel.accessoryView as? UISwitch {
                updateSwitchUI(switchControl: switchControl)
            }
        }
        viewModelFor(field: .aboutUs)?.textColor = Color.titleText
        viewModelFor(field: .icloudSyncNow)?.textColor = Color.activeElements
        viewModelFor(field: .suggestIdea)?.textColor = Color.activeElements
        viewModelFor(field: .shareApplication)?.textColor = Color.activeElements
        viewModelFor(field: .donate)?.textColor = Color.titleText
    }
    
    private func indexPath(for field: Field) -> IndexPath? {
        for section in 0..<displayingViewModels.count {
            for row in 0..<displayingViewModels[section].count {
                if displayingViewModels[section][row].field == field {
                    return IndexPath(row: row, section: section)
                }
            }
        }
        return nil
    }
    
    private func updateField(_ field: Field, animation: UITableView.RowAnimation) {
        if let indexPath = indexPath(for: field) {
            settingsTableView.reloadRows(at: [indexPath], with: animation)
        }
    }
    
    // MARK: - UI
    
    private func updateSwitchUI(switchControl: UISwitch) {
        if switchControl.isOn {
            switchControl.backgroundColor = Color.inputBackground
            switchControl.onTintColor = Color.activeElements.withAlphaComponent(0.3)
            switchControl.thumbTintColor = Color.activeElements
        } else {
            switchControl.backgroundColor = Color.activeInputText.withAlphaComponent(0.3)
            switchControl.layer.cornerRadius = switchControl.frame.height / 2
            switchControl.thumbTintColor = Color.activeInputText
        }
    }
    
    // MARK: - UITableViewDataSource && UITableViewDelegate
    
    func tableView(_ tableView: UITableView, viewForFooterInSection section: Int) -> UIView? {
        let headerView = UIView(frame: CGRect(x: 0, y: 0, width: tableView.bounds.size.width, height: 24))
        headerView.backgroundColor = Color.mainBackground
        return headerView
    }
    
    func tableView(_ tableView: UITableView, heightForFooterInSection section: Int) -> CGFloat {
        return 24
    }
    
    func numberOfSections(in tableView: UITableView) -> Int {
        return displayingViewModels.count
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return displayingViewModels[section].count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: cellId) ?? UITableViewCell(style: .value1, reuseIdentifier: cellId)
        cell.backgroundColor = Color.inputBackground
        cell.textLabel?.font = Font.contentFont
        cell.detailTextLabel?.font = Font.contentFont
        cell.detailTextLabel?.textColor = Color.passiveElement
        
        let viewModel = displayingViewModels[indexPath.section][indexPath.row]
        cell.selectionStyle = viewModel.selectionStyle
        cell.textLabel?.textColor = viewModel.textColor
        cell.textLabel?.text = viewModel.text
        cell.detailTextLabel?.text = viewModel.subtitle
        cell.accessoryView = viewModel.accessoryView
        cell.imageView?.image = viewModel.image
        
        let selectionBackground = UIView()
        selectionBackground.backgroundColor = Color.tagBackground
        cell.selectedBackgroundView = selectionBackground
        
        return cell
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        
        let field = displayingViewModels[indexPath.section][indexPath.row].field
        switch field {
        case .baseCurrency:
            Anal.Settings.selectCurrency()
            
            let vc = storyboard?.instantiateViewController(withIdentifier: "MainCurrencyVC") as! MainCurrencyViewController
            vc.delegate = self
            navigationController?.pushViewController(vc, animated: true)
        case .pallette:
            Anal.Settings.colorPalette()
            
            let vc = ColorPaletteViewController.loadFormStoryboard()
            vc.delegate = self
            navigationController?.pushViewController(vc, animated: true)
        case .icloudSync:
            break
        case .aboutUs:
            Anal.Settings.aboutApplication()
            
            let vc = AboutUsViewController()
            navigationController?.pushViewController(vc, animated: true)
        case .icloudSyncNow:
            Anal.Settings.syncWithICloud()
            
            if Cloud.instance.iCloudSystemLevelEnabled {
                let controller = ActivityController.controllerFor(indicatorType: .pacman, color: .white)
                mainTabBarController?.present(controller, animated: true, completion: nil)
                
                Cloud.instance.synchronize(force: true) { [weak controller] error in
                    DispatchQueue.main.async {
                        controller?.dismiss(animated: true, completion: nil)
                    }
                }
            }
        case .suggestIdea:
            Anal.Settings.suggentIdea()
            
            EmailManager.instance.sendDefaultEmail(from: self)
        case .shareApplication:
            Anal.Settings.shareApplication()
            
            SharingManager.instance.shareApplication(from: self)
        case .donate:
            Anal.Settings.donate()
            
            DeviceRouter.openLink(Links.donations)
        }
    }
    
    // MARK: - Actions
    
    @objc func switchChangedValue(_ switchControl: UISwitch) {
        Anal.Settings.iCloudSwitch(value: switchControl.isOn)
        
        Cloud.instance.iCloudUserLevelEnabledAttribute.setValue(switchControl.isOn)
        updateSwitchUI(switchControl: switchControl)
    }
    
    // MARK: - Apply Style
    
    override func applyStyle() {
        super.applyStyle()
        
        view.backgroundColor = Color.mainBackground
        settingsTableView.separatorColor = Color.tagBackground
        updateViewModelsStyle()
        settingsTableView.reloadData()
        
        addDefaultBackButtonIfNeeded()
    }
    
    // MARK: - Main currency delegate
    
    func mainCurrencyViewController(_ viewController: MainCurrencyViewController, didChangeCurrency currency: String?) {
        navigationController?.popViewController(animated: true)
        viewModelFor(field: .baseCurrency)?.subtitle = currency
        delegate?.settingsViewController(self, didChangeCurrency: currency)
    }
    
    // MARK: - ColorPaletteViewControllerDelegate
    
    func colorPaletteViewControllerDidUpdateColorPalette(_ viewController: ColorPaletteViewController) {
        viewModelFor(field: .pallette)?.subtitle = Style.paletteSetting.description
        navigationController?.popToViewController(self, animated: true)
    }
}
