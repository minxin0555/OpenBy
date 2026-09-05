import Foundation

/// 轻量测试运行器：无 Xcode/CLT 环境下 `swift test` 不可用（CLT SDK 不含 XCTest，
/// Swift Testing framework 也不在可链接路径），故用断言式用例替代。
public enum MiniTest {
    public struct Failure: Error, CustomStringConvertible {
        public let message: String
        public let file: String
        public let line: Int
        public var description: String { "\(file):\(line): \(message)" }
    }

    public struct Case {
        public let name: String
        public let body: () throws -> Void

        public init(_ name: String, _ body: @escaping () throws -> Void) {
            self.name = name
            self.body = body
        }
    }

    /// 运行全部用例，打印汇总；返回是否全部通过。
    @discardableResult
    public static func run(_ cases: [Case]) -> Bool {
        var passed = 0
        var failures: [String] = []

        for testCase in cases {
            do {
                try testCase.body()
                passed += 1
            } catch {
                failures.append("  ✗ \(testCase.name) — \(error)")
            }
        }

        print("共 \(cases.count) 个用例：通过 \(passed)，失败 \(failures.count)")
        for failure in failures {
            print(failure)
        }
        return failures.isEmpty
    }
}

// MARK: - 断言函数

func check(_ condition: Bool, _ message: String = "", file: String = #filePath, line: Int = #line) throws {
    guard condition else {
        throw MiniTest.Failure(message: message.isEmpty ? "check 失败" : message, file: file, line: line)
    }
}

func expectEqual<T: Equatable>(_ actual: T, _ expected: T, _ message: String = "", file: String = #filePath, line: Int = #line) throws {
    guard actual == expected else {
        throw MiniTest.Failure(message: "\(message) 期望 \(expected)，实际 \(actual)", file: file, line: line)
    }
}

func expectNil<T>(_ value: T?, _ message: String = "", file: String = #filePath, line: Int = #line) throws {
    guard value == nil else {
        throw MiniTest.Failure(message: "\(message) 期望 nil，实际 \(String(describing: value))", file: file, line: line)
    }
}

@discardableResult
func expectNotNil<T>(_ value: T?, _ message: String = "", file: String = #filePath, line: Int = #line) throws -> T {
    guard let value else {
        throw MiniTest.Failure(message: "\(message) 期望非 nil", file: file, line: line)
    }
    return value
}

func expectThrows<T>(_ body: () throws -> T, _ message: String = "", file: String = #filePath, line: Int = #line) throws {
    do {
        _ = try body()
        throw MiniTest.Failure(message: "\(message) 期望抛错，实际未抛", file: file, line: line)
    } catch is MiniTest.Failure {
        throw MiniTest.Failure(message: "\(message) 断言失败", file: file, line: line)
    } catch {
        // 期望的抛错。
    }
}

/// `Void` 在新 Swift 中不满足 Equatable，用专用断言校验 `Result<Void, Error>` 成功。
func expectSuccess(_ result: Result<Void, Error>, _ message: String = "", file: String = #filePath, line: Int = #line) throws {
    guard case .success = result else {
        throw MiniTest.Failure(message: "\(message) 期望成功，实际失败", file: file, line: line)
    }
}
