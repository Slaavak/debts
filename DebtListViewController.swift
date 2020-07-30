//
//  DebtListViewController.swift
//  debts
//
//  Created by Slava Korolevich on 5/8/19.
//  Copyright © 2019 Slava Korolevich. All rights reserved.
//

import UIKit
import CoreData
import CloudKit

class DebtListViewController: BaseViewController, UITableViewDataSource, UITableViewDelegate, NSFetchedResultsControllerDelegate, TabBarViewControllerChild, SettingsViewControllerDelegate, CreateDebtViewControllerDelegate, DebtInfoViewControllerDelegate, CloseDebtViewControllerDelegate {

    enum DebtType {
        case myDebt
        case toMe
    }
    
    enum SegmentItem: Int, CaseIterable {
        case allTime = 0
        case week
        case month
        case year
        
        var name: String {
            switch self {
            case .allTime: return Strings.DebtList.segmentAllTime
            case .week: return Strings.DebtList.segmentWeek
            case .month: return Strings.DebtList.segmentMonth
            case .year: return Strings.DebtList.segmentYear
            }
        }
    }
    
    enum DebtsState {
        case noDebts
        case debtExist
    }
    
    struct UISettings {
        struct SegmentControl {
            static let insets = UIEdgeInsets(top: 17, left: 17, bottom: 17, right: 17)
            static let height: CGFloat = 38
            
            static var fullHeight: CGFloat {
                return insets.top + insets.bottom + height
            }
        }
    }
    
    // MARK: - Properties
   
    private lazy var fetchedResultController: NSFetchedResultsController<Debt> = {
        let fetchRequest = NSFetchRequest<Debt>(entityName: "Debt")
        fetchRequest.sortDescriptors = [NSSortDescriptor(key: "isDateSet", ascending: false), NSSortDescriptor(key: "date", ascending: true), NSSortDescriptor(key: "lastUpdateDate", ascending: false)]

        fetchRequest.predicate = defaultPredicate
        let fetchedResultsController = NSFetchedResultsController(fetchRequest: fetchRequest, managedObjectContext: context, sectionNameKeyPath: "isExpired", cacheName: nil)
        return fetchedResultsController
    }()
    
    private lazy var defaultPredicate: NSPredicate = {
        let isClosedPredicate = NSPredicate(format: "isClosed = nil || isClosed = false")
        let isMyDebtPredicate = NSPredicate(format: "isMyDebt == %@", NSNumber(value:  debtType == .myDebt ? true : false))
        return NSCompoundPredicate(andPredicateWithSubpredicates: [isClosedPredicate, isMyDebtPredicate])
    }()
    
    var debtType: DebtType = .myDebt
    
    private let cellReuseID = "cell"
    private let context = DataStorage.shared.mainManagedObjectContext
    private var mainCurrency: String?
    private var mainCurrencyValue: Double?
    private var headerSegmentControl: UISegmentedControl!
    private var segmentContainerView: UIView!
    private let generalPlaceholder = PlaceholderView()
    private let segmentItemPlaceholder = PlaceholderView()
    private var tableView: UITableView!
    private lazy var df: DateFormatter = {
        let df = DateFormatter()
        df.setLocalizedDateFormatFromTemplate("dMMMM")
        return df
    }()
    private lazy var nf: NumberFormatter = {
        let nf = NumberFormatter()
        nf.minimumFractionDigits = 2
        nf.maximumFractionDigits = 2
        return nf
    }()
    private var debtsState: DebtsState = .noDebts
    
    private var firstAppear = true
    
    // MARK: - UIViewController Lifecycle
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        tableView = UITableView(frame: .zero, style: .plain)
        tableView.backgroundColor = .clear
        tableView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tableView)
        [tableView.topAnchor.constraint(equalTo: view.topAnchor),
        tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view
                .trailingAnchor)].activate()
        tableView.dataSource = self
        tableView.delegate = self
        let width = tableView.frame.size.width * 0.04
        tableView.separatorInset = UIEdgeInsets(top: 0, left: width, bottom: 0, right: width)
        tableView.register(UINib.init(nibName: "DebtViewCell", bundle: nil), forCellReuseIdentifier: cellReuseID)
        tableView.tableFooterView = UIView()
        tableView.contentInset.bottom = 30
        tableView.separatorStyle = UITableViewCell.SeparatorStyle.singleLine

        navigationController?.navigationBar.isTranslucent = false
        configureSegmentControl()
        configurePlaceholder()
        
        updateMainCurrencyInfo()
       
        title = (debtType == .myDebt ? Strings.DebtList.screenTitleMyDebts : Strings.DebtList.screenTitleDebtsToOther)
        
        NotificationCenter.default.addObserver(forName: .NSManagedObjectContextDidSave, object: context, queue: nil) { notification in
            self.reloadDebtHistoryIcon()
        }
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        mainTabBarController?.setTabBarHidden(false, animated: true)
        
        if firstAppear {
            fetchedResultController.delegate = self
            
            self.indexChanged(headerSegmentControl)

            syncTableViewPlaceholder()
            firstAppear = false
            
            applyStyle()
        }
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if (tableView.tableHeaderView?.bounds.width ?? 0) != view.bounds.width {
            layoutTableViewHeader()
        }
    }
    
    // MARK: - Layout
    
    private func layoutTableViewHeader() {
        let insets = UISettings.SegmentControl.insets
        let controlHeight = UISettings.SegmentControl.height
        
        segmentContainerView.frame = CGRect(x: 0, y: 0, width: view.bounds.width, height: controlHeight + insets.top + insets.bottom)
        headerSegmentControl.frame = CGRect(x: insets.left, y: insets.top, width: view.bounds.width - insets.left - insets.right, height: controlHeight)
        
        tableView.tableHeaderView = segmentContainerView
    }
    
    // MARK: - UITableViewDataSource && UITableViewDelegate
    
    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        return 28
    }
    
    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        let headerView = UIView()
        let headerLabel = UILabel(frame: CGRect(x: 16, y: 5, width: tableView.bounds.size.width, height: 18))
        headerView.backgroundColor = Color.headerBackground
        headerLabel.font = Font.cardTitle
        headerLabel.textColor = Color.titleText
        
        switch section {
        case 0:
            let debt = fetchedResultController.object(at: IndexPath(row: 0, section: 0))
            if debt.isExpired {
                headerLabel.text = Strings.DebtList.sectionExpired
            } else {
                headerLabel.text = Strings.DebtList.sectionRelevant
            }
        case 1:
            headerLabel.text = Strings.DebtList.sectionRelevant
        default:
            break
        }
        
        headerView.addSubview(headerLabel)
        
        return headerView
    }

    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        guard let sections = fetchedResultController.sections else { return nil }
        let currentSection = sections[section]
        return currentSection.name
    }
    
    func numberOfSections(in tableView: UITableView) -> Int {
        return fetchedResultController.sections?.count ?? 0
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if let sections = fetchedResultController.sections {
            return sections[section].numberOfObjects
        } else {
            return 0
        }
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: cellReuseID, for: indexPath) as! DebtViewCell
        let debt = fetchedResultController.object(at: indexPath)
        
        updateCell(cell: cell, with: debt)
        
        return cell
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let debt = fetchedResultController.object(at: indexPath)
        Anal.DebtList.didSelectDebt(myDebts: debtType == .myDebt)
        let debtInfoVC = DebtInfoViewController.loadFormStoryboard(debtID: debt.objectID, context: context)
        debtInfoVC.delegate = self
        navigationController?.pushViewController(debtInfoVC, animated: true)
        
        tableView.deselectRow(at: indexPath, animated: true)
    }
    
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return 60
    }
    
    func tableView(_ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        let debtObjectID = fetchedResultController.object(at: indexPath).objectID
        let closeDebtAction = UIContextualAction(style: .normal, title: Strings.DebtList.closeDebtAction) { (action, view, bool) in
            Anal.DebtList.closeDebt(myDebts: self.debtType == .myDebt)
            
            let closeDebtVC = CloseDebtViewController.loadFormStoryboard(debtID: debtObjectID, context: self.context)
            closeDebtVC.delegate = self
            self.navigationController?.pushViewController(closeDebtVC, animated: true)
            self.tableView.isEditing = false
        }
        closeDebtAction.backgroundColor = Color.good
        let configuration = UISwipeActionsConfiguration(actions: [closeDebtAction])
        configuration.performsFirstActionWithFullSwipe = true
        return configuration
    }
    
    // MARK: - Update
    
    private func updateCell(cell: DebtViewCell, with debt: Debt) {
        cell.nameLabel.text = debt.name
        
        if let date = debt.date {
            cell.dateLabel.text = Strings.Common.tillColon + " " + df.string(from: date as Date)
        } else {
            cell.dateLabel.text = nil
        }
        
        var image: UIImage? = nil
        
        if let thingName = debt.thingName {
            cell.moneyInfoStackView.isHidden = true
            cell.thingContainerView.isHidden = false

            cell.thingLabel.text = thingName.uppercased()
            
            if debt.isExpired {
                cell.thingLabel.textColor = Color.outstandingElements
                image = ImageAsset.outThingIcon
            } else {
                cell.thingLabel.textColor = Color.tagTextColor
                image = ImageAsset.thingIcon
            }
        } else if let moneyAmount = debt.moneyAmount {
            cell.moneyInfoStackView.isHidden = false
            cell.thingContainerView.isHidden = true
            
            cell.amountLabel.text = [debt.currency?.code, nf.string(from: moneyAmount)].compactMap({ $0 }).joined(separator: " ")
            
            var showingMainCurrency = false
            if let mainCurrency = mainCurrency, let mainCurrencyValue = mainCurrencyValue, let currency = debt.currency {
                if mainCurrency != currency.code {
                    let convertedValue = moneyAmount.doubleValue * mainCurrencyValue / currency.value
                    cell.mainCurrencyLabel.text = "~ " + [mainCurrency, nf.string(from: NSNumber(value: convertedValue))].compactMap({ $0 }).joined(separator: " ")
                    showingMainCurrency = true
                }
            }
            cell.mainCurrencyLabel.isHidden = !showingMainCurrency
            
            if debt.isExpired {
                image = ImageAsset.outMoneyIcon
            } else {
                image = ImageAsset.moneyIcon
            }
        } else {
            cell.moneyInfoStackView.isHidden = true
            cell.thingContainerView.isHidden = true
        }
        cell.icon.image = image
        
        cell.applyStyle()
    }
    
    // MARK: - NSFetchedResultsControllerDelegate

    func controllerWillChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
        tableView.beginUpdates()
    }
    
    func controller(_ controller: NSFetchedResultsController<NSFetchRequestResult>, didChange anObject: Any, at indexPath: IndexPath?, for type: NSFetchedResultsChangeType, newIndexPath: IndexPath?) {
        switch type {
        case .insert:
            if let newIndexPath = newIndexPath {
                tableView.insertRows(at: [newIndexPath], with: .automatic)
            }
        case .update:
            if let indexPath = indexPath {
                if let cell = tableView.cellForRow(at: indexPath) as? DebtViewCell {
                    let debt = fetchedResultController.object(at: indexPath)
                    updateCell(cell: cell, with: debt)
                }
            }
        case .move:
            if let newIndexPath = newIndexPath {
                tableView.moveRow(at: indexPath!, to: newIndexPath)
            }
        case .delete:
            if let indexPath = indexPath {
                tableView.deleteRows(at: [indexPath], with: .automatic)
            }
        @unknown default:
            break
        }
    }
    
    func controller(_ controller: NSFetchedResultsController<NSFetchRequestResult>, didChange sectionInfo: NSFetchedResultsSectionInfo, atSectionIndex sectionIndex: Int, for type: NSFetchedResultsChangeType) {
        switch type {
        case .insert:
            tableView.insertSections(IndexSet(integer: sectionIndex), with: .automatic)
        case .update:
            tableView.reloadSections(IndexSet(integer: sectionIndex), with: .automatic)
        case .delete:
            tableView.deleteSections(IndexSet(integer: sectionIndex), with: .automatic)
        default:
            break
        }
    }
    
    func controllerDidChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
        tableView.endUpdates()
        syncTableViewPlaceholder()
    }
    
    // MARK: - SegmentControl
    
    func configureSegmentControl() {
        segmentContainerView = UIView()
        
        headerSegmentControl = UISegmentedControl(items: SegmentItem.allCases.map({ $0.name }))
        segmentContainerView.addSubview(headerSegmentControl)
        headerSegmentControl.selectedSegmentIndex = 0
        headerSegmentControl.addTarget(self, action: #selector(indexChanged(_:)), for: .valueChanged)
     
        layoutTableViewHeader()
    }
    
    @objc func indexChanged(_ sender: UISegmentedControl) {
        if let segmentItem = SegmentItem(rawValue: sender.selectedSegmentIndex) {
            Anal.DebtList.switchSegmentControl(item: segmentItem)
            
            let maximumDate: Date?
            switch segmentItem {
            case .allTime: maximumDate = nil
            case .week: maximumDate = Date().addingComponent(.day, count: 7)
            case .month: maximumDate = Date().addingComponent(.month, count: 1)
            case .year: maximumDate = Date().addingComponent(.year, count: 1)
            }
            
            var predicates = [defaultPredicate]
            if let maximumDate = maximumDate {
                predicates.append(NSPredicate(format: "date <= %@", maximumDate as NSDate))
            }
            self.fetchedResultController.fetchRequest.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
            try? fetchedResultController.performFetch()
            
            tableView.reloadData()
            
            UserSettings.debtListSelectedSegmentIndex.setValue(sender.selectedSegmentIndex)
        }
        syncItemTablePlaceholder()
    }
    
    // MARK:- TableViewPlaceHolder
    
    private func syncTableViewPlaceholder() {
        let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "Debt")
        fetchRequest.predicate = defaultPredicate
        let debtsCount = (try? context.count(for: fetchRequest)) ?? 0
        debtsState = (debtsCount == 0) ? .noDebts : .debtExist
        if debtsState == .debtExist {
            generalPlaceholder.isHidden = true
            tableView.isHidden = false
            segmentItemPlaceholder.isHidden = false
        } else {
            generalPlaceholder.isHidden = false
            tableView.isHidden = true
            segmentItemPlaceholder.isHidden = true
        }
        syncItemTablePlaceholder()
    }
    
    private func syncItemTablePlaceholder() {
        if debtsState == .debtExist {
            if fetchedResultController.sections?.contains(where: { $0.numberOfObjects > 0}) ?? false  {
                segmentItemPlaceholder.isHidden = true
            } else {
                segmentItemPlaceholder.isHidden = false
            }
        }
    }

    private func configurePlaceholder() {
        generalPlaceholder.title = Strings.DebtList.generalPlaceholderTitle
        generalPlaceholder.subtitle = Strings.DebtList.generalPlaceholderSubtitle
        generalPlaceholder.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(generalPlaceholder)
        
        [generalPlaceholder.topAnchor.constraint(equalTo: view.topAnchor),
        generalPlaceholder.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        generalPlaceholder.leadingAnchor.constraint(equalTo: view.leadingAnchor),
        generalPlaceholder.trailingAnchor.constraint(equalTo: view.trailingAnchor)].activate()
        
        segmentItemPlaceholder.title = Strings.DebtList.itemPlaceholderTitle
        segmentItemPlaceholder.subtitle = nil
        segmentItemPlaceholder.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(segmentItemPlaceholder)
        
        [segmentItemPlaceholder.topAnchor.constraint(equalTo: view.topAnchor, constant: UISettings.SegmentControl.fullHeight),
         segmentItemPlaceholder.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -14),
        segmentItemPlaceholder.leadingAnchor.constraint(equalTo: view.leadingAnchor),
        segmentItemPlaceholder.trailingAnchor.constraint(equalTo: view.trailingAnchor)].activate()
    }

    // MARK: - Actions
    
    @objc func settingsButtonTapped() {
        Anal.DebtList.settingsTapped()
        
        let vc = UIStoryboard(name: "Main", bundle: nil).instantiateViewController(withIdentifier: "SettingsVC")
        (vc as? SettingsViewController)?.delegate = self
        navigationController?.pushViewController(vc, animated: true)
    }
    
    @objc func historyButtonTapped() {
        Anal.DebtList.historyTapped()
        
        let vc = DebtHistoryViewController()
        navigationController?.pushViewController(vc, animated: true)
    }
    
    // MARK: - StyleController
    
    override func applyStyle() {
        generalPlaceholder.applyStyle()
        segmentItemPlaceholder.applyStyle()
        
        if #available(iOS 13.0, *) {
            headerSegmentControl.selectedSegmentTintColor = Color.activeElements
            headerSegmentControl.setTitleTextAttributes([.foregroundColor: Color.activeElements], for: .normal)
            headerSegmentControl.setTitleTextAttributes([.foregroundColor: Color.buttonColor], for: .selected)
            headerSegmentControl.layer.borderWidth = 1
            headerSegmentControl.layer.borderColor = Color.activeElements.cgColor
        } else {
            headerSegmentControl.setTitleTextAttributes([.foregroundColor: Color.buttonColor], for: .selected)
            
            headerSegmentControl.backgroundColor = Color.headerBackground
            headerSegmentControl.tintColor = Color.activeElements
        }
        segmentContainerView.backgroundColor = Color.mainBackground
        
        let rightButtonItem = UIBarButtonItem.init(image: ImageAsset.settings, style: .done, target: self, action: #selector(settingsButtonTapped))
        self.navigationItem.rightBarButtonItem = rightButtonItem
        
        reloadDebtHistoryIcon()
        
        view.backgroundColor = Color.mainBackground
        tableView.separatorColor = Color.tagBackground
        tableView.reloadData()
    }
    
    // MARK: - Currency
    
    private func updateMainCurrencyInfo() {
        let mainCurrency = DebtSharedInfo.getSharedInContext(context)?.mainCurrencyRelationship
        self.mainCurrency = mainCurrency?.code
        self.mainCurrencyValue = mainCurrency?.value
    }
    
    // MARK: - TabBarViewControllerChild
    
    func tabViewControllerAddButtonDidTapped(_ viewController: TabBarViewController) {
        mainTabBarController?.showSelectDebtOverlay(oweThemHandler: { [weak self] in
            self?.showCreateDebt(oweMe: false)
        }, oweMeHandler: { [weak self] in
            self?.showCreateDebt(oweMe: true)
        })
    }
    
    // MARK: - Setting Protocol delegate
    
    func settingsViewController(_ viewController: SettingsViewController, didChangeCurrency currency: String?) {
        updateMainCurrencyInfo()
        tableView.reloadData()
    }
    
    // MARK: - CreateDebtViewControllerDelegate
    
    func createDebtViewController(_ controller: CreateDebtViewContoller, didCreateDebtWithId id: NSManagedObjectID) {
        if (controller.isMyDebt && (self.debtType == .toMe)) || (!controller.isMyDebt && (self.debtType == .myDebt)) {
            mainTabBarController?.makeFocusPocus(createDebt: controller)
        } else {
            navigationController?.popToViewController(self, animated: true)
        }
    }
    
    func createDebtViewController(_ controller: CreateDebtViewContoller, didUpdateDebtWithId id: NSManagedObjectID) {
        navigationController?.popToViewController(self, animated: true)
    }
    
    // MARK: - CloseDebtViewControllerDelegate
    
    func closeDebtViewController(_ controller: CloseDebtViewController, didCloseDebtWithId id: NSManagedObjectID) {
        navigationController?.popToViewController(self, animated: true)
    }
    
    // MARK: - DebtInfoViewControllerDelegate
    
    func debtInfoViewController(_ debtInfoViewController: DebtInfoViewController, didCloseDebtWithId id: NSManagedObjectID) {
        navigationController?.popToViewController(self, animated: true)
    }
    
    func debtInfoViewController(_ debtInfoViewController: DebtInfoViewController, didUpdateDebtWithId id: NSManagedObjectID) {}
    
    func debtInfoViewController(_ debtInfoViewController: DebtInfoViewController, didDeleteDebtWithId id: NSManagedObjectID) {
        navigationController?.popToViewController(self, animated: true)
    }
    
    // MARK: - Other
    
    private func reloadDebtHistoryIcon() {
        var shouldShow = false
        let fetchRequest = NSFetchRequest<Debt>(entityName: "Debt")
        fetchRequest.predicate = NSPredicate(format: "isClosed = YES")
        shouldShow = ((try? context.count(for: fetchRequest)) ?? 0) > 0
        
        if shouldShow {
            let leftButtonItem = UIBarButtonItem(image: ImageAsset.debtHistory, style: .done, target: self, action: #selector(historyButtonTapped))
            self.navigationItem.leftBarButtonItem = leftButtonItem
        } else {
            self.navigationItem.leftBarButtonItem = nil
        }
    }
    
    // MARK: - Routing
    
    func showCreateDebt(oweMe: Bool) {
        if let viewController = UIStoryboard(name: "Main", bundle: nil).instantiateViewController(withIdentifier: "AddDebtVC") as? CreateDebtViewContoller {
            viewController.context = context
            viewController.isMyDebt = !oweMe
            viewController.screenMode = .create
            viewController.delegate = self
            navigationController?.pushViewController(viewController, animated: true)
        }
    }
}
