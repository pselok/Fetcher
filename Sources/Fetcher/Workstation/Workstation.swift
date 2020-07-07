//
//  Workstation.swift
//  
//
//  Created by Eduard Shugar on 05.04.2020.
//

import Foundation
import StorageKit
import NetworkKit

extension Workstation {
    public class Context {
        private(set) var workers: [URL: [Worker]] = [:]
        private let lock = NSLock()
        
        public func workers(with url: URL) -> [Worker]? {
            lock.lock(); defer { lock.unlock() }
            return workers[url]
        }
        
        //Memory could be cleared after a background session, save items via storage for further managing?
        public func add(worker: Worker) -> Bool {
            lock.lock(); defer { lock.unlock() }
            guard let working = workers(with: worker.remoteURL) else { return true }
            working.filter({$0.recognizer == worker.recognizer}).forEach{$0.progress = .cancelled}
            workers[worker.remoteURL]?.append(worker)
        }
        
        public func remove(worker: Worker) {
            lock.lock(); defer { lock.unlock() }
            workers[worker.remoteURL]?.removeAll(where: {$0.recognizer == worker.recognizer})
        }
        
        public func remove(with url: URL) {
            lock.lock(); defer { lock.unlock() }
            workers.removeValue(forKey: url)
        }
    }
}

public class Workstation: NSObject {
    private var identifier = "background.download.session"
    private var session: URLSession!
        
    private let context = Context()
    
    public var backgroundCompletion: (() -> Void)?
    
    public var workers: [URL: [Worker]] {
        return context.workers
    }

    // MARK: - Singleton
    public static let shared = Workstation()

    // MARK: - Init
    private override init() {
        super.init()
        session = Network.Session.background(delegate: self, identifier: identifier).session
    }
    
    public func fetch(file url: URL, format: Storage.Format, configuration: Storage.Configuration, recognizer: UUID, progress: @escaping (Result<Network.Progress, Network.Failure>) -> Void) {
        guard context.add(worker: Worker(work: .download, format: format, configuration: configuration, remoteURL: url, progress: .loading, recognizer: recognizer, leech: progress)) else { return }
        session.downloadTask(with: url).resume()
    }
    
    public func toggle(worker: Worker, completion: @escaping (Network.Progress) -> Void) {
        session.getAllTasks { (tasks) in
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
                DispatchQueue.main.async {
                    completion(worker.progress)
                }
            }
        }
    }
    
    public func cancel(worker: Worker, completely: Bool = true, completion: @escaping (Bool) -> Void) {
        worker.progress = .cancelled
        context.remove(worker: worker)
        session.getAllTasks { (tasks) in
            if let task = tasks.first(where: { (task) -> Bool in
                task.originalRequest?.url == worker.remoteURL
            }) {
                task.cancel()
                DispatchQueue.main.async {
                    completion(true)
                }
            } else {
                DispatchQueue.main.async {
                    completion(false)
                }
            }
        }
    }
    
    private func average(from workers: [Worker]) -> Worker {
        
    }
}

extension Workstation: URLSessionDownloadDelegate {
    public func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let url = downloadTask.originalRequest?.url, let workers = context.workers(with: url) else { return }
        do {
            let average = average(from: workers)
            let data = try Data(contentsOf: location)
            let output = Network.Progress.Output(data: data)
            workers.forEach{$0.progress = .finished(output: output)}
            let meta = Storage.File.Meta(name           : average.remoteURL.absoluteString,
                                         extension      : average.remoteURL.pathExtension,
                                         size           : .init(bytes: UInt64(data.count)),
                                         localURL       : location,
                                         remoteURL      : average.remoteURL,
                                         format         : average.format)
            let file = Storage.File(data: data, meta: meta)
            Storage.set(file: file, configuration: average.configuration)
        } catch {
            worker.progress = .failed(error: .data)
        }
        context.remove(with: url)
        Storage.removeData(at: location)
    }
    
    public func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        DispatchQueue.main.async {
            self.backgroundCompletion?()
            self.backgroundCompletion = nil
        }
    }
    
    public func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didResumeAtOffset fileOffset: Int64, expectedTotalBytes: Int64) {
        guard let url = downloadTask.originalRequest?.url, let workers = context.workers(with: url) else { return }
        workers.forEach{$0.progress = .downloading(progress: downloadTask.progress.fractionCompleted)}
    }
        
    public func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard let url = downloadTask.originalRequest?.url, let workers = context.workers(with: url) else { return }
        workers.forEach{$0.progress = .downloading(progress: downloadTask.progress.fractionCompleted)}
    }
    
    public func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64, totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
        guard let url = task.originalRequest?.url, let workers = context.workers(with: url) else { return }
        workers.forEach{$0.progress = .uploading(progress: task.progress.fractionCompleted)}
    }
}
