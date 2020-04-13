//
//  Options.swift
//  
//
//  Created by Eduard Shugar on 13.04.2020.
//

import Foundation

extension Fetcher {
    public struct Options: OptionSet, Hashable {

        public let rawValue: Int
        
        /// Fetch value only from storage.
        public static let cache = Options(rawValue: 1 << 0)
        /// Fetch value only from network.
        public static let network = Options(rawValue: 1 << 1)
    
        public init(rawValue: Int) {
            self.rawValue = rawValue
        }
    }
}
