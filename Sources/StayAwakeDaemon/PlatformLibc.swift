#if canImport(Musl)
import Musl
#elseif canImport(Glibc)
import Glibc
#endif

// The platform libc module is Glibc on a normal Linux build and Musl on the
// static Linux SDK, so call sites cannot qualify these calls by module name.
// These top-level wrappers are unambiguous, which is what the Glibc.* prefixes
// were buying: RCONClient has its own connect()/close() methods that would
// otherwise shadow the libc ones.

#if canImport(Musl)
let sysSockStream: Int32 = SOCK_STREAM
#else
let sysSockStream: Int32 = Int32(SOCK_STREAM.rawValue)
#endif

func sysConnect(_ fd: Int32, _ addr: UnsafePointer<sockaddr>, _ len: socklen_t) -> Int32 {
    connect(fd, addr, len)
}

@discardableResult
func sysClose(_ fd: Int32) -> Int32 {
    close(fd)
}

func sysSend(_ fd: Int32, _ buffer: UnsafeRawPointer, _ count: Int, _ flags: Int32) -> Int {
    send(fd, buffer, count, flags)
}

func sysRecv(_ fd: Int32, _ buffer: UnsafeMutableRawPointer, _ count: Int, _ flags: Int32) -> Int {
    recv(fd, buffer, count, flags)
}
