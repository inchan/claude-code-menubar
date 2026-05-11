import Foundation

/// FNV-1a 32-bit. 결정적 해시 — 같은 입력은 항상 같은 결과.
/// 사용처: Account 색상 결정, 토큰 마스킹.
enum FNV {
    static func hash32(_ s: String) -> UInt32 {
        var h: UInt32 = 0x811c9dc5
        for byte in s.utf8 {
            h ^= UInt32(byte)
            h &*= 0x01000193
        }
        return h
    }
}
