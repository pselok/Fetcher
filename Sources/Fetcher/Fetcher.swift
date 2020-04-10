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
    
    static func retrieve(image from: URL,
                         progress: @escaping (Result<Network.Progress, NetworkError>) -> Void,
                         completion: @escaping (Result<UIImage, NetworkError>) -> Void) {
        if Storage.Disk(path: from.absoluteString).exists() {
            Storage.Disk(path: from.absoluteString).retrieve(storable: .image, as: Storage.SKImage.self, qos: .userInteractive) { (result) in
                switch result {
                case .success(let image):
                    completion(.success(image.image))
                case .failure(let error):
                    completion(.failure(.explicit(string: error.description)))
                }
            }
        } else {
            Workstation.shared.download(from: from, format: .image, progress: progress)
        }
    }
}

extension UIImageView {
    public func fetch(image from: URL,
                      placeholder: UIImage = .image(with: #colorLiteral(red: 0.09411764706, green: 0.1450980392, blue: 0.231372549, alpha: 1)),
                      transition: FetcherTransition = Fetcher.Transition.fade(),
                      loader: FetcherLoader? = nil,
                      progress: @escaping (Result<Network.Progress, NetworkError>) -> Void = {_ in},
                      completion: @escaping (Result<UIImage, NetworkError>) -> Void = {_ in}) {
        self.image = placeholder
        if let loader = loader {
            loader.translatesAutoresizingMaskIntoConstraints = false
            addSubview(loader)
            loader.box(in: self)
            loader.start()
        }
        Fetcher.retrieve(image: from, progress: progress) { (result) in
            switch result {
            case .success(let image):
                //set image with animation
                print()
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
}
