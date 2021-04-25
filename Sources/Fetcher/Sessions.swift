//
//  File.swift
//  
//
//  Created by Eduard Shugar on 25.04.2021.
//

import NetworkKit
import Foundation

extension Workstation {
    public struct Sessions {
        public let foreground: URLSession
        public let background: URLSession
        
        public var all: [URLSession] {
            return [foreground, background]
        }
        
        public func session(for session: Session) -> URLSession {
            switch session {
            case .foreground: return foreground
            case .background: return background
            }
        }
    }
    public enum Session {
        case foreground
        case background
    }
}

