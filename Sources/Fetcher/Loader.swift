//
//  Loader.swift
//  
//
//  Created by Eduard Shugar on 10.04.2020.
//

import UIKit

public protocol FetcherLoader: UIView {
    var activity: UIView { get set }
    var background: UIView { get set }
    
    func start()
    func stop()
}

extension Fetcher {
    public enum Loader {
        case `default`
        
        public var loader: FetcherLoader {
            switch self {
            case .default:
                let activity = UIActivityIndicatorView()
                activity.startAnimating()
                return Fetcher.DefaultLoader(frame: .zero, activity: activity, background: UIVisualEffectView(effect: UIBlurEffect(style: .dark)))
            }
        }
    }
}

extension Fetcher {
    open class DefaultLoader: UIView, FetcherLoader {
        
        public var activity: UIView
        public var background: UIView
        
        init(frame: CGRect, activity: UIView, background: UIView) {
            self.activity = activity
            self.background = background
            super.init(frame: frame)
            setup()
            start()
        }
        
        private func setup() {
            backgroundColor = .clear
            background.translatesAutoresizingMaskIntoConstraints = false
            addSubview(background)
            background.box(in: self)
            
            activity.translatesAutoresizingMaskIntoConstraints = false
            addSubview(activity)
            activity.heightAnchor.constraint(equalToConstant: 50).isActive = true
            activity.widthAnchor.constraint(equalToConstant: 50).isActive = true
            activity.centerXAnchor.constraint(equalTo: centerXAnchor).isActive = true
            activity.centerYAnchor.constraint(equalTo: centerYAnchor).isActive = true
            activity.transform = CGAffineTransform(scaleX: 0.5, y: 0.5)
            activity.alpha = 0
        }
        
        required public init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
        
        public func start() {
            UIView.animate(withDuration: 0.25, delay: 0, usingSpringWithDamping: 0.5, initialSpringVelocity: 0.5, options: [.allowUserInteraction, .preferredFramesPerSecond60], animations: { [weak self] in
                self?.activity.transform = .identity
                self?.activity.alpha = 1
            }, completion: nil)
        }
        
        public func stop() {
            UIView.animate(withDuration: 0.25, delay: 0, usingSpringWithDamping: 0.5, initialSpringVelocity: 0.5, options: [.allowUserInteraction, .preferredFramesPerSecond60], animations: { [weak self] in
                self?.activity.transform = CGAffineTransform(scaleX: 0.5, y: 0.5)
                self?.activity.alpha = 0
            }, completion: nil)
        }
        
    }
}
