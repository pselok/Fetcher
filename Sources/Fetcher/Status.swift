//
//  File.swift
//  
//
//  Created by Eduard Shugar on 25.05.2021.
//

import Foundation

extension Fetcher {
    public enum Status {
        case missing
        case fetched
        case fetching(worker: Workstation.Worker)
    }
}
