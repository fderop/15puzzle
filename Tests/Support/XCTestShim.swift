import Foundation
nonisolated(unsafe) var failures = 0
class XCTestCase { required init() {} }
func XCTAssertTrue(_ e: @autoclosure () -> Bool, file: StaticString = #file, line: UInt = #line) { if !e() { failures += 1; print("FAIL line \(line)") } }
func XCTAssertFalse(_ e: @autoclosure () -> Bool, file: StaticString = #file, line: UInt = #line) { if e() { failures += 1; print("FAIL line \(line)") } }
func XCTAssertNil(_ e: @autoclosure () -> Any?, file: StaticString = #file, line: UInt = #line) { if e() != nil { failures += 1; print("FAIL line \(line)") } }
func XCTAssertNotNil(_ e: @autoclosure () -> Any?, file: StaticString = #file, line: UInt = #line) { if e() == nil { failures += 1; print("FAIL line \(line)") } }
func XCTAssertEqual<T: Equatable>(_ a: @autoclosure () -> T, _ b: @autoclosure () -> T, file: StaticString = #file, line: UInt = #line) { let x = a(), y = b(); if x != y { failures += 1; print("FAIL line \(line): \(x) != \(y)") } }
func XCTAssertLessThanOrEqual<T: Comparable>(_ a: @autoclosure () -> T, _ b: @autoclosure () -> T, file: StaticString = #file, line: UInt = #line) { let x = a(), y = b(); if !(x <= y) { failures += 1; print("FAIL line \(line): \(x) > \(y)") } }
