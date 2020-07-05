//
//  Transition.swift
//  
//
//  Created by Eduard Shugar on 10.04.2020.
//

import UIKit

public protocol FetcherTransition {
    var duration: TimeInterval { get }
    var options: UIView.AnimationOptions { get }
    var animations: ((UIImageView, UIImage) -> Void)? { get }
    var completion: ((Bool) -> Void)? { get }
}

extension Fetcher {
    public enum Transition: FetcherTransition {
        case fade(duration: TimeInterval = 0.5)
        
        public var duration: TimeInterval {
            switch self {
            case .fade(let duration):
                return duration
            }
        }
        
        public var options: UIView.AnimationOptions {
            switch self {
            case .fade:
                return [.transitionCrossDissolve, .allowUserInteraction, .preferredFramesPerSecond60]
            }
        }
        
        public var animations: ((UIImageView, UIImage) -> Void)? {
            switch self {
            case .fade:
                return { $0.image = $1 }
            }
        }
        
        public var completion: ((Bool) -> Void)? {
            switch self {
            case .fade:
                return nil
            }
        }
    }
}
