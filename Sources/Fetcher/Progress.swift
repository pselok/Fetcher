//
//  File.swift
//  
//
//  Created by Eduard Shugar on 25.05.2021.
//

import Foundation
import StorageKit

extension Fetcher {
    public enum Progress {
        case loading
        case downloading(progress: Double)
        case uploading(progress: Double)
        case paused
        case cancelled
        case failed(error: Fetcher.Failure)
        case finished(file: Storable)
    }
}

extension Fetcher.Progress {
    public struct Output {
        public let url: URL
        
        public init(url: URL) {
            self.url = url
        }
    }
}
