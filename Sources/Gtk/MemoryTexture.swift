import CGtk

public struct MemoryTexture {
    public let pointer: OpaquePointer

    public init(rgbaData: [UInt8], width: Int, height: Int, format: Int, stride: Int) {
        // `gsize`, not `UInt`. Both are 64 bits here, but Swift imports `gsize`
        // as `UInt` on Linux and `UInt64` on Windows, and those are different
        // nominal types. Naming the C type works on both.
        let bytes = g_bytes_new(rgbaData, gsize(rgbaData.count))
        pointer = gdk_memory_texture_new(Int32(width), Int32(height), GDK_MEMORY_R8G8B8A8, bytes, 4)
    }
}
