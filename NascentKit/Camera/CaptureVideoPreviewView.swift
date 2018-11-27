import Foundation
import AVFoundation


internal class CaptureVideoPreviewView: UIView {

    public override class var layerClass: AnyClass {
        return AVCaptureVideoPreviewLayer.self
    }
    
    public var previewLayer: AVCaptureVideoPreviewLayer {
        get {
            return layer as! AVCaptureVideoPreviewLayer
        }
    }
}
