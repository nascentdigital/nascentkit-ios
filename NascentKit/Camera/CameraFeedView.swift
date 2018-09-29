import Foundation
import UIKit
import AVFoundation


class CameraFeedView: UIView {

    override class var layerClass: AnyClass {
        return AVCaptureVideoPreviewLayer.self
    }
    
    func startPreview(cameraFeed: CameraFeed) {
    
        // get preview layer
        let previewLayer = layer as! AVCaptureVideoPreviewLayer
        
        // bind feed session to layer
        previewLayer.session = cameraFeed.captureSession
    }
    
    func stopPreview() {
     
        // get preview layer
        let previewLayer = layer as! AVCaptureVideoPreviewLayer
        
        // bind feed session to layer
        previewLayer.session = nil
    }
}
