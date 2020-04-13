//
//  Workstation.swift
//  
//
//  Created by Eduard Shugar on 05.04.2020.
//

import Foundation
import StorageKit
import NetworkKit

fileprivate final class WorkstationContext {
    private(set) var workers: [URL: Worker] = [:]
    
    public func worker(with url: URL) -> Worker? {
        return workers[url]
    }
    
    //Memory could be cleared after a background session, save items via storage for further managing?
    public func add(worker: Worker) {
        workers[worker.remoteURL] = worker
    }
    
    public func remove(worker: Worker) {
        workers[worker.remoteURL] = nil
    }
    
}

public final class Workstation: NSObject {
    
    private var identifier = "background.download.session"
    private var session: URLSession!
        
    private let context = WorkstationContext()
    
    public var backgroundCompletion: (() -> Void)?
    
    public var workers: [Worker] {
        return Array(context.workers.values)
    }

    // MARK: - Singleton

    public static let shared = Workstation()

    // MARK: - Init

    private override init() {
        super.init()
        session = Network.Session.background(delegate: self, identifier: identifier).session
    }
    
    public func download(from remoteURL: URL, format: Storage.Format, configuration: Storage.Configuration, progress: @escaping (Result<Network.Progress, NetworkError>) -> Void) {
        guard context.worker(with: remoteURL) == nil else { return }
        let downloadTask = session.downloadTask(with: remoteURL)
        let worker = Worker(work: .download, format: format, configuration: configuration, remoteURL: remoteURL, progress: .loading, progressBlock: progress)
        context.add(worker: worker)
        downloadTask.resume()
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
    
}

extension Workstation: URLSessionDownloadDelegate {
    
    public func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard let originalRequestURL = downloadTask.originalRequest?.url, let worker = context.worker(with: originalRequestURL) else { return }
        do {
            let data = try Data(contentsOf: location)
            let output = Network.Progress.Output(data: data)
            worker.progress = .finished(output: output)
            let meta = File.Meta(name           : worker.remoteURL.absoluteString,
                                 extension      : worker.remoteURL.pathExtension,
                                 size           : .init(bytes: UInt64(data.count)),
                                 remoteURL      : worker.remoteURL,
                                 lastAccessDate : Date(),
                                 format         : worker.format)
            let file = File(data: data, meta: meta)
            Storage.Disk.set(file: file, configuration: worker.configuration)
        } catch {
            worker.progress = .failed(error: .data)
        }
        context.remove(worker: worker)
        Storage.Disk.removeFile(at: location)
    }
    
    public func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        DispatchQueue.main.async {
            self.backgroundCompletion?()
            self.backgroundCompletion = nil
        }
    }
    
    public func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didResumeAtOffset fileOffset: Int64, expectedTotalBytes: Int64) {
        guard let originalRequestURL = downloadTask.originalRequest?.url, let downloadItem = context.worker(with: originalRequestURL) else { return }
        downloadItem.progress = .downloading(progress: downloadTask.progress.fractionCompleted)
    }
        
    public func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard let originalRequestURL = downloadTask.originalRequest?.url, let worker = context.worker(with: originalRequestURL) else { return }
        worker.progress = .downloading(progress: downloadTask.progress.fractionCompleted)
    }
    
    public func urlSession(_ session: URLSession, task: URLSessionTask, didSendBodyData bytesSent: Int64, totalBytesSent: Int64, totalBytesExpectedToSend: Int64) {
        guard let originalRequestURL = task.originalRequest?.url, let worker = context.worker(with: originalRequestURL) else { return }
        worker.progress = .uploading(progress: task.progress.fractionCompleted)
    }
    
}
