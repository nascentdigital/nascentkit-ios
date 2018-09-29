import Foundation


enum CameraFeedError: Error {
    
    case notInitialized
    case disposed
    case permissionRequired
    case permissionUnavailable
    case cameraNotFound
    case cameraNotCompatible
    case photoInProgress
}
