import Foundation
import UIKit


public class CameraFeedView: UIView {

    private let _capturePreview = CaptureVideoPreviewView()
    private var _dxConstraint: NSLayoutConstraint!
    private var _dyConstraint: NSLayoutConstraint!
    private var _innerContainerSize: CGRect!
    private var _lastOffset: CGFloat!
    private var _previewLayerRectConverted: CGRect!
    private var _additionalTopOffset: CGFloat! = 0
    
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
        previewLayer.backgroundColor = UIColor.purple.cgColor
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
                self._dyConstraint.constant = -self._lastOffset + self._additionalTopOffset
                
                // Update preview layer converted rect anytime the subviews layout changes
                self.updatePreviewLayerRectConverted()
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
                    self._dyConstraint.constant = -newOffset + self._additionalTopOffset
                    
                    // if the new size is different
                    if (newInnerContainerSize != self._innerContainerSize) {
                        // save the new values
                        self._innerContainerSize = newInnerContainerSize
                        self._lastOffset = newOffset
                    }
                }
                
                // Update preview layer converted rect anytime the subviews layout changes
                self.updatePreviewLayerRectConverted()
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
    
    /*
        Calculate the Rect of the layerPointConverted coordinate system for the capturePreview preview layer.
        This is used when converting CGPoints from their native image coordinates to coordinates relative to the preview layer
     */
    private func updatePreviewLayerRectConverted() {
        let previewLayer = _capturePreview.previewLayer
        if(previewLayer.frame.width != 0 && previewLayer.frame.height != 0) {
            
            // Get all 4 points of the coordinate system where (0,0) is bottom right and (1,1) is top left
            let topLeft = previewLayer.layerPointConverted(fromCaptureDevicePoint: CGPoint(x: 1, y: 1))
            let topRight = previewLayer.layerPointConverted(fromCaptureDevicePoint: CGPoint(x: 1, y: 0))
            let bottomLeft = previewLayer.layerPointConverted(fromCaptureDevicePoint: CGPoint(x: 0, y: 1))
            let bottomRight = previewLayer.layerPointConverted(fromCaptureDevicePoint: CGPoint(x: 0, y: 0))

            _previewLayerRectConverted = CGRect(x: topLeft.x,
                                                y: topLeft.y,
                                                width: (topRight.x - topLeft.x),
                                                height: (bottomLeft.y - topLeft.y))
        }
    }
    
    /*
     * Translates a given Rect to be relative to the camera capture preview
     */
    public func translateImagePointToPreviewLayer(forPoint point: CGPoint, relativeTo size: CGSize) -> CGPoint {
        let previewLayer = _capturePreview.previewLayer
        
        /*
            Since the image captured will have its X,Y coordinated flipped
            [(0,0) -> BottomLeft coordinate on native image translates to (0,1) -> BottomRight coordinate of preview layer coordinate system and vice versa]
            need to flip relative point calculations
         */
        let relativePoint = CGPoint(x: point.y / size.height, y: point.x / size.width)

        // Set up transform to account for the Y offset as well as translate the X coordinate as image captured from captureDevice is flipped
        let transform = CGAffineTransform.identity
            .scaledBy(x: -1, y: 1)
            .translatedBy(x: -_previewLayerRectConverted.width, y: self._dyConstraint.constant)

        // Convert the point from the capture device coordinate system to the previewLayer's
        let translatedPoint = previewLayer.layerPointConverted(fromCaptureDevicePoint: relativePoint)
        
        // Apply the transform on the translated point
        return translatedPoint.applying(transform)
        
    }
    
    /*
     * Summary: Translates a given Rect to be relative to the camera capture preview
     */
    public func translateRectInPreview(rect: CGRect) -> CGRect {
        // Modify the origin of the rect by the offset calculated for the CamereFeedView
        return CGRect(x: rect.origin.x,
                      y: rect.origin.y - self._dyConstraint.constant,
                      width: rect.width,
                      height: rect.height)
    }
    
    /*
        Adds an additional offset from the top by the given amount
        Caller may show a banner/view on top of screen, need to add offset of added view height
        so camera feed doesn't display under the newly added view
    */
    public func setAdditionalTopOffsetAmount(By amount: CGFloat) {
        
        // Saves the additional top offset and triggers layout
        _additionalTopOffset = amount;
        setNeedsLayout()
        layoutIfNeeded()
    }
    
    public func getYOffset() -> CGFloat {
        return _capturePreview.previewLayer.layerPointConverted(
            fromCaptureDevicePoint: CGPoint(x: 0, y: 0)).y
    }
}
