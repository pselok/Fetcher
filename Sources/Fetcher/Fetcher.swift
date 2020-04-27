//
//  Fetcher.swift
//  
//
//  Created by Eduard Shugar on 10.04.2020.
//

import UIKit
import NetworkKit
import StorageKit
import InterfaceKit

public struct Fetcher {
    private init() {}
    
    static func get(image from: URL,
                    configuration: Storage.Configuration,
                    progress: @escaping (Result<Network.Progress, NetworkError>) -> Void,
                    completion: @escaping (Result<UIImage, NetworkError>) -> Void) {
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
                      placeholder: UIImage = .image(with: #colorLiteral(red: 0.09411764706, green: 0.1450980392, blue: 0.231372549, alpha: 1)),
                      transition: Fetcher.Transition = .fade(duration: 0.5),
                      loader: Loader? = nil,
                      persist: Bool = false,
                      progress: @escaping (Result<Network.Progress, NetworkError>) -> Void = {_ in},
                      completion: @escaping (Result<UIImage, NetworkError>) -> Void = {_ in}) {
        self.image = placeholder
        if let loader = loader {
            loader.translatesAutoresizingMaskIntoConstraints = false
            if let superview = superview {
                superview.addSubview(loader)
            } else {
                addSubview(loader)
            }
            loader.box(in: self)
            loader.start(animated: true)
        }
        let configuration = persist ? Settings.Storage.configuration : .memory
        Fetcher.get(image: from, configuration: configuration, progress: progress) { [weak self] (result) in
            DispatchQueue.main.async {
                switch result {
                case .success(let image):
                    guard let strongSelf = self else {
                        completion(.success(image))
                        return
                    }
                    loader?.stop(animated: true)
                    UIView.transition(with: strongSelf, duration: transition.duration, options: [transition.options, .allowUserInteraction, .preferredFramesPerSecond60], animations: {
                        transition.animations?(strongSelf, image)
                    }, completion: { finished in
                        transition.completion?(finished)
                        completion(.success(image))
                    })
                case .failure(let error):
                    completion(.failure(error))
                }
            }
        }
    }
}
