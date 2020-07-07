//
//  Worker.swift
//  
//
//  Created by Eduard Shugar on 05.04.2020.
//

import Foundation
import StorageKit
import NetworkKit

extension Workstation.Worker {
    public enum Work: Equatable {
        case download, upload
    }
}

extension Workstation {
    public final class Worker: Equatable {
        let work: Work
        let format: Storage.Format
        let configuration: Storage.Configuration
        let remoteURL: URL
        var progress: Network.Progress {
            didSet {
                switch progress {
                case .failed(let error):
                    leeches.forEach {$0(.failure(.error(error)))}
                default:
                    leeches.forEach {$0(.success(progress))}
                }
            }
        }
        var recognizer: UUID
        var leeches: [((Result<Network.Progress, Network.Failure>) -> Void)]
        
        public func track(progress: @escaping ((Result<Network.Progress, Network.Failure>) -> Void)) {
            leeches.append(progress)
        }
        
        public static func ==(lhs: Worker, rhs: Worker) -> Bool {
            return lhs.remoteURL == rhs.remoteURL && lhs.work == rhs.work && lhs.configuration == rhs.configuration && lhs.recognizer == rhs.recognizer
        }
        
        // MARK: - Init
        init(work: Work, format: Storage.Format, configuration: Storage.Configuration, remoteURL: URL, progress: Network.Progress, recognizer: UUID, leeches: [((Result<Network.Progress, Network.Failure>) -> Void)]) {
            self.work = work
            self.format = format
            self.configuration = configuration
            self.remoteURL = remoteURL
            self.progress = progress
            self.recognizer = recognizer
            self.leeches = leeches
        }
    }
}
