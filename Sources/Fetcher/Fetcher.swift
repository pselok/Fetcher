//
//  Fetcher.swift
//  
//
//  Created by Eduard Shugar on 10.04.2020.
//

import UIKit
import NetworkKit
import InterfaceKit
import StorageKit

internal let queue = DispatchQueue(label: "com.fetcher.queue", qos: .userInteractive, attributes: .concurrent)
internal let main = DispatchQueue.main

fileprivate protocol Resource {
    var recognizer: UUID { get }
    var provider: Fetcher.Provider { get }
}

extension Fetcher {
    public struct Image: Resource {
        public let image: UIImage
        public let recognizer: UUID
        public let provider: Provider
    }
    public enum Provider: Equatable {
        case storage(provider: Storage.Output.Provider)
        case network
    }
}

public struct Fetcher {
    private init() {}
    
    static func fetch(image from: URL,
                    configuration: Storage.Configuration,
                    recognizer: UUID,
                    progress: @escaping (Result<Network.Progress, Fetcher.Failure>) -> Void,
                    completion: @escaping (Result<Image, Fetcher.Failure>) -> Void) {
        Storage.get(file: .image, name: from.absoluteString, configuration: configuration) { (result) in
            queue.async {
                switch result {
                case .success(let output):
                    guard let image = output.file.image else {
                        completion(.failure(.explicit(string: "Failed to convert data to UIImage")))
                        return
                    }
                    completion(.success(Image(image: image, recognizer: recognizer, provider: .storage(provider: output.provider))))
                case .failure:
                    Workstation.shared.fetch(file: from, format: .image, configuration: configuration, recognizer: recognizer) { (result) in
                        queue.async {
                            switch result {
                            case .success(let result):
                                switch result.progress {
                                case .finished(let output):
                                    guard let image = UIImage.decoded(data: output.data) else {
                                        completion(.failure(.explicit(string: "Failed to convert data to UIImage")))
                                        return
                                    }
                                    completion(.success(Image(image: image, recognizer: result.recognizer, provider: .network)))
                                case .cancelled:
                                    completion(.failure(.cancelled))
                                case .failed(let error):
                                    completion(.failure(.error(error)))
                                default:
                                    main.async {
                                        progress(.success(result.progress))
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
                  progress: @escaping (Result<Network.Progress, Fetcher.Failure>) -> Void = {_ in},
                  completion: @escaping (Result<UIImage, Fetcher.Failure>) -> Void = {_ in}) {
        main.async {
            Fetcher.Wrapper(source: self).fetch(image: from, options: options, progress: progress, completion: completion)
        }
    }
}

extension Fetcher.Wrapper where Source: UIImageView {
    public func fetch(image from: URL,
                      options: Fetcher.Options,
                      progress: @escaping (Result<Network.Progress, Fetcher.Failure>) -> Void = {_ in},
                      completion: @escaping (Result<UIImage, Fetcher.Failure>) -> Void = {_ in}) {
        let options = Fetcher.Option.Parsed(options: options)
        let configuration = options.persist ? Settings.Storage.configuration : .memory
        source.image = options.placeholder
        source.loader = options.loader
        Fetcher.fetch(image: from, configuration: configuration, recognizer: recognizer, progress: progress) { [weak source] (result) in
            main.async {
                switch result {
                case .success(let resource):
                    guard resource.recognizer == self.recognizer else {
                        completion(.failure(.outsider))
                        return
                    }
                    var image = resource.image
                    options.modifiers.forEach {
                        image = $0.modify(image: image)
                    }
                    guard let source = source else {
                        completion(.success(image))
                        return
                    }
                    source.loader?.stop(completion: { _ in
                        source.loader = nil
                    })
                    guard let transition = options.transition, resource.provider != .storage(provider: .memory) else {
                        source.image = image
                        completion(.success(image))
                        return
                    }
                    UIView.transition(with: source, duration: transition.duration, options: [transition.options], animations: {
                        transition.animations?(source, image)
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

private var recognizerKey: Void?
private var indicatorKey: Void?
extension Fetcher {
    public struct Wrapper<Source> {
        public let source: Source
        public var recognizer: UUID {
            get {
                guard let box: Box<UUID> = getAssociatedObject(source, &recognizerKey) else {
                    return setRetainedAssociatedObject(source, &recognizerKey, Box(UUID())).value
                }
                return box.value
            }
        }
        public init(source: Source) {
            self.source = source
        }
        fileprivate class Box<T> {
            var value: T
            init(_ value: T) {
                self.value = value
            }
        }
    }
}

extension UIImageView {
    public var loader: Loader? {
        get {
            let box: Fetcher.Wrapper<UIImageView>.Box<Loader>? = getAssociatedObject(self, &indicatorKey)
            return box?.value
        } set {
            loader?.removeFromSuperview()
//            print("old loader: \(loader)")
            if let loader = newValue {
//                print("new loader: \(loader)")
                loader.translatesAutoresizingMaskIntoConstraints = false
                if let superview = superview {
                    superview.addSubview(loader)
                } else {
                    addSubview(loader)
                }
                loader.stretch(on: self)
                loader.play()
            }
            setRetainedAssociatedObject(self, &indicatorKey, newValue.map(Fetcher.Wrapper<UIImageView>.Box.init))
        }
    }
}

fileprivate func getAssociatedObject<T>(_ object: Any, _ key: UnsafeRawPointer) -> T? {
    return objc_getAssociatedObject(object, key) as? T
}

@discardableResult
fileprivate func setRetainedAssociatedObject<T>(_ object: Any, _ key: UnsafeRawPointer, _ value: T) -> T {
    objc_setAssociatedObject(object, key, value, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    return value
}
