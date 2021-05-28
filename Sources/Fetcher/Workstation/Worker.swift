//
//  Worker.swift
//  
//
//  Created by Eduard Shugar on 05.04.2020.
//

import CoreKit
import Foundation
import StorageKit
import NetworkKit

extension Workstation.Worker {
    public enum Work: Equatable {
        case download(file: URL, session: Workstation.Session)
        case upload(data: Data, url: URL, session: Workstation.Session)
        
        public var url: URL {
            switch self {
            case .download(let url, _):
                return url
            case .upload(_, let url, _):
                return url
            }
        }
    }
}

extension Workstation {
    public class Worker: Equatable {
        public let work: Work
        public let file: Storage.File
        public let configuration: Storage.Configuration
        public let item: Core.Database.Item?
        public let remoteURL: URL
        public var progress: Fetcher.Progress {
            didSet {
                switch progress {
                case .failed(let error):
                    leech(.failure(error))
                default:
                    leech(.success(Fetcher.Output(progress: progress, recognizer: recognizer)))
                }
            }
        }
        public let recognizer: UUID
        public var leech: ((Result<Fetcher.Output, Fetcher.Failure>) -> Void)
        public var created: Date
        
        public static func ==(lhs: Worker, rhs: Worker) -> Bool {
            return lhs.remoteURL == rhs.remoteURL && lhs.work == rhs.work && lhs.configuration == rhs.configuration && lhs.recognizer == rhs.recognizer
        }
        
        // MARK: - Init
        init(work: Work, file: Storage.File, configuration: Storage.Configuration, remoteURL: URL, progress: Fetcher.Progress, recognizer: UUID, item: Core.Database.Item?, leech: @escaping ((Result<Fetcher.Output, Fetcher.Failure>) -> Void)) {
            self.work = work
            self.file = file
            self.configuration = configuration
            self.remoteURL = remoteURL
            self.progress = progress
            self.recognizer = recognizer
            self.item = item
            self.leech = leech
            self.created = Date()
        }
    }
}
