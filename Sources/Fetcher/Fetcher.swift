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
    
    static func fetch(image from: URL,
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
                    Workstation.shared.fetch(file: from, format: .image, configuration: configuration) { (result) in
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
        Fetcher.Wrapper(source: self).fetch(image: from, options: options, progress: progress, completion: completion)
    }
}

extension Fetcher.Wrapper where Source: UIImageView {
    public func fetch(image from: URL,
                      options: Fetcher.Options,
                      progress: @escaping (Result<Network.Progress, Network.Failure>) -> Void = {_ in},
                      completion: @escaping (Result<UIImage, Network.Failure>) -> Void = {_ in}) {
        let options = Fetcher.Option.Parsed(options: options)
        let configuration = options.persist ? Settings.Storage.configuration : .memory
        source.image = options.placeholder
        if let loader = options.loader {
            loader.translatesAutoresizingMaskIntoConstraints = false
            if let superview = source.superview {
                superview.addSubview(loader)
            } else {
                source.addSubview(loader)
            }
            loader.box(in: source)
            loader.play()
        }
        print("requested: \(from), recognizer: \(recognizer!)\n")
        Fetcher.fetch(image: from, configuration: configuration, progress: progress) { [weak source] (result) in
            DispatchQueue.main.async {
                switch result {
                case .success(let resource):
                    var image = resource.image
                    options.modifiers.forEach {
                        image = $0.modify(image: image)
                    }
                    guard let strongSelf = source else {
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
                    options.loader?.stop(completion: {_ in
                        options.loader?.removeFromSuperview()
                    })
                    completion(.failure(error))
                }
            }
        }
    }
}

private var recognizerKey: Void?
extension Fetcher {
    public struct Wrapper<Source> {
        public let source: Source
        public private(set) var recognizer: UUID? {
            get {
                let box: Box<UUID>? = getAssociatedObject(source, &recognizerKey)
                return box?.value
            }
            set {
                let box = newValue.map {Box($0)}
                setRetainedAssociatedObject(source, &recognizerKey, box)
            }
        }
        public init(source: Source) {
            self.source = source
            guard recognizer == nil else { return }
            self.recognizer = UUID()
        }
        private class Box<T> {
            var value: T
            init(_ value: T) {
                self.value = value
            }
        }
    }
}

fileprivate func getAssociatedObject<T>(_ object: Any, _ key: UnsafeRawPointer) -> T? {
    return objc_getAssociatedObject(object, key) as? T
}

fileprivate func setRetainedAssociatedObject<T>(_ object: Any, _ key: UnsafeRawPointer, _ value: T) {
    objc_setAssociatedObject(object, key, value, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
}
