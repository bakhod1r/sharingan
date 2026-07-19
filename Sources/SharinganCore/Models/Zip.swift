import Foundation

/// Minimal store-only (no compression) ZIP archive builder — just enough to
/// package an .xlsx. Emits local file headers, a central directory, and the
/// end-of-central-directory record, all little-endian.
public enum Zip {
    public static func archive(files: [(name: String, data: Data)]) -> Data {
        var out = Data()
        var central = Data()
        var offset: UInt32 = 0

        for (name, data) in files {
            let nameBytes = Array(name.utf8)
            let crc = CRC32.checksum(data)
            let size = UInt32(data.count)

            // Local file header.
            var local = Data()
            local.append(le32: 0x0403_4b50)      // signature
            local.append(le16: 20)               // version needed
            local.append(le16: 0)                // flags
            local.append(le16: 0)                // method: store
            local.append(le16: 0)                // mod time
            local.append(le16: 0)                // mod date
            local.append(le32: crc)
            local.append(le32: size)             // compressed size
            local.append(le32: size)             // uncompressed size
            local.append(le16: UInt16(nameBytes.count))
            local.append(le16: 0)                // extra len
            local.append(contentsOf: nameBytes)
            local.append(data)

            // Central directory entry.
            central.append(le32: 0x0201_4b50)    // signature
            central.append(le16: 20)             // version made by
            central.append(le16: 20)             // version needed
            central.append(le16: 0)              // flags
            central.append(le16: 0)              // method
            central.append(le16: 0)              // mod time
            central.append(le16: 0)              // mod date
            central.append(le32: crc)
            central.append(le32: size)
            central.append(le32: size)
            central.append(le16: UInt16(nameBytes.count))
            central.append(le16: 0)              // extra len
            central.append(le16: 0)              // comment len
            central.append(le16: 0)              // disk number
            central.append(le16: 0)              // internal attrs
            central.append(le32: 0)              // external attrs
            central.append(le32: offset)         // local header offset
            central.append(contentsOf: nameBytes)

            out.append(local)
            offset += UInt32(local.count)
        }

        let centralOffset = offset
        let centralSize = UInt32(central.count)
        out.append(central)

        // End of central directory.
        out.append(le32: 0x0605_4b50)
        out.append(le16: 0)                      // disk
        out.append(le16: 0)                      // disk with central
        out.append(le16: UInt16(files.count))    // entries on disk
        out.append(le16: UInt16(files.count))    // total entries
        out.append(le32: centralSize)
        out.append(le32: centralOffset)
        out.append(le16: 0)                      // comment len
        return out
    }
}

/// Standard CRC-32 (IEEE 802.3), used by ZIP.
public enum CRC32 {
    private static let table: [UInt32] = {
        (0..<256).map { i -> UInt32 in
            var c = UInt32(i)
            for _ in 0..<8 { c = (c & 1) != 0 ? 0xEDB8_8320 ^ (c >> 1) : c >> 1 }
            return c
        }
    }()

    public static func checksum(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data {
            crc = table[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8)
        }
        return crc ^ 0xFFFF_FFFF
    }
}

private extension Data {
    mutating func append(le16 value: UInt16) {
        append(UInt8(value & 0xFF)); append(UInt8((value >> 8) & 0xFF))
    }
    mutating func append(le32 value: UInt32) {
        append(UInt8(value & 0xFF)); append(UInt8((value >> 8) & 0xFF))
        append(UInt8((value >> 16) & 0xFF)); append(UInt8((value >> 24) & 0xFF))
    }
}
