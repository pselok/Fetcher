//
//  Workstation.swift
//  
//
//  Created by Eduard Shugar on 05.04.2020.
//

import UIKit
import CoreKit
import Foundation
import StorageKit
import NetworkKit

extension Workstation {
    public class Context {
        public private(set) var workers: [Worker] = []
        private let lock = NSLock()
        
        public func workers(with url: URL) -> [Worker] {
            return workers.filter{$0.remoteURL == url}
        }
        //Memory could be cleared after a background session, save items via storage for further managing?
        public func add(worker: Worker) -> Bool {
            lock.lock(); defer { lock.unlock() }
            let allowed = workers(with: worker.remoteURL).isEmpty
            workers.removeAll(where: {$0.recognizer == worker.recognizer})
            workers.append(worker)
            return allowed
        }
        public func remove(worker: Worker) {
            lock.lock(); defer { lock.unlock() }
            workers.removeAll(where: {$0 == worker})
        }
        public func remove(with url: URL) {
            lock.lock(); defer { lock.unlock() }
            workers.removeAll(where: {$0.remoteURL == url})
        }
        public func deafen(with recognizer: UUID) {
            lock.lock(); defer { lock.unlock() }
            workers.filter({$0.recognizer == recognizer}).forEach({$0.progress = .cancelled})
        }
    }
}

public class Workstation: NSObject {
    private let identifier = "com.fetcher.background"
    private var sessions: Sessions!
        
    private let context = Context()
    
    public var backgroundCompletion: (() -> Void)?
    
    public var workers: [Worker] {
        return context.workers
    }

    // MARK: - Singleton
    public static let shared = Workstation()

    // MARK: - Init
    private override init() {
        super.init()
        sessions = Sessions(foreground: Network.Session.foreground(cache: .none, delegate: self).session, background: Network.Session.background(delegate: self, identifier: identifier).session)
    }
    
    public func perform(work: Worker.Work, file: Storage.File, configuration: Storage.Configuration, recognizer: UUID, representation item: Core.Database.Item? = nil, progress: @escaping (Result<Fetcher.Output, Fetcher.Failure>) -> Void) {
        guard context.add(worker: Worker(work: work, file: file, configuration: configuration, remoteURL: work.url, progress: .loading, recognizer: recognizer, item: item, leech: progress)) else { return }
        switch work {
        case .download(let url, let session):
            sessions.session(for: session).downloadTask(with: url).resume()
        case .upload(let data, let url, let session):
            sessions.session(for: session).uploadTask(with: URLRequest(url: url), from: data).resume()
        }
    }
        
    public func fetched(recognizer: UUID) {
        context.deafen(with: recognizer)
    }
    
    public func toggle(worker: Worker, completion: @escaping (Fetcher.Progress) -> Void) {
        sessions.all.forEach({
            $0.getAllTasks { (tasks) in
                if let task = tasks.first(where: { (task) -> Bool in
                    task.originalRequest?.url == worker.remoteURL
                }) {
                    switch worker.progress {
                    case .paused:
                        task.resume()
                        worker.progress = .downloading(progress: task.progress.fractionCompleted)
                    case .downloading:
                        task.suspend()
                        worker.progress = .paused
                    default: break
                    }
                    main.async {
                        completion(worker.progress)
                    }
                }
            }
        })
    }
    
    public func cancel(worker: Worker, completely: Bool = true, completion: @escaping (Bool) -> Void) {
        worker.progress = .cancelled
        context.remove(worker: worker)
        sessions.all.forEach({
            $0.getAllTasks { (tasks) in
                if let task = tasks.first(where: { (task) -> Bool in
                    task.originalRequest?.url == worker.remoteURL
                }) {
                    task.cancel()
                    main.async {
                        completion(true)
                    }
                } else {
                    main.async {
                        completion(false)
                    }
                }
            }
        })
    }
    
    private func average(from workers: [Worker]) -> Worker? {
        guard let first = workers.first else { return nil }
        return Worker(work: first.work, file: first.file, configuration: workers.compactMap{$0.configuration}.sorted(by: {$0 > $1})[0], remoteURL: first.remoteURL, progress: first.progress, recognizer: first.recognizer, item: first.item, leech: first.leech)
    }
    
    deinit {sessions.all.forEach({$0.invalidateAndCancel()})}
}

extension Workstation: URLSessionDownloadDelegate {
    public func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let url = downloadTask.originalRequest?.url else { Storage.removeData(at: location); return }
        let workers = context.workers(with: url)
        guard !workers.isEmpty, let worker = average(from: workers) else { Storage.removeData(at: location); return }
        context.remove(with: url)
        var location = location
        do {
            switch worker.file {
            case .image:
                guard let raw = UIImage(contentsOfFile: location.path),
                      let decoded = raw.decoded,
                      let data = decoded.pngData() else {
                    throw(Fetcher.Failure.data)
                }
                location = try Storage.Disk.createURL(for: Storage.Folder.path(to: worker.file), in: .documents).dataURL
                try data.write(to: location)
            default:
                break
            }
            let meta = Storage.File.Meta(id       : worker.item?.id ?? worker.recognizer.hashValue,
                                         title    : worker.item?.title ?? worker.remoteURL.absoluteString,
                                         subtitle : worker.item?.subtitle,
                                         picture  : worker.item?.media?.picture?.id,
                                         extension: worker.remoteURL.pathExtension,
                                         size     : Storage.Disk.size(of: location),
                                         localURL : location,
                                         remoteURL: worker.remoteURL,
                                         file     : worker.file)
            let file = Storage.File.Storable(url: location, meta: meta)
            Storage.set(file: file, configuration: worker.configuration) { result in
                switch result {
                case .success(let output):
                    print("SSSSSSS")
                    workers.forEach{$0.progress = .finished(output: Fetcher.Progress.Output(url: output.file.url))}
                case .failure(let failure):
                    print("FFF \(failure)")
                    workers.forEach{$0.progress = .failed(error: .error(failure))}
                }
            }
        } catch let error {
            print(error)
            workers.forEach{$0.progress = .failed(error: .data)}
        }
    }
    
    public func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        main.async {
            self.backgroundCompletion?()
            self.backgroundCompletion = nil
        }
    }
        
    public func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let url = task.originalRequest?.url, let error = error else { return }
        context.workers(with: url).forEach{$0.progress = .failed(error: .error(error))}
    }

    public func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didResumeAtOffset fileOffset: Int64, expectedTotalBytes: Int64) {
        guard let url = downloadTask.originalRequest?.url else { return }
        context.workers(with: url).forEach{$0.progress = .downloading(progress: downloadTask.progress.fractionCompleted)}
    }
        
    public func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard let url = downloadTask.originalRequest?.url else { return }
        context.workers(with: url).forEach{$0.progress = .downloading(progress: downloadTask.progress.fractionCompleted)}
    }
    
    public func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64, totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
        guard let url = task.originalRequest?.url else { return }
        context.workers(with: url).forEach{$0.progress = .uploading(progress: task.progress.fractionCompleted)}
    }
}
