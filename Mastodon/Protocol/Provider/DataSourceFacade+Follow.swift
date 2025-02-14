//
//  DataSourceFacade+Follow.swift
//  Mastodon
//
//  Created by MainasuK on 2022-1-24.
//

import UIKit
import CoreDataStack
import MastodonCore
import MastodonSDK
import MastodonLocalization

extension DataSourceFacade {
    @MainActor
    static func responseToUserFollowAction(
        dependency: ViewControllerWithDependencies & AuthContextProvider,
        account: Mastodon.Entity.Account
    ) async throws -> Mastodon.Entity.Relationship {
        let authBox = dependency.authContext.mastodonAuthenticationBox
        let relationship = try await dependency.context.apiService.relationship(
            forAccounts: [account], authenticationBox: authBox
        ).value.first
        
        return try await withCheckedThrowingContinuation { continuation in
            Task { @MainActor in
                let performAction = {
                    FeedbackGenerator.shared.generate(.selectionChanged)

                    let response = try await dependency.context.apiService.toggleFollow(
                        account: account,
                        authenticationBox: dependency.authContext.mastodonAuthenticationBox
                    ).value

                    dependency.context.authenticationService.fetchFollowingAndBlockedAsync()
                    

                    NotificationCenter.default.post(name: .relationshipChanged, object: nil, userInfo: [
                        UserInfoKey.relationship: response
                    ])
                    
                    continuation.resume(returning: response)
                }

                if relationship?.following == true {
                    let alert = UIAlertController(
                        title: L10n.Common.Alerts.UnfollowUser.title("@\(account.username)"),
                        message: nil,
                        preferredStyle: .alert
                    )
                    let cancel = UIAlertAction(title: L10n.Common.Alerts.UnfollowUser.cancel, style: .default) { _ in
                        if let relationship {
                            NotificationCenter.default.post(name: .relationshipChanged, object: nil, userInfo: [
                                UserInfoKey.relationship: relationship
                            ])
                            
                            continuation.resume(returning: relationship)
                        } else {
                            continuation.resume(throwing: AppError.unexpected)
                        }
                    }
                    alert.addAction(cancel)
                    let unfollow = UIAlertAction(title: L10n.Common.Alerts.UnfollowUser.unfollow, style: .destructive) { _ in
                        Task {
                            try await performAction()
                        }
                    }
                    alert.addAction(unfollow)
                    dependency.present(alert, animated: true)
                } else {
                    try await performAction()
                }
            }
        }
    }

}

extension DataSourceFacade {
    static func responseToUserFollowRequestAction(
        dependency: NeedsDependency & AuthContextProvider,
        notification: MastodonNotification,
        notificationView: NotificationView,
        query: Mastodon.API.Account.FollowRequestQuery
    ) async throws {
        FeedbackGenerator.shared.generate(.selectionChanged)

        let userID = notification.account.id
        let state: MastodonFollowRequestState = notification.followRequestState
        
        guard state.state == .none else { return }

        switch query {
        case .accept:
            notification.transientFollowRequestState = .init(state: .isAccepting)
        case .reject:
            notification.transientFollowRequestState = .init(state: .isRejecting)
        }

        await notificationView.configure(notification: notification, authenticationBox: dependency.authContext.mastodonAuthenticationBox)

        do {
            let newRelationship = try await dependency.context.apiService.followRequest(
                userID: userID,
                query: query,
                authenticationBox: dependency.authContext.mastodonAuthenticationBox
            ).value

            switch query {
            case .accept:
                notification.transientFollowRequestState = .init(state: .isAccept)
                notification.followRequestState = .init(state: .isAccept)
            case .reject:
                break
            }

            NotificationCenter.default.post(name: .relationshipChanged, object: nil, userInfo: [
                UserInfoKey.relationship: newRelationship
            ])

            await notificationView.configure(notification: notification, authenticationBox: dependency.authContext.mastodonAuthenticationBox)
        } catch {
            // reset state when failure
            notification.transientFollowRequestState = .init(state: .none)
            await notificationView.configure(notification: notification, authenticationBox: dependency.authContext.mastodonAuthenticationBox)

            if let error = error as? Mastodon.API.Error {
                switch error.httpResponseStatus {
                case .notFound:
                    break
                default:
                    let alertController = await UIAlertController(for: error, title: nil, preferredStyle: .alert)
                    let okAction = await UIAlertAction(title: L10n.Common.Controls.Actions.ok, style: .default)
                    await alertController.addAction(okAction)
                    _ = await dependency.coordinator.present(
                        scene: .alertController(alertController: alertController),
                        from: nil,
                        transition: .alertController(animated: true, completion: nil)
                    )
                }
            }
        }
        
    }
}

extension DataSourceFacade {
    static func responseToShowHideReblogAction(
        dependency: NeedsDependency & AuthContextProvider,
        account: Mastodon.Entity.Account
    ) async throws {
        let newRelationship = try await dependency.context.apiService.toggleShowReblogs(
            for: account,
            authenticationBox: dependency.authContext.mastodonAuthenticationBox
        )

        let userInfo = [
            UserInfoKey.relationship: newRelationship,
        ]

        NotificationCenter.default.post(name: .relationshipChanged, object: self, userInfo: userInfo)
    }
}
