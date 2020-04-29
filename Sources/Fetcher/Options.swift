//
//  Options.swift
//  
//
//  Created by Eduard Shugar on 13.04.2020.
//

import UIKit
import InterfaceKit

extension Fetcher {
    public typealias Options = [Option]
    public enum Option {
        case placeholder(UIImage)
        case transition(Fetcher.Transition)
        case loader(Loader)
        case persist
        case modifier(Modifier)
        
        internal struct Parsed {
            var placeholder: UIImage?
            var transition: Fetcher.Transition?
            var loader: Loader?
            var persist: Bool = false
            var modifiers: [Modifier] = []
            
            init(options: Options) {
                for option in options {
                    switch option {
                    case .placeholder(let placeholder): self.placeholder = placeholder
                    case .transition(let transition)  : self.transition = transition
                    case .loader(let loader)          : self.loader = loader
                    case .persist                     : self.persist = true
                    case .modifier(let modifier)      : self.modifiers.append(modifier)
                    }
                }
            }
        }
    }
}
