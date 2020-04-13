//
//  Worker.swift
//  
//
//  Created by Eduard Shugar on 05.04.2020.
//

import Foundation
import StorageKit
import NetworkKit

public enum Work {
    case download, upload
}

public final class Worker {
    let work: Work
    let format: Storage.Format
    let configuration: Storage.Configuration
    let remoteURL: URL
    var progress: Network.Progress {
        didSet {
            switch progress {
            case .failed(let error):
                progressBlock(.failure(.error(error)))
            default:
                progressBlock(.success(progress))
            }
        }
    }
    var progressBlock: ((Result<Network.Progress, NetworkError>) -> Void)
    
    // MARK: - Init
    
    init(work: Work, format: Storage.Format, configuration: Storage.Configuration, remoteURL: URL, progress: Network.Progress, progressBlock: @escaping ((Result<Network.Progress, NetworkError>) -> Void)) {
        self.work = work
        self.format = format
        self.configuration = configuration
        self.remoteURL = remoteURL
        self.progress = progress
        self.progressBlock = progressBlock
    }
}
