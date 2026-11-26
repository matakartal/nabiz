// Nabız — © 2026 Mehmet Ata Kartal. Licensed under GPL-3.0-or-later; see LICENSE.
import Darwin
import Foundation

/// A TCP socket a process listens on.
struct ListeningSocket: Sendable, Hashable {
    let port: UInt16
    /// Bound to every interface (0.0.0.0 or ::), so other devices on the network can reach it; else only this Mac.
    let everyInterface: Bool
}

/// Process facts through libproc and sysctl: no `ps` or `lsof`, a few milliseconds for every process. Only the
/// user's own processes answer the socket and folder questions; the system's (root) ones are hidden by macOS.
enum ProcInfo {
    static func allPIDs() -> [pid_t] {
        let estimate = proc_listallpids(nil, 0)
        guard estimate > 0 else { return [] }
        var pids = [pid_t](repeating: 0, count: Int(estimate) + 64)
        let found = pids.withUnsafeMutableBytes { proc_listallpids($0.baseAddress, Int32($0.count)) }
        return Array(pids.prefix(Int(max(found, 0))))
    }

    static func isAlive(_ pid: pid_t) -> Bool {
        // A zombie still answers kill(0) until its parent reaps it; its BSD info says it's gone.
        guard kill(pid, 0) == 0, let info = bsdInfo(pid) else { return false }
        return info.pbi_status != UInt32(SZOMB)
    }

    static func childCount(_ pid: pid_t) -> Int {
        var children = [pid_t](repeating: 0, count: 64)
        let found = children.withUnsafeMutableBytes { proc_listchildpids(pid, $0.baseAddress, Int32($0.count)) }
        return Int(max(found, 0))
    }

    static func bsdInfo(_ pid: pid_t) -> proc_bsdinfo? {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        return proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size ? info : nil
    }

    static func name(_ info: proc_bsdinfo) -> String {
        withUnsafeBytes(of: info.pbi_comm) { String(cString: $0.bindMemory(to: CChar.self).baseAddress!) }
    }

    static func started(_ info: proc_bsdinfo) -> Date? {
        info.pbi_start_tvsec > 0 ? Date(timeIntervalSince1970: TimeInterval(info.pbi_start_tvsec)) : nil
    }

    static func listeningPorts(_ pid: pid_t) -> [UInt16] {
        Array(Set(listeningSockets(pid).map(\.port))).sorted()
    }

    /// Each listening TCP socket, one per port (every interface wins over loopback), lowest port first.
    static func listeningSockets(_ pid: pid_t) -> [ListeningSocket] {
        let size = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, nil, 0)
        guard size > 0 else { return [] }
        let stride = MemoryLayout<proc_fdinfo>.stride
        var fds = [proc_fdinfo](repeating: proc_fdinfo(), count: Int(size) / stride + 16)
        let bytes = fds.withUnsafeMutableBytes { proc_pidinfo(pid, PROC_PIDLISTFDS, 0, $0.baseAddress, Int32($0.count)) }
        guard bytes > 0 else { return [] }
        var ports: [UInt16: Bool] = [:]
        for fd in fds.prefix(Int(bytes) / stride) where fd.proc_fdtype == UInt32(PROX_FDTYPE_SOCKET) {
            var socket = socket_fdinfo()
            let socketSize = Int32(MemoryLayout<socket_fdinfo>.size)
            guard proc_pidfdinfo(pid, fd.proc_fd, PROC_PIDFDSOCKETINFO, &socket, socketSize) == socketSize,
                  socket.psi.soi_kind == SOCKINFO_TCP else { continue }
            let tcp = socket.psi.soi_proto.pri_tcp
            guard tcp.tcpsi_state == TSI_S_LISTEN else { continue }
            let port = UInt16(bigEndian: UInt16(truncatingIfNeeded: tcp.tcpsi_ini.insi_lport))
            let any = isAnyAddress(tcp.tcpsi_ini)
            ports[port] = (ports[port] ?? false) || any
        }
        return ports.map { ListeningSocket(port: $0.key, everyInterface: $0.value) }.sorted { $0.port < $1.port }
    }

    private static func isAnyAddress(_ ini: in_sockinfo) -> Bool {
        if ini.insi_vflag & UInt8(INI_IPV4) != 0 && ini.insi_vflag & UInt8(INI_IPV6) == 0 {
            return ini.insi_laddr.ina_46.i46a_addr4.s_addr == 0
        }
        return withUnsafeBytes(of: ini.insi_laddr.ina_6) { $0.allSatisfy { $0 == 0 } }
    }

    static func workingFolder(_ pid: pid_t) -> String? {
        var info = proc_vnodepathinfo()
        let size = Int32(MemoryLayout<proc_vnodepathinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &info, size) == size else { return nil }
        let path = withUnsafeBytes(of: info.pvi_cdir.vip_path) { String(cString: $0.bindMemory(to: CChar.self).baseAddress!) }
        return path.isEmpty ? nil : path
    }

    /// The executable's full path.
    static func executable(_ pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        return length > 0 ? String(decoding: buffer.prefix(Int(length)).map { UInt8(bitPattern: $0) }, as: UTF8.self) : nil
    }

    /// argv through KERN_PROCARGS2: argc, the executable path, padding, then argc strings.
    static func arguments(_ pid: pid_t) -> [String] {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > MemoryLayout<Int32>.size else { return [] }
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, 3, &buffer, &size, nil, 0) == 0 else { return [] }
        let argc = buffer.withUnsafeBytes { $0.load(as: Int32.self) }
        var index = MemoryLayout<Int32>.size
        while index < size, buffer[index] != 0 { index += 1 }   // executable path
        while index < size, buffer[index] == 0 { index += 1 }   // padding
        var result: [String] = []
        while index < size, result.count < Int(argc) {
            let start = index
            while index < size, buffer[index] != 0 { index += 1 }
            result.append(String(decoding: buffer[start..<index], as: UTF8.self))
            index += 1
        }
        return result
    }

    /// True when something accepts TCP connections on this port on 127.0.0.1 (a system process we can't see).
    static func somethingListens(on port: UInt16) -> Bool {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        defer { close(fd) }
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        return withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) == 0 }
        }
    }
}
