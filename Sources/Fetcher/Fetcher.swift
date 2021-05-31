//
//  Fetcher.swift
//  
//
//  Created by Eduard Shugar on 10.04.2020.
//

import UIKit
import CoreKit
import StorageKit
import NetworkKit
import InterfaceKit

internal let iqueue = DispatchQueue(label: "com.fetcher.images.queue", qos: .userInteractive, attributes: .concurrent)
internal let fqueue = DispatchQueue(label: "com.fetcher.files.queue", qos: .userInteractive, attributes: .concurrent)
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
        
        public var description: String {
            switch self {
            case .network: return "NETWORK"
            case .storage(let provider):
                switch provider {
                case .disk  : return "DISK"
                case .memory: return "MEMORY"
                }
            }
        }
    }
}

public struct Fetcher {
    private init() {}
    internal static func fetch(image from: URL,
                               configuration: Storage.Configuration,
                               recognizer: UUID,
                               options: Fetcher.Option.Parsed,
                               progress: @escaping (Result<Fetcher.Progress, Fetcher.Failure>) -> Void,
                               completion: @escaping (Result<Image, Fetcher.Failure>) -> Void) {
        progress(.success(.loading))
        Storage.get(file: .image(named: from.absoluteString), configuration: configuration) { (result) in
            iqueue.async {
                switch result {
                case .success(let output):
                    guard let image = UIImage(contentsOfFile: output.file.url.path)?.decoded else {
                        completion(.failure(.explicit(string: "STORAGE Failed to convert data to UIImage")))
                        return
                    }
                    completion(.success(Image(image: image, recognizer: recognizer, provider: .storage(provider: output.provider))))
                    return
                case .failure:
                    Workstation.shared.perform(work: .download(file: from, session: .foreground), file: .image(named: from.absoluteString), configuration: configuration, recognizer: recognizer) { (result) in
                        iqueue.async {
                            switch result {
                            case .success(let result):
                                switch result.progress {
                                case .finished(let output):
                                    guard let image = UIImage(contentsOfFile: output.url.path)?.decoded else {
                                        completion(.failure(.explicit(string: "NETWORK Failed to convert data to UIImage")))
                                        return
                                    }
                                    completion(.success(Image(image: image, recognizer: result.recognizer, provider: .network)))
                                    return
                                case .cancelled:
                                    completion(.failure(.cancelled))
                                    return
                                case .failed(let error):
                                    completion(.failure(.error(error)))
                                    return
                                default:
                                    main.async {
                                        progress(.success(result.progress))
                                    }
                                }
                            case .failure(let error):
                                completion(.failure(error))
                                return
                            }
                        }
                    }
                }
            }
        }
    }
    public static func fetch(file: StorageKit.Storage.File,
                             progress: @escaping (Result<Fetcher.Progress, Fetcher.Failure>) -> Void) {
        progress(.success(.loading))
        Storage.get(file: file) { result in
            fqueue.async {
                switch result {
                case .success(let output):
                    main.async {
                        progress(.success(.finished(file: output.file)))
                    }
                case .failure:
                    switch file {
                    case .audio(let id):
                        Network.get(object: Core.Audio.self, with: Network.Smotrim.audio(id: id)) { (result) in
                            fqueue.async {
                                switch result {
                                case .success(let audio):
                                    guard let source = audio.data.sources?.mp3, let url = URL(string: source) else { return }
                                    log(event: "Fetch audio: \(url.absoluteString)", source: .fetcher)
                                    Workstation.shared.perform(work: .download(file: url, session: .background),
                                                               file: .audio(id: id),
                                                               configuration: .weekly,
                                                               recognizer: UUID(),
                                                               representation: audio.data.item) { result in
                                        switch result {
                                        case .success(let output):
                                            main.async {
                                                progress(.success(output.progress))
                                            }
                                        case .failure(let failure):
                                            main.async {
                                                progress(.failure(failure))
                                            }
                                        }
                                    }
                                case .failure(let failure):
                                    main.async {
                                        progress(.failure(.error(failure)))
                                    }
                                }
                            }
                        }
                    case .video(let id):
                        Network.get(object: Core.VideoItem.self, with: Network.Smotrim.video(id: id)) { (representation) in
                            Network.get(object: Core.Video.self, with: Network.Shared.video(id: id)) { (result) in
                                fqueue.async {
                                    switch result {
                                    case .success(let video):
                                        guard let best = video.data.playlist.medialist.first?.sources?.http?.keys.sorted(by: {Int($0) ?? 0 > Int($1) ?? 0}).first,
                                              let quality = video.data.playlist.medialist.first?.sources?.http?[best],
                                              let url = URL(string: quality) else { return }
                                        log(event: "Fetch video: \(url.absoluteString)", source: .fetcher)
                                        Workstation.shared.perform(work: .download(file: url, session: .background),
                                                                   file: .video(id: id),
                                                                   configuration: .weekly,
                                                                   recognizer: UUID(),
                                                                   representation: try? representation.get().data.item ?? video.data.playlist.medialist.first?.item) { result in
                                            switch result {
                                            case .success(let output):
                                                main.async {
                                                    progress(.success(output.progress))
                                                }
                                            case .failure(let failure):
                                                main.async {
                                                    progress(.failure(failure))
                                                }
                                            }
                                        }
                                    case .failure(let failure):
                                        main.async {
                                            progress(.failure(.error(failure)))
                                        }
                                    }
                                }
                            }
                        }
                    default:
                        progress(.failure(.explicit(string: "Unfetchable")))
                    }
                }
            }
        }
    }
}

extension UIImageView {
    public func fetch(image from: URL,
                  options: Fetcher.Options = [.transition(.fade(duration: 0.5))],
                  progress: @escaping (Result<Fetcher.Progress, Fetcher.Failure>) -> Void = {_ in},
                  completion: @escaping (Result<UIImage, Fetcher.Failure>) -> Void = {_ in}) {
        main.async {
            Fetcher.Wrapper(source: self).fetch(image: from, options: options, progress: progress, completion: completion)
        }
    }
}

extension Fetcher.Wrapper where Source: UIImageView {
    public func fetch(image from: URL,
                      options: Fetcher.Options,
                      progress: @escaping (Result<Fetcher.Progress, Fetcher.Failure>) -> Void = {_ in},
                      completion: @escaping (Result<UIImage, Fetcher.Failure>) -> Void = {_ in}) {
        log(event: "Fetch image: \(from.absoluteString)", source: .fetcher)
        var _self = self
        _self.recognizer = UUID()
        let options = Fetcher.Option.Parsed(options: options)
        let configuration = options.persist ? Settings.Storage.configuration : .memory
        source.image = options.holdSource ? source.image : options.placeholder ?? source.image
        source.loader = options.loader
        Fetcher.fetch(image: from, configuration: configuration, recognizer: _self.recognizer, options: options, progress: progress) { [weak source] (result) in
            main.async {
                source?.loader?.stop(completion: { _ in
                    source?.loader = nil
                })
                switch result {
                case .success(let resource):
                    log(event: "Fetched image: \(from.absoluteString), resource: \(resource.provider.description)", source: .fetcher)
                    Workstation.shared.fetched(recognizer: resource.recognizer)
                    guard resource.recognizer == _self.recognizer else {
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
                    guard let transition = options.transition else {
                        source.image = image
                        completion(.success(image))
                        return
                    }
                    let animate: Bool = {
                        if transition.force {
                            return true
                        } else if resource.provider != .storage(provider: .memory) {
                            return true
                        } else {
                            return false
                        }
                    }()
                    switch animate {
                    case true:
                        UIView.transition(with: source, duration: transition.duration, options: [transition.options], animations: {
                            transition.animations?(source, image)
                        }, completion: { finished in
                            transition.completion?(finished)
                        })
                    case false:
                        source.image = image
                    }
                    completion(.success(image))
                    return
                case .failure(let error):
                    log(event: ("Fetcher image error: \(error), resource: \(from.absoluteString)"), source: .fetcher)
                    completion(.failure(error))
                    return
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
            } set {
                setRetainedAssociatedObject(source, &recognizerKey, Box(UUID()))
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
    internal var loader: Loader? {
        get {
            let box: Fetcher.Wrapper<UIImageView>.Box<Loader>? = getAssociatedObject(self, &indicatorKey)
            return box?.value
        } set {
            loader?.removeFromSuperview()
            if let loader = newValue {
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
