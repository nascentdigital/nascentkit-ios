//
//  VisionController.swift
//  CameraVision
//
//  Created by Simeon de Dios on 2018-10-26.
//  Copyright © 2018 Nascent Digital. All rights reserved.
//

import UIKit
import AVKit
import NascentKit
import RxSwift
import Firebase


class VisionController: UIViewController {

    enum BarcodeType: String {
        case CertificateNo = "CertificateNo"
        case DateOfBirth = "DateOfBirth"
        case Invalid = "Invalid"
    }
    
    let X_VALID_MARGIN: Int = 5
    let Y_VALID_MARGIN: Int = 20
    
    
    @IBOutlet weak var _cameraPreview: CameraFeedView!
    @objc @IBOutlet weak var _takePhotoButton: UIButton!
    @IBOutlet weak var _certificateLabel: UILabel!
    var _barcodeReaderView: UIView!
    var _promptLabel: UILabel!
    
    private let _cameraFeed = CameraFeed()
    private var _cameraDirection = AVCaptureDevice.Position.back
    
    private var _takePhotoObserver: NSKeyValueObservation?
    private var barcodeDetector: VisionBarcodeDetector!
    private let _disposeBag = DisposeBag()
    private var _nativeImageHeight: CGFloat?
    private var _nativeImageWidth: CGFloat?
    private var _imageXOffset: Int!
    private var _imageYOffset: Int!
    
    override func viewDidLoad() {
        
        // call base implementation
        super.viewDidLoad()
        
        // Setup prompt label and the view to read Barcode
        _barcodeReaderView = UIView(frame: CGRect(x: 10, y: 400, width: 250, height: 70))
        _promptLabel = UILabel(frame: CGRect(x: 10, y: self.view.frame.height - 150, width: self.view.frame.width, height: 50))
        
        //Configure prompt label
        _promptLabel.textAlignment = NSTextAlignment.center
        _promptLabel.textColor = UIColor.red;
        _promptLabel.text = ""
        
        // Set certificate View properties
        _barcodeReaderView.layer.borderWidth = 1.0
        _barcodeReaderView.layer.borderColor = UIColor.black.cgColor
        _barcodeReaderView.layer.backgroundColor = UIColor.clear.cgColor
        
        // Add certificate view to cameraPreview
        self._cameraPreview.addSubview(_barcodeReaderView)
        self.view.addSubview(_promptLabel)
        
        // customize photo button to be round
        _takePhotoButton.layer.masksToBounds = false
        _takePhotoButton.layer.cornerRadius = _takePhotoButton.bounds.width / 2
        _takePhotoButton.layer.borderWidth = 2
        _takePhotoButton.layer.borderColor = UIColor.black.cgColor
        
        //Initialize barcode scanner
        let format = VisionBarcodeFormat.all
        let barcodeOptions = VisionBarcodeDetectorOptions(formats: format)
        
        var vision = Vision.vision()
        barcodeDetector = vision.barcodeDetector(options: barcodeOptions)
        
        // toggle photo button highlight
        _takePhotoObserver = observe(
            \VisionController._takePhotoButton.isHighlighted,
            options: [.new, .old]
        ) {
            [unowned self]
            object, change in
            
            let highlighted = change.newValue ?? false
            self._takePhotoButton.layer.opacity = highlighted
                ? 0.5
                : 1.0
        }
        
        _cameraFeed.videoSamples
            .throttle(2, scheduler: ConcurrentMainScheduler.instance)
            .subscribe(
                onNext: {
                    [unowned self]
                    image in
                    
//                    // Modify the Image returned via the video to correct width/height of the camera preview view
//                    UIGraphicsBeginImageContext(CGSize(width: self._cameraPreview.frame.width, height: self._cameraPreview.frame.height))
//                    image.draw(in: CGRect(x: 0, y: 0, width: self._cameraPreview.frame.width, height: self._cameraPreview.frame.height))
//                    // Save newly formatted image to be used in further analysis
//                    let newImage = UIGraphicsGetImageFromCurrentImageContext()
                    
                    let _visionImage = VisionImage(image: image)
                    
                    // Set the native image Height / Width
                    if(self._nativeImageWidth == nil) {
                        self._nativeImageWidth = image.size.width
                    }
                    if(self._nativeImageHeight == nil) {
                        self._nativeImageHeight = image.size.height
                    }
                    

                    self.barcodeDetector.detect(in: _visionImage) {
                        features, error in
                        
                        guard error == nil, let features = features, !features.isEmpty else {
                            self._promptLabel.text = "No full barcode within view"
                            return
                        }
                        
                        for feature in features {
                            
                            /*
                                Date Barcode Raw Value: e.g 1991/04/29
                                CertificateNo Raw Value: e.g K9548487
                             */

                            // Check if barcode is within view
                            let validBarcode = self.isValidBarcodeInView(barcode: feature, containerView: self._barcodeReaderView)
                            if validBarcode {
                                let barcodeType = self.getBarcodeType(barcode: feature)
                                self._promptLabel.text?.append("Barcode type: \(barcodeType)")
                            } else {
                                self._promptLabel.text?.append("Invalid Barcode")
                            }
                        }
                        // ...
                    }
            },
                onError: {
                    error in
                    print("error")
            },
                onDisposed: {
                    UIGraphicsEndImageContext()
            }
        )
        .disposed(by: _disposeBag)
    }

    override func viewWillAppear(_ animated: Bool) {
    
        // call base implementation
        super.viewWillAppear(animated)

        // try to start camera feed + preview
        do {
        
            // start camera feed
            try _cameraFeed.start(cameraPosition: _cameraDirection)

            // start camera preview
            _cameraPreview.startPreview(cameraFeed: _cameraFeed)
        }
        
        catch {
            print("[VisionController] unexpected error: \(error)")
        }
        
    }
    
    override func viewWillDisappear(_ animated: Bool) {
    
        // stop camera preview
        _cameraPreview.stopPreview()

        // stop camera feed
        _cameraFeed.stop()
    
        // call base implementation
        super.viewWillAppear(animated)
    }
    
    func isValidBarcodeInView(barcode: VisionBarcode, containerView: UIView) -> Bool {
        var isValid = false
        let offsets = calculateImageOffset(barcode: barcode)
        
        // cornerPoints stores array of NSValue for each corner coordinate going clockwise starting from top left
        let barcodeTopLeft = barcode.cornerPoints![0]
        let barcodeBottomLeft = barcode.cornerPoints![3]
        let barcodeTopRight = barcode.cornerPoints![1]
        let barcodeBottomRight = barcode.cornerPoints![2]
        
//        print("Barcode Top Left X: \(barcodeTopLeft.cgPointValue.x * offsets.0)")
//        print("Barcode Top Left Y: \(barcodeTopLeft.cgPointValue.y * offsets.1)")

        //Get container view Origin point relative to the camera preview view
        let viewOriginX = containerView.frame.origin.x
        
        /*
            Reason for the +150, The container view (rectangle box) seems to be roughly ~150 units smaller than expected
            Currently not sure how to fix this, putting in hardcoded offset for now to test
         */
        let viewOriginY = containerView.frame.origin.y + 150
        
        let viewWidth = containerView.frame.size.width
        let viewHeight = containerView.frame.size.height
        
//        print("View Origin X: \(viewOriginX)")
//        print("View Origin Y: \(viewOriginY)")
        
        // If the barcode is above the container view
        if(barcodeTopRight.cgPointValue.y * offsets.1 < (viewOriginY + CGFloat(self.Y_VALID_MARGIN))) {
            self._promptLabel.text = "Move camera up"
        } else if (barcodeBottomLeft.cgPointValue.y * offsets.1 > (viewOriginY + viewHeight + CGFloat(self.Y_VALID_MARGIN))) {
            // If the barcode is below the container view
            self._promptLabel.text = "Move Camera Down"
        } else if (barcodeTopLeft.cgPointValue.x * offsets.0 < (viewOriginX + CGFloat(self.X_VALID_MARGIN))) {
            // If the barcode is to the left of the container view
            self._promptLabel.text = "Move Camera to the Left"
        } else if (barcodeTopRight.cgPointValue.x * offsets.0 > (viewOriginX + viewWidth + CGFloat(self.X_VALID_MARGIN))) {
            // If the barcode is to the right of the container view
            self._promptLabel.text = "Move Camera to the Right"
        } else {
            self._promptLabel.text = "Barcode within view :)"
            isValid = true
        }
        
        
        return isValid
    }
    
    func getBarcodeType(barcode: VisionBarcode) -> BarcodeType{
        let rawValue = barcode.rawValue
        if(rawValue == nil) {
            return BarcodeType.Invalid
        }
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy/MM/dd"
        guard let date = dateFormatter.date(from: rawValue!) else {
            // Its not a valid date , check if its a Certificate Number
            // TODO: This isnt always a certificate No. Need criteria to classify string as certificate No or not
            return BarcodeType.CertificateNo
        }
        
        // Return valid Date of Birth Barcode Type
        return BarcodeType.DateOfBirth
        
    }
    
    
    /*
        Calculate the percent difference of image width/heigh vs the camera preview witdh/height
        Use offset to convert cornerPoints of barcodes to proper view scale
     */
    func calculateImageOffset(barcode: VisionBarcode) -> (CGFloat, CGFloat) {
        
        // Width and height of the camera preview
        let previewWidth = self._cameraPreview.frame.width
        let previewHeight = self._cameraPreview.frame.height
        

        // Difference in width and height between the camera preview view and the native image containing the barcode
        let widthPercentDiff = Float32(previewWidth) / Float32(self._nativeImageWidth!)
        let heightPercentDiff = Float32(previewHeight) / Float32(self._nativeImageHeight!)
       
        return (CGFloat(widthPercentDiff), CGFloat(heightPercentDiff))
    }
    
    
    @IBAction func toggleCameraPosition() {
        
        // determine new camera position
        let cameraPosition = _cameraFeed.cameraPosition == .front
            ? AVCaptureDevice.Position.back
            : AVCaptureDevice.Position.front

        print("[VisionController] switching camera position to \(cameraPosition == .front ? "front" : "back")")

        // swap to new position
        do {
            try _cameraFeed.start(cameraPosition: cameraPosition)
        }
        catch {
            print("[VisionController] error switching camera position: \(error)")
        }
    }
    
    @IBAction func takePhoto() {
    
        print("[VisionController] taking photo")
    }
}
