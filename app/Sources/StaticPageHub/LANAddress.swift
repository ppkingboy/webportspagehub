import Darwin
import Foundation

enum LANAddress {
    static func primaryIPv4Address() -> String? {
        var addressPointer: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addressPointer) == 0, let firstAddress = addressPointer else {
            return nil
        }

        defer {
            freeifaddrs(addressPointer)
        }

        var candidates: [(name: String, address: String)] = []
        var pointer: UnsafeMutablePointer<ifaddrs>? = firstAddress

        while let current = pointer {
            defer {
                pointer = current.pointee.ifa_next
            }

            guard let socketAddress = current.pointee.ifa_addr,
                  socketAddress.pointee.sa_family == UInt8(AF_INET) else {
                continue
            }

            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let result = getnameinfo(
                socketAddress,
                socklen_t(socketAddress.pointee.sa_len),
                &host,
                socklen_t(host.count),
                nil,
                0,
                NI_NUMERICHOST
            )

            guard result == 0 else {
                continue
            }

            let name = String(cString: current.pointee.ifa_name)
            let address = String(cString: host)

            if name == "en0" {
                return address
            }

            if !address.hasPrefix("127.") && !name.hasPrefix("utun") {
                candidates.append((name, address))
            }
        }

        return candidates.first?.address
    }
}

