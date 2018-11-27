import Foundation
import UIKit


public class CameraFeedView: UIView {

    private let _capturePreview = CaptureVideoPreviewView()
    private var _dxConstraint: NSLayoutConstraint!
    private var _dyConstraint: NSLayoutConstraint!

    public override init(frame: CGRect) {
    
        // call base constructor
        super.init(frame: frame)
        
        // initialize
        initialize()
    }
    
    public required init(coder: NSCoder) {

        // call base constructor
        super.init(coder: coder)!
        
        // initialize
        initialize()
    }
    
    public func startPreview(cameraFeed: CameraFeed) {
    
        // bind feed session to layer
        let previewLayer = _capturePreview.previewLayer
        previewLayer.session = cameraFeed.captureSession
        
        // position layer
        previewLayer.backgroundColor = UIColor.red.cgColor
        previewLayer.videoGravity = .resizeAspect
        
        // show
        isHidden = false
    }
    
    public func stopPreview() {
        
        // hide
        isHidden = true

        // bind feed session to layer
        let previewLayer = _capturePreview.previewLayer
        previewLayer.session = nil
    }
    
    override public func layoutSubviews() {
        
        // update constraint (if required)
        if (_dyConstraint != nil) {
        
            // determine new offset
            let previewLayer = _capturePreview.previewLayer
            let offset = previewLayer.layerPointConverted(
                fromCaptureDevicePoint: CGPoint(x: 0, y: 0))
            
            // update constraints
            _dyConstraint.constant = -offset.y
            
            let layerSize = previewLayer.layerRectConverted(fromMetadataOutputRect: CGRect(x: 0, y: 0, width: 1, height: 1))

            print("updated offset: \(offset) \(layerSize)")
        }

        // call base method
        super.layoutSubviews()
    }
    
    private func initialize() {
        
        backgroundColor = UIColor.green

        // bind preview view
        addSubview(_capturePreview)

        // set preview constraints
        _capturePreview.translatesAutoresizingMaskIntoConstraints = false
        _dxConstraint = NSLayoutConstraint(item: _capturePreview, attribute: .centerX,
                                           relatedBy: .equal,
                                           toItem: self, attribute: .centerX,
                                           multiplier: 1.0, constant: 0.0)
        _dyConstraint = NSLayoutConstraint(item: _capturePreview, attribute: .centerY,
                                           relatedBy: .equal,
                                           toItem: self, attribute: .centerY,
                                           multiplier: 1.0, constant: 0.0)
       
        // bind constraints
        addConstraints([
            _dxConstraint,
            _dyConstraint,
            NSLayoutConstraint(item: _capturePreview, attribute: .width,
                               relatedBy: .equal,
                               toItem: self, attribute: .width,
                               multiplier: 1.0, constant:0.0),
            NSLayoutConstraint(item: _capturePreview, attribute: .height,
                               relatedBy: .equal,
                               toItem: self, attribute: .height,
                               multiplier: 1.0, constant:0.0)
        ])
    }
}
