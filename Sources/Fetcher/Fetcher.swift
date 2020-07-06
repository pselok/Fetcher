//
//  Fetcher.swift
//  
//
//  Created by Eduard Shugar on 10.04.2020.
//

import UIKit
import NetworkKit
import StorageKit

fileprivate protocol Resource {
    var provider: Fetcher.Provider { get }
}

extension Fetcher {
    public struct Image: Resource {
        public let image: UIImage
        public let provider: Provider
    }
    public enum Provider: Equatable {
        case storage(provider: Storage.Output.Provider)
        case network
    }
}

public struct Fetcher {
    private init() {}
    private static let queue = DispatchQueue(label: "com.fetcher.queue", qos: .userInteractive, attributes: .concurrent)
    
    static func get(image from: URL,
                    configuration: Storage.Configuration,
                    progress: @escaping (Result<Network.Progress, Network.Failure>) -> Void,
                    completion: @escaping (Result<Image, Network.Failure>) -> Void) {
        Storage.get(file: .image, name: from.absoluteString, configuration: configuration) { (result) in
            queue.async {
                switch result {
                case .success(let output):
                    guard let image = output.file.image else {
                        completion(.failure(.explicit(string: "Failed to convert data to UIImage")))
                        return
                    }
                    completion(.success(Image(image: image, provider: .storage(provider: output.provider))))
                case .failure:
                    Workstation.shared.download(from: from, format: .image, configuration: configuration) { (result) in
                        queue.async {
                            switch result {
                            case .success(let currentProgress):
                                switch currentProgress {
                                case .finished(let output):
                                    guard let image = UIImage.decoded(data: output.data) else {
                                        completion(.failure(.explicit(string: "Failed to convert data to UIImage")))
                                        return
                                    }
                                    completion(.success(Image(image: image, provider: .network)))
                                default:
                                    DispatchQueue.main.async {
                                        progress(.success(currentProgress))
                                    }
                                }
                            case .failure(let error):
                                completion(.failure(error))
                            }
                        }
                    }
                }
            }
        }
    }
}

extension UIImageView {
    public func fetch(image from: URL,
                      options: Fetcher.Options = [.transition(.fade(duration: 0.5))],
                      progress: @escaping (Result<Network.Progress, Network.Failure>) -> Void = {_ in},
                      completion: @escaping (Result<UIImage, Network.Failure>) -> Void = {_ in}) {
        let options = Fetcher.Option.Parsed(options: options)
        let configuration = options.persist ? Settings.Storage.configuration : .memory
        self.image = options.placeholder
        if let loader = options.loader {
            loader.translatesAutoresizingMaskIntoConstraints = false
            if let superview = superview {
                superview.addSubview(loader)
            } else {
                addSubview(loader)
            }
            loader.box(in: self)
            loader.play()
        }
        Fetcher.get(image: from, configuration: configuration, progress: progress) { [weak self] (result) in
            DispatchQueue.main.async {
                switch result {
                case .success(let resource):
                    var image = resource.image
                    options.modifiers.forEach {
                        image = $0.modify(image: image)
                    }
                    guard let strongSelf = self else {
                        completion(.success(image))
                        return
                    }
                    options.loader?.stop(completion: {_ in
                        options.loader?.removeFromSuperview()
                    })
                    guard let transition = options.transition, resource.provider != .storage(provider: .memory) else {
                        strongSelf.image = image
                        completion(.success(image))
                        return
                    }
                    UIView.transition(with: strongSelf, duration: transition.duration, options: [transition.options], animations: {
                        transition.animations?(strongSelf, image)
                    }, completion: { finished in
                        transition.completion?(finished)
                    })
                    completion(.success(image))
                case .failure(let error):
                    completion(.failure(error))
                }
            }
        }
    }
}
