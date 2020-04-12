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
                         progress: @escaping (Result<Network.Progress, NetworkError>) -> Void,
                         completion: @escaping (Result<UIImage, NetworkError>) -> Void) {
        if Storage.Disk(path: from.absoluteString).exists() {
            Storage.Disk(path: from.absoluteString).get(storable: .image, as: Storage.SKImage.self, qos: .userInteractive) { (result) in
                switch result {
                case .success(let image):
                    completion(.success(image.image))
                case .failure(let error):
                    completion(.failure(.explicit(string: error.description)))
                }
            }
        } else {
            Workstation.shared.download(from: from, format: .image) { (result) in
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
                        progress(.success(currentProgress))
                    }
                case .failure(let error):
                    completion(.failure(error))
                }
            }
        }
    }
}

extension UIImageView {
    public func fetch(image from: URL,
                      placeholder: UIImage = .image(with: #colorLiteral(red: 0.09411764706, green: 0.1450980392, blue: 0.231372549, alpha: 1)),
                      transition: Fetcher.Transition,
                      loader: FetcherLoader? = nil,
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
        Fetcher.get(image: from, progress: progress) { (result) in
            DispatchQueue.main.async {
                switch result {
                case .success(let image):
                    loader?.stop(animated: true)
                    UIView.transition(with: self, duration: transition.duration, options: [transition.options, .allowUserInteraction, .preferredFramesPerSecond60], animations: {
                        transition.animations?(self, image)
                    }, completion: {finished in
                        transition.completion?(finished)
                    })
                case .failure(let error):
                    completion(.failure(error))
                }
            }
        }
    }
}
