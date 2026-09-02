import Foundation

extension HostEnvironment {
    /// The real machine: home directory, keychain via `security`, URLSession, wall clock.
    public static func live() -> HostEnvironment {
        let session = URLSession(configuration: {
            let c = URLSessionConfiguration.ephemeral
            c.timeoutIntervalForRequest = 20
            c.waitsForConnectivity = false
            return c
        }())
        return HostEnvironment(
            home: FileManager.default.homeDirectoryForCurrentUser,
            timeZone: .current,
            readFile: { try Data(contentsOf: $0) },
            fileExists: { FileManager.default.fileExists(atPath: $0.path(percentEncoded: false)) },
            keychainPassword: { service in Keychain.genericPassword(service: service) },
            environmentVariable: { ProcessInfo.processInfo.environment[$0] },
            send: { request in
                var r = URLRequest(url: request.url)
                r.httpMethod = request.method
                r.httpBody = request.body
                for (k, v) in request.headers { r.setValue(v, forHTTPHeaderField: k) }
                let (data, response) = try await session.data(for: r)
                let http = response as? HTTPURLResponse
                var headers: [String: String] = [:]
                for (k, v) in http?.allHeaderFields ?? [:] {
                    if let k = k as? String, let v = v as? String { headers[k.lowercased()] = v }
                }
                return HTTPResponse(statusCode: http?.statusCode ?? 0, headers: headers, body: data)
            },
            now: { Date() },
            sleep: { try await Task.sleep(for: $0) },
            enumerateFiles: { directory, ext in
                let fm = FileManager.default
                guard let e = fm.enumerator(at: directory, includingPropertiesForKeys: [.isRegularFileKey],
                                            options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { return [] }
                var out: [URL] = []
                for case let url as URL in e where url.pathExtension == ext {
                    if (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true {
                        out.append(url)
                    }
                }
                return out
            },
            fileInfo: { url in
                guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path(percentEncoded: false)),
                      let size = attrs[.size] as? Int,
                      let modified = attrs[.modificationDate] as? Date else { return nil }
                return FileInfo(size: size, modified: modified)
            },
            readFileRange: { url, offset in
                let handle = try FileHandle(forReadingFrom: url)
                defer { try? handle.close() }
                try handle.seek(toOffset: UInt64(offset))
                return try handle.readToEnd() ?? Data()
            },
            writeFile: { url, data in
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                        withIntermediateDirectories: true)
                try data.write(to: url, options: .atomic)
            }
        )
    }
}

enum Keychain {
    /// Reads a generic password item by shelling out to `security`, the same way the CLIs'
    /// own tooling does. Read-only; never adds, updates, or deletes items.
    static func genericPassword(service: String) -> Data? {
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/security")
        process.arguments = ["find-generic-password", "-s", service, "-w"]
        let out = Pipe()
        process.standardOutput = out
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return nil
        }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            HeadroomLog.credentials.error("security find-generic-password for \(service, privacy: .public) exited \(process.terminationStatus)")
            return nil
        }
        HeadroomLog.credentials.debug("keychain item \(service, privacy: .public): \(data.count) bytes")
        // `security -w` prints hex for non-UTF8 payloads and appends a newline otherwise.
        if let text = String(data: data, encoding: .utf8) {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if let decoded = Data(hexString: trimmed) { return decoded }
            return Data(trimmed.utf8)
        }
        return data
    }
}

extension Data {
    init?(hexString: String) {
        guard !hexString.isEmpty, hexString.count % 2 == 0,
              hexString.allSatisfy(\.isHexDigit) else { return nil }
        var bytes = [UInt8]()
        bytes.reserveCapacity(hexString.count / 2)
        var index = hexString.startIndex
        while index < hexString.endIndex {
            let next = hexString.index(index, offsetBy: 2)
            guard let byte = UInt8(hexString[index..<next], radix: 16) else { return nil }
            bytes.append(byte)
            index = next
        }
        self.init(bytes)
    }
}
