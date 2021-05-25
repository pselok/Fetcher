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
        let work: Work
        let format: Storage.Format
        let configuration: Storage.Configuration
        let item: Core.Database.Item?
        let remoteURL: URL
        var progress: Network.Progress {
            didSet {
                switch progress {
                case .failed(let error):
                    leech(.failure(.error(error)))
                default:
                    leech(.success(Fetcher.Output(progress: progress, recognizer: recognizer)))
                }
            }
        }
        var recognizer: UUID
        var leech: ((Result<Fetcher.Output, Fetcher.Failure>) -> Void)
        
        public static func ==(lhs: Worker, rhs: Worker) -> Bool {
            return lhs.remoteURL == rhs.remoteURL && lhs.work == rhs.work && lhs.configuration == rhs.configuration && lhs.recognizer == rhs.recognizer
        }
        
        // MARK: - Init
        init(work: Work, format: Storage.Format, configuration: Storage.Configuration, remoteURL: URL, progress: Network.Progress, recognizer: UUID, item: Core.Database.Item?, leech: @escaping ((Result<Fetcher.Output, Fetcher.Failure>) -> Void)) {
            self.work = work
            self.format = format
            self.configuration = configuration
            self.remoteURL = remoteURL
            self.progress = progress
            self.recognizer = recognizer
            self.item = item
            self.leech = leech
        }
    }
}
