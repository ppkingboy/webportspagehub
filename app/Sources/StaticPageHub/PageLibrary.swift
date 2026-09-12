import Foundation

struct StaticPage: Codable, Identifiable {
    let id: String
    let title: String
    let relativePath: String
    let group: String
}

enum PageLibraryError: LocalizedError {
    case missingBundledWebDirectory
    case unableToCreatePagesDirectory(Error)
    case unableToCopyBundledPages(Error)

    var errorDescription: String? {
        switch self {
        case .missingBundledWebDirectory:
            return "应用内置页面目录不存在。"
        case .unableToCreatePagesDirectory(let error):
            return "无法创建页面目录：\(error.localizedDescription)"
        case .unableToCopyBundledPages(let error):
            return "无法复制内置页面：\(error.localizedDescription)"
        }
    }
}

final class PageLibrary {
    let rootURL: URL
    private let bundledWebURL: URL

    init(fileManager: FileManager = .default) throws {
        guard let resourceURL = Bundle.main.resourceURL else {
            throw PageLibraryError.missingBundledWebDirectory
        }

        bundledWebURL = resourceURL.appendingPathComponent("Web", isDirectory: true)

        guard fileManager.fileExists(atPath: bundledWebURL.path) else {
            throw PageLibraryError.missingBundledWebDirectory
        }

        let applicationSupport = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )

        rootURL = applicationSupport
            .appendingPathComponent("安华金和静态页面", isDirectory: true)
            .appendingPathComponent("Web", isDirectory: true)

        try preparePagesDirectory(fileManager: fileManager)
    }

    func scanPages(fileManager: FileManager = .default) -> [StaticPage] {
        guard let enumerator = fileManager.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return []
        }

        var pages: [StaticPage] = []

        for case let fileURL as URL in enumerator {
            let relativeComponents = fileURL.pathComponents.dropFirst(rootURL.pathComponents.count)
            guard !relativeComponents.contains(where: {
                $0.hasPrefix(".") || $0.hasSuffix("_files")
            }) else {
                continue
            }

            let isRootIndex = relativeComponents.count == 1
                && fileURL.lastPathComponent.lowercased() == "index.html"

            guard fileURL.pathExtension.lowercased() == "html", !isRootIndex else {
                continue
            }

            let relativePath = relativeComponents.joined(separator: "/")
            pages.append(
                StaticPage(
                    id: relativePath,
                    title: pageTitle(at: fileURL) ?? fileURL.deletingPathExtension().lastPathComponent,
                    relativePath: relativePath,
                    group: pageGroup(for: relativeComponents)
                )
            )
        }

        return pages.sorted {
            if $0.group == $1.group {
                return $0.title.localizedStandardCompare($1.title) == .orderedAscending
            }
            return $0.group.localizedStandardCompare($1.group) == .orderedAscending
        }
    }

    private func preparePagesDirectory(fileManager: FileManager) throws {
        if !fileManager.fileExists(atPath: rootURL.path) {
            do {
                try fileManager.createDirectory(
                    at: rootURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
            } catch {
                throw PageLibraryError.unableToCreatePagesDirectory(error)
            }

            do {
                try fileManager.copyItem(at: bundledWebURL, to: rootURL)
                return
            } catch {
                throw PageLibraryError.unableToCopyBundledPages(error)
            }
        }

        do {
            try refreshManagedAssets(fileManager: fileManager)
        } catch {
            throw PageLibraryError.unableToCopyBundledPages(error)
        }
    }

    private func pageTitle(at url: URL) -> String? {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe),
              let html = String(data: data, encoding: .utf8),
              let openingRange = html.range(of: "<title", options: [.caseInsensitive]),
              let openingEnd = html[openingRange.lowerBound...].firstIndex(of: ">"),
              let closingRange = html.range(
                of: "</title>",
                options: [.caseInsensitive],
                range: html.index(after: openingEnd)..<html.endIndex
              ) else {
            return nil
        }

        let title = html[html.index(after: openingEnd)..<closingRange.lowerBound]
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return title.isEmpty ? nil : title
    }

    private func pageGroup(for components: ArraySlice<String>) -> String {
        guard components.count > 1 else {
            return "页面"
        }
        return components.dropLast().last ?? "页面"
    }

    private func refreshManagedAssets(fileManager: FileManager) throws {
        for relativePath in ["index.html", "assets"] {
            let source = bundledWebURL.appendingPathComponent(relativePath)
            let destination = rootURL.appendingPathComponent(relativePath)

            if fileManager.fileExists(atPath: destination.path) {
                try fileManager.removeItem(at: destination)
            }
            try fileManager.copyItem(at: source, to: destination)
        }
    }
}
