import Foundation
import UIKit
import AVFoundation


public class CameraFeedView: UIView {

    public override class var layerClass: AnyClass {
        return AVCaptureVideoPreviewLayer.self
    }
    
    public func startPreview(cameraFeed: CameraFeed) {
    
        // get preview layer
        let previewLayer = layer as! AVCaptureVideoPreviewLayer
        
        // bind feed session to layer
        previewLayer.session = cameraFeed.captureSession
        
        // show
        isHidden = false
    }
    
    public func stopPreview() {
        
        // hide
        isHidden = false

        // get preview layer
        let previewLayer = layer as! AVCaptureVideoPreviewLayer
        
        // bind feed session to layer
        previewLayer.session = nil
    }
}
