//
//  Transition.swift
//  
//
//  Created by Eduard Shugar on 10.04.2020.
//

import Foundation

public protocol FetcherTransition {
    
}

extension Fetcher {
    public enum Transition: FetcherTransition {
        case fade(duration: TimeInterval = 0.5)
    }
}
