//
//  Output.swift
//  
//
//  Created by Eduard Shugar on 07.07.2020.
//

import Foundation
import NetworkKit

extension Fetcher {
    public struct Output {
        public let progress: Network.Progress
        public let recognizer: UUID
    }
}
