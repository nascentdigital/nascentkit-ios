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
        previewLayer.backgroundColor = UIColor.green.cgColor
        previewLayer.videoGravity = .resizeAspect
        
        // show
        isHidden = false

        // force refresh
        layoutIfNeeded()
    }
    
    public func stopPreview() {
        
        // hide
        isHidden = true

        // bind feed session to layer
        let previewLayer = _capturePreview.previewLayer
        previewLayer.session = nil
    }

    override public func layoutSubviews() {
        let previewLayer = self._capturePreview.previewLayer
        let oldLayerSize = previewLayer.layerRectConverted(fromMetadataOutputRect: CGRect(x: 0, y: 0, width: 1, height: 1))
        
        DispatchQueue.main.async {
            [unowned self] in
            let newLayerSize = previewLayer.layerRectConverted(fromMetadataOutputRect: CGRect(x: 0, y: 0, width: 1, height: 1))
            print("New Layer Size \(newLayerSize) , oldLayerSize \(String(describing: oldLayerSize))")

            // If the layerSize hasn't changed in time for the async closure to run, then correct offset can be calculated
            if(self._dyConstraint != nil && oldLayerSize.equalTo(newLayerSize)) {
                // determine new offset
                let offset = previewLayer.layerPointConverted(
                    fromCaptureDevicePoint: CGPoint(x: 0, y: 0))
                
                // update constraints
                self._dyConstraint.constant = -offset.y
                
                print("updated offset: \(offset) \(newLayerSize)")
                
                self.updateConstraints()
            } else {
                // Layer size is still different, need to run layoutSubviews again until layer stays constant
                self.setNeedsLayout()
                self.layoutIfNeeded()
            }
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
