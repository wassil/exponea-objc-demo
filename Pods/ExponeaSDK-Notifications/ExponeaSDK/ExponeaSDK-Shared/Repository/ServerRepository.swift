//
//  ConnectionManager.swift
//  ExponeaSDK
//
//  Created by Ricardo Tokashiki on 04/04/2018.
//  Copyright © 2018 Exponea. All rights reserved.
//

import Foundation

/// The Server Repository class is responsible to manage all the requests for the Exponea API.
final class ServerRepository {

    public internal(set) var configuration: Configuration
    internal let session = URLSession(configuration: .default)

    // Initialize the configuration for all HTTP requests
    init(configuration: Configuration) {
        self.configuration = configuration
    }

    // Gets and cancels all tasks
    func cancelRequests() {
        session.getAllTasks { (tasks) in
            for task in tasks {
                task.cancel()
            }
        }
    }
}
