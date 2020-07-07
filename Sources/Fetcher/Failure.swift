//
//  Failure.swift
//  
//
//  Created by Eduard Shugar on 07.07.2020.
//

import Foundation

extension Fetcher {
    public enum Failure: Error {
        case data
        case error(Error)
        case explicit(string: String)
        case outsider
        case cancelled
        
        public var description: String {
            switch self {
            case .error(let error):
                return error.localizedDescription
            case .explicit(let error):
                return error
            case .data:
                return "Data error"
            case .outsider:
                return "Wrong source"
            case .cancelled:
                return "Cancelled"
            }
        }
    }
}
