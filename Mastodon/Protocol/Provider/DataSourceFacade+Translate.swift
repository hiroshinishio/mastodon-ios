//
//  DataSourceFacade+Translate.swift
//  Mastodon
//
//  Created by Marcus Kida on 29.11.22.
//

import UIKit
import MastodonCore
import MastodonSDK

typealias Provider = UIViewController & NeedsDependency & AuthContextProvider

extension DataSourceFacade {
    enum TranslationFailure: Error {
        case emptyOrInvalidResponse
    }
    
    public static func translateStatus(
        provider: Provider,
        status: Mastodon.Entity.Status
    ) async throws -> Mastodon.Entity.Translation? {
        let selectionFeedbackGenerator = await UISelectionFeedbackGenerator()
        await selectionFeedbackGenerator.selectionChanged()

        if let reblog = status.reblog {
            return try await _translateStatus(provider: provider, status: reblog)
        } else {
            return try await _translateStatus(provider: provider, status: status)
        }
    }
}

private extension DataSourceFacade {
    static func _translateStatus(provider: Provider, status: Mastodon.Entity.Status) async throws -> Mastodon.Entity.Translation? {
        do {
            let value = try await provider.context
                .apiService
                .translateStatus(
                    statusID: status.id,
                    authenticationBox: provider.authContext.mastodonAuthenticationBox
                ).value

            if value.content != nil {
                return value
            } else {
                return nil
            }

        } catch {
            throw TranslationFailure.emptyOrInvalidResponse
        }
    }
}
