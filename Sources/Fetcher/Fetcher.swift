//
//  Fetcher.swift
//  
//
//  Created by Eduard Shugar on 10.04.2020.
//

import UIKit
import NetworkKit
import StorageKit

public struct Fetcher {
    private init() {}
    
    static func get(image from: URL,
                    configuration: Storage.Configuration,
                    progress: @escaping (Result<Network.Progress, Network.Failure>) -> Void,
                    completion: @escaping (Result<UIImage, Network.Failure>) -> Void) {
        DispatchQueue.global(qos: .userInteractive).async {
            if Storage.Disk.fileExists(with: from.absoluteString, format: .image, configuration: configuration) {
                Storage.Disk.get(file: .image, name: from.absoluteString, configuration: configuration) { (result) in
                    switch result {
                    case .success(let file):
                        guard let image = UIImage(data: file.data) else {
                            completion(.failure(.explicit(string: "Failed to convert data to UIImage")))
                            return
                        }
                        completion(.success(image))
                    case .failure(let error):
                        completion(.failure(.explicit(string: error.description)))
                    }
                }
            } else {
                Workstation.shared.download(from: from, format: .image, configuration: configuration) { (result) in
                    switch result {
                    case .success(let currentProgress):
                        switch currentProgress {
                        case .finished(let output):
                            guard let image = UIImage(data: output.data) else {
                                completion(.failure(.explicit(string: "Failed to convert data to UIImage")))
                                return
                            }
                            completion(.success(image))
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

extension UIImageView {
    public func fetch(image from: URL,
                      options: Fetcher.Options = [],
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
            loader.start(animated: true)
        }
        Fetcher.get(image: from, configuration: configuration, progress: progress) { [weak self] (result) in
            DispatchQueue.main.async {
                switch result {
                case .success(var image):
                    options.modifiers.forEach {
                        image = $0.modify(image: image)
                    }
                    guard let strongSelf = self else {
                        completion(.success(image))
                        return
                    }
                    options.loader?.stop(animated: true, completion: {_ in
                        options.loader?.removeFromSuperview()
                    })
                    guard let transition = options.transition else {
                        strongSelf.image = image
                        completion(.success(image))
                        return
                    }
                    UIView.transition(with: strongSelf, duration: transition.duration, options: [transition.options, .allowUserInteraction, .preferredFramesPerSecond60], animations: {
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
