import Foundation

public func debugPrintWithTimestamp(_ items: Any..., separator: String = " ", terminator: String = "\n", file: String = #file, line: Int = #line) {
    #if DEBUG
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "HH:mm:ss.SSS"
        let timestamp = dateFormatter.string(from: Date())

        let fileName = (file as NSString).lastPathComponent
        let output = items.map { "\($0)" }.joined(separator: separator)

        print("⏰[\(timestamp)] [\(fileName):\(line)] \(output)", terminator: terminator)
    #endif
}
