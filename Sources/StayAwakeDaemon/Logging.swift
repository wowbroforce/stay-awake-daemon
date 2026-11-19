import Foundation
#if canImport(Musl)
import Musl
#elseif canImport(Glibc)
import Glibc
#endif

func log(_ message: String) {
    print(message)
    fflush(stdout)
}
func logError(_ message: String) {
    FileHandle.standardError.write((message + "\n").data(using: .utf8)!)
}
