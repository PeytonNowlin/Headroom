import os

/// Unified logging. Never log credentials or response bodies; statuses and counts only.
public enum HeadroomLog {
    public static let subsystem = "com.peytonnowlin.headroom"
    public static let polling = Logger(subsystem: subsystem, category: "polling")
    public static let credentials = Logger(subsystem: subsystem, category: "credentials")
    public static let spend = Logger(subsystem: subsystem, category: "spend")
}
