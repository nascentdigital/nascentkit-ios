import Foundation


public enum CameraFeedError: Error {
    
    case cameraNotFound
    case cameraNotCompatible
    case disposed
    case invalidState
    case notInitialized
    case permissionRequired
    case photoInProgress
}
