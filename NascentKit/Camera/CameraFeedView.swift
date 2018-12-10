import Foundation
import UIKit


public class CameraFeedView: UIView {

    private let _capturePreview = CaptureVideoPreviewView()
    private var _dxConstraint: NSLayoutConstraint!
    private var _dyConstraint: NSLayoutConstraint!
    private var _innerContainerSize: CGRect!
    private var _lastOffset: CGFloat!
    
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
        // if this is the first load
        if (_innerContainerSize == nil || _lastOffset == nil || _innerContainerSize.isEmpty) {
            
            DispatchQueue.main.async {
            [unowned self] in
            
                // set the inner container size
                self._innerContainerSize = previewLayer.layerRectConverted(fromMetadataOutputRect: CGRect(x: 0, y: 0, width: 1, height: 1))
                
                // determine offset
                self._lastOffset = previewLayer.layerPointConverted(
                        fromCaptureDevicePoint: CGPoint(x: 0, y: 0)).y
                
                // update constraints
                self._dyConstraint.constant = -self._lastOffset
            }
        }
        // otherwse
        else {
        
            // get last container size
            let oldContainerSize = _innerContainerSize
            
            DispatchQueue.main.async {
            [unowned self] in
                
                // get outer container size
                let outerContainerSize = self.bounds
                
                // calculate aspect rations
                let innerContainerAspectRatio = oldContainerSize!.width / oldContainerSize!.height
                let outerContainerAspectRatio = outerContainerSize.width / outerContainerSize.height
                
                if (outerContainerAspectRatio >= innerContainerAspectRatio) {
                
                    // remove offset
                    self._dyConstraint.constant = 0
                    
                } else {
                    
                    // recalculate offset
                    let newInnerContainerSize = previewLayer.layerRectConverted(fromMetadataOutputRect: CGRect(x: 0, y: 0, width: 1, height: 1))
                    
                    let newOffset = previewLayer.layerPointConverted(
                            fromCaptureDevicePoint: CGPoint(x: 0, y: 0)).y
                    
                    // update constraints
                    self._dyConstraint.constant = -newOffset
                    
                    // if the new size is different
                    if (newInnerContainerSize != self._innerContainerSize) {
                        // save the new values
                        self._innerContainerSize = newInnerContainerSize
                        self._lastOffset = newOffset
                    }
                }
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
