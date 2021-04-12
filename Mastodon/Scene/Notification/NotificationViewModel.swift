//
//  NotificationViewModel.swift
//  Mastodon
//
//  Created by sxiaojian on 2021/4/12.
//

import Foundation
import Combine
import UIKit
import CoreData
import CoreDataStack
import GameplayKit

final class NotificationViewModel: NSObject  {
    
    var disposeBag = Set<AnyCancellable>()
    
    // input
    let context: AppContext
    weak var coordinator: SceneCoordinator!
    weak var tableView: UITableView!
    weak var contentOffsetAdjustableTimelineViewControllerDelegate: ContentOffsetAdjustableTimelineViewControllerDelegate?
    
    
    let activeMastodonAuthenticationBox: CurrentValueSubject<AuthenticationService.MastodonAuthenticationBox?, Never>
    let fetchedResultsController: NSFetchedResultsController<MastodonNotification>!
    let notificationPredicate = CurrentValueSubject<NSPredicate?, Never>(nil)
    let cellFrameCache = NSCache<NSNumber, NSValue>()
    
    let isFetchingLatestNotification = CurrentValueSubject<Bool, Never>(false)
    
    //output
    var diffableDataSource: UITableViewDiffableDataSource<NotificationSection, NotificationItem>!
    // top loader
    private(set) lazy var loadLatestStateMachine: GKStateMachine = {
        // exclude timeline middle fetcher state
        let stateMachine = GKStateMachine(states: [
            LoadLatestState.Initial(viewModel: self),
            LoadLatestState.Loading(viewModel: self),
            LoadLatestState.Fail(viewModel: self),
            LoadLatestState.Idle(viewModel: self),
        ])
        stateMachine.enter(LoadLatestState.Initial.self)
        return stateMachine
    }()
    
    lazy var loadLatestStateMachinePublisher = CurrentValueSubject<LoadLatestState?, Never>(nil)
    
    init(context: AppContext,coordinator: SceneCoordinator) {
        self.coordinator = coordinator
        self.context = context
        self.activeMastodonAuthenticationBox = CurrentValueSubject(context.authenticationService.activeMastodonAuthenticationBox.value)
        self.fetchedResultsController = {
            let fetchRequest = MastodonNotification.sortedFetchRequest
            fetchRequest.returnsObjectsAsFaults = false
            fetchRequest.relationshipKeyPathsForPrefetching = [#keyPath(MastodonNotification.status),#keyPath(MastodonNotification.account)]
            let controller = NSFetchedResultsController(
                fetchRequest: fetchRequest,
                managedObjectContext: context.managedObjectContext,
                sectionNameKeyPath: nil,
                cacheName: nil
            )
            
            return controller
        }()
        
        super.init()
        self.fetchedResultsController.delegate = self
        context.authenticationService.activeMastodonAuthenticationBox
            .assign(to: \.value, on: activeMastodonAuthenticationBox)
            .store(in: &disposeBag)
        
        notificationPredicate
            .compactMap{ $0 }
            .sink { [weak self] predicate in
                guard let self = self else { return }
                self.fetchedResultsController.fetchRequest.predicate = predicate
                do {
                    try self.fetchedResultsController.performFetch()
                } catch {
                    assertionFailure(error.localizedDescription)
                }
            }
            .store(in: &disposeBag)
    }
}
