import Foundation

public enum StorageDiskSafety {

    public enum Assessment: Equatable, Sendable {
        case externalPhysicalCandidate
        case rejected(String)
    }

    public static func assess(
        _ info: [String: Any]
    ) -> Assessment {

        guard let identifier =
            info["DeviceIdentifier"] as? String,
            identifier.range(
                of: #"^disk[0-9]+$"#,
                options: .regularExpression
            ) != nil
        else {
            return .rejected("Invalid disk identifier")
        }

        guard info["WholeDisk"] as? Bool == true else {
            return .rejected("Not a whole disk")
        }

        guard info["Internal"] as? Bool == false else {
            return .rejected("Internal or unknown disk")
        }

        guard info["VirtualOrPhysical"] as? String == "Physical" else {
            return .rejected("Virtual or unknown disk")
        }

        guard let size = info["Size"] as? NSNumber,
              size.uint64Value > 0
        else {
            return .rejected("Invalid disk size")
        }

        return .externalPhysicalCandidate
    }
}
