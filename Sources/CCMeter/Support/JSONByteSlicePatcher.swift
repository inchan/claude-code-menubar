import Foundation

/// 최상위 객체의 단일 키 값을 **원본 바이트 영역만** 새 값으로 교체한다.
/// 키 순서, 들여쓰기, 정수/실수 표현, 알 수 없는 필드를 모두 보존한다.
///
/// 한계 / 가정:
/// - 입력은 UTF-8 JSON 객체.
/// - 키는 최상위 레벨에 1회만 등장.
/// - 값은 객체(`{...}`) 또는 배열(`[...]`). 단일 토큰(string/number/bool/null) 도 지원.
enum JSONByteSlicePatcher {
    enum Error: Swift.Error, CustomStringConvertible {
        case keyNotFound(String)
        case malformed(String)
        var description: String {
            switch self {
            case .keyNotFound(let k): return "JSONByteSlicePatcher: key not found '\(k)'"
            case .malformed(let m): return "JSONByteSlicePatcher: malformed — \(m)"
            }
        }
    }

    /// `json` 의 최상위 `key` value 영역을 `newValue` 바이트로 교체한 새 Data 반환.
    static func replace(in json: Data, key: String, with newValue: Data) throws -> Data {
        let bytes = [UInt8](json)
        let keyRange = try findTopLevelKeyRange(bytes: bytes, key: key)
        let valueRange = try findValueRange(bytes: bytes, after: keyRange.upperBound)
        var out = Data()
        out.append(contentsOf: bytes[0..<valueRange.lowerBound])
        out.append(newValue)
        out.append(contentsOf: bytes[valueRange.upperBound..<bytes.count])
        return out
    }

    /// 최상위 객체 안에서 `"key"` 의 (시작, 끝+1) 범위. depth 1 (최상위) 만 매칭.
    private static func findTopLevelKeyRange(bytes: [UInt8], key: String) throws -> Range<Int> {
        let target = Array(("\"" + key + "\"").utf8)
        var i = 0
        // 최상위 `{` 까지 스킵
        while i < bytes.count, bytes[i] != UInt8(ascii: "{") { i += 1 }
        guard i < bytes.count else { throw Error.malformed("no top-level object") }
        i += 1
        var depth = 1
        var inString = false
        var escape = false
        while i < bytes.count {
            let b = bytes[i]
            if inString {
                if escape { escape = false; i += 1; continue }
                if b == UInt8(ascii: "\\") { escape = true; i += 1; continue }
                if b == UInt8(ascii: "\"") { inString = false; i += 1; continue }
                i += 1; continue
            }
            if b == UInt8(ascii: "\"") {
                if depth == 1, matches(bytes: bytes, at: i, sequence: target) {
                    return i..<(i + target.count)
                }
                inString = true
                i += 1
                continue
            }
            if b == UInt8(ascii: "{") || b == UInt8(ascii: "[") { depth += 1; i += 1; continue }
            if b == UInt8(ascii: "}") || b == UInt8(ascii: "]") {
                depth -= 1
                if depth == 0 { break }
                i += 1; continue
            }
            i += 1
        }
        throw Error.keyNotFound(key)
    }

    /// 키 닫는 따옴표 다음부터 `:` 다음 첫 토큰의 (시작, 끝+1) 범위.
    private static func findValueRange(bytes: [UInt8], after keyEnd: Int) throws -> Range<Int> {
        var i = keyEnd
        // 공백 + ':'
        while i < bytes.count, isWhitespace(bytes[i]) { i += 1 }
        guard i < bytes.count, bytes[i] == UInt8(ascii: ":") else {
            throw Error.malformed("expected ':' after key")
        }
        i += 1
        while i < bytes.count, isWhitespace(bytes[i]) { i += 1 }
        guard i < bytes.count else { throw Error.malformed("no value") }
        let start = i
        let b = bytes[i]
        switch b {
        case UInt8(ascii: "{"), UInt8(ascii: "["):
            // balanced match
            let open = b
            let close: UInt8 = (b == UInt8(ascii: "{")) ? UInt8(ascii: "}") : UInt8(ascii: "]")
            var depth = 1
            var inString = false
            var escape = false
            i += 1
            while i < bytes.count {
                let c = bytes[i]
                if inString {
                    if escape { escape = false; i += 1; continue }
                    if c == UInt8(ascii: "\\") { escape = true; i += 1; continue }
                    if c == UInt8(ascii: "\"") { inString = false; i += 1; continue }
                    i += 1; continue
                }
                if c == UInt8(ascii: "\"") { inString = true; i += 1; continue }
                if c == open { depth += 1; i += 1; continue }
                if c == close {
                    depth -= 1
                    if depth == 0 { return start..<(i + 1) }
                    i += 1; continue
                }
                i += 1
            }
            throw Error.malformed("unterminated value")
        case UInt8(ascii: "\""):
            // string
            var inEscape = false
            i += 1
            while i < bytes.count {
                let c = bytes[i]
                if inEscape { inEscape = false; i += 1; continue }
                if c == UInt8(ascii: "\\") { inEscape = true; i += 1; continue }
                if c == UInt8(ascii: "\"") { return start..<(i + 1) }
                i += 1
            }
            throw Error.malformed("unterminated string")
        default:
            // number / true / false / null — 값의 끝은 ',' 또는 '}' 또는 ']' 또는 whitespace
            while i < bytes.count {
                let c = bytes[i]
                if c == UInt8(ascii: ",") || c == UInt8(ascii: "}") || c == UInt8(ascii: "]")
                    || isWhitespace(c) {
                    return start..<i
                }
                i += 1
            }
            return start..<i
        }
    }

    private static func isWhitespace(_ b: UInt8) -> Bool {
        b == 0x20 || b == 0x09 || b == 0x0A || b == 0x0D
    }

    private static func matches(bytes: [UInt8], at index: Int, sequence: [UInt8]) -> Bool {
        guard index + sequence.count <= bytes.count else { return false }
        for k in 0..<sequence.count where bytes[index + k] != sequence[k] {
            return false
        }
        return true
    }
}
