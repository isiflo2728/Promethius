import Foundation

/// Live machine readings for the agent detail's "Live Activity" panel.
/// Mac-only: inference happens on this machine (LM Studio holds ~9GB of the
/// model in unified memory), so system RAM and thermal pressure are the
/// honest signals of what a run costs — unlike per-app stats, which would
/// miss the model server entirely.
enum SystemStats {
    /// System-wide memory in use (active + wired + compressed), the same
    /// approximation Activity Monitor's "Memory Used" shows. Nil if the mach
    /// call fails.
    static func memoryUsedBytes() -> UInt64? {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size
        )
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        let pages = UInt64(stats.active_count)
            + UInt64(stats.wire_count)
            + UInt64(stats.compressor_page_count)
        return pages * UInt64(vm_page_size)
    }

    static var memoryTotalBytes: UInt64 { ProcessInfo.processInfo.physicalMemory }

    /// The OS's thermal pressure signal. True die temperature needs private
    /// SMC access; this is the supported equivalent and what actually
    /// matters — it's what makes the machine throttle inference.
    static var thermalState: ProcessInfo.ThermalState { ProcessInfo.processInfo.thermalState }
}
