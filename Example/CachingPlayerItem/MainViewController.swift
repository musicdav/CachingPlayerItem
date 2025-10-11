//
//  MainViewController.swift
//  CachingPlayerItem
//
//  Created by Gorjan Shukov on 10.10.25.
//  Copyright © 2025 CocoaPods. All rights reserved.
//

import UIKit

final class MainViewController: UITableViewController {
    private enum Section: Int, CaseIterable {
        case demos
        case actions
    }

    private enum Demo: Int, CaseIterable {
        case singleMedia
        case collection

        var title: String {
            switch self {
            case .singleMedia: 
                return "Single Media File"
            case .collection:  
                return "Media Collection Grid"
            }
        }
    }

    private enum Action: Int, CaseIterable {
        case clearCache

        var title: String {
            switch self {
            case .clearCache: 
                return "Clear Cache"
            }
        }
    }

    private let cellIdentifier = "CellIdentifier"

    override func viewDidLoad() {
        super.viewDidLoad()

        title = "CachingPlayerItem Examples"
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: cellIdentifier)
    }
}

// MARK: - TableViewDataSource

extension MainViewController {
    override func numberOfSections(in tableView: UITableView) -> Int {
        Section.allCases.count
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        guard let section = Section(rawValue: section) else { return 0 }

        switch section {
        case .demos:
            return Demo.allCases.count
        case .actions:
            return Action.allCases.count
        }
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let section = Section(rawValue: indexPath.section) else { fatalError() }

        switch section {
        case .demos:
            let cell = tableView.dequeueReusableCell(withIdentifier: cellIdentifier, for: indexPath)
            cell.textLabel?.text = Demo(rawValue: indexPath.row)?.title
            cell.accessoryType = .disclosureIndicator
            return cell
        case .actions:
            let cell = tableView.dequeueReusableCell(withIdentifier: cellIdentifier, for: indexPath)
            cell.textLabel?.text = Action(rawValue: indexPath.row)?.title
            cell.textLabel?.textColor = .red
            return cell
        }
    }


}

// MARK: - TableViewDelegate

extension MainViewController {
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)

        guard let section = Section(rawValue: indexPath.section) else { fatalError() }

        switch section {
        case .demos:
            guard let demo = Demo(rawValue: indexPath.row) else { fatalError() }

            switch demo {
            case .singleMedia:
                navigationController?.pushViewController(SingleMediaViewController(), animated: true)
            case .collection:
                let layout = UICollectionViewFlowLayout()
                layout.minimumInteritemSpacing = 8
                layout.minimumLineSpacing = 8
                navigationController?.pushViewController(MediaCollectionViewController(collectionViewLayout: layout), animated: true)
            }
        case .actions:
            guard let action = Action(rawValue: indexPath.row) else { fatalError() }

            switch action {
            case .clearCache:
                clearCache()
                let alert = UIAlertController(title: "Cache Cleared", message: "The cache has been successfully cleared.", preferredStyle: .alert)
                alert.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
                present(alert, animated: true, completion: nil)
            }
        }
    }
}

// MARK: - Clear cache

extension MainViewController {
    func clearCache() {
        let cacheURL =  FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        let fileManager = FileManager.default

        let directoryContents = try! FileManager.default.contentsOfDirectory( at: cacheURL, includingPropertiesForKeys: nil, options: [])
        for file in directoryContents {
            try! fileManager.removeItem(at: file)
        }
    }
}
