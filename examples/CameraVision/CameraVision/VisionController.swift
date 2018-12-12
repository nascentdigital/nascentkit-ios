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
    
    enum BarcodeTypeId: Int {
        case CertificateNo = 1
        case DateOfBirth = 2
        case Invalid = -1
    }
    
    let X_VALID_MARGIN: Int = 5
    let Y_VALID_MARGIN: Int = 5
    let NUM_OF_BARCODES: Int = 2
    
    @IBOutlet weak var _cameraPreview: CameraFeedView!
    @objc @IBOutlet weak var _takePhotoButton: UIButton!
    @IBOutlet weak var _certificateLabel: UILabel!
    var _certificateBarcodeReader: UIView!
    var _birthdayBarcodeReader: UIView!
    var _promptLabel: UILabel!
    
    private let _cameraFeed = CameraFeed()
    private var _cameraDirection = AVCaptureDevice.Position.back
    
    private var _takePhotoObserver: NSKeyValueObservation?
    private var barcodeDetector: VisionBarcodeDetector!
    private let _disposeBag = DisposeBag()
    private var _nativeImageHeight: CGFloat?
    private var _nativeImageWidth: CGFloat?
    private var _nativeImageSize: CGSize?
    private var _imageXOffset: Int!
    private var _imageYOffset: Int!
    
    override func viewDidLoad() {
        
        // call base implementation
        super.viewDidLoad()

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
                        
                        if(features.count != self.NUM_OF_BARCODES) {
                            self._promptLabel.text = "Please have both barcodes clearly visible \n in camera"
                            return
                        }
                        
                        // Flag to determin if any read barcode is invalid / can't be read
                        var isValid = true
                        
                        /*
                         Date Barcode Raw Value: e.g 1991/04/29
                         CertificateNo Raw Value: e.g K9548487
                         */
                        for feature in features {
                            // If an invalid barcode was scanned, no need to continue
                            if (!isValid) {
                                break
                            }
                            
                            // Figure out which container the barcode belongs to
                            let barcodeTopLeft =  self._cameraPreview.translateImagePointToPreviewLayer(forPoint: feature.cornerPoints![0].cgPointValue, relativeTo: image.size)
                            var _containerView: UIView!
                            
                            // If the top left of the barcode is further past the right border of the the certificate view, assume barcode is for DoB
                            if(barcodeTopLeft.x > self._certificateBarcodeReader.frame.origin.x + self._certificateBarcodeReader.frame.width) {
                                _containerView = self._birthdayBarcodeReader
                            } else {
                                // Otherwise assume barcode is for Certificate No
                                _containerView = self._certificateBarcodeReader
                            }
                            
                            let barcodeType = self.getBarcodeType(barcode: feature)
                            // Check if barcode is within view
                            let validBarcode = self.isValidBarcodeInView(barcode: feature, barcodeType: barcodeType, containerView: _containerView, imageSize: image.size)
                            if validBarcode {
                                self._promptLabel.text?.append("\n Barcode type: \(barcodeType)")
                            } else {
                                // If any of the barcodes fail, false flag
                                isValid = false
                            }
                        }
                        
                        // Both Barcodes were read successfully
                        if(isValid) {
                            self._promptLabel.text? = "Yay both barcodes read!"
                            
                        }
                    }
            },
                onError: {
                    error in
                    print("error")
            }
        )
        .disposed(by: _disposeBag)
    }

    override func viewDidLayoutSubviews() {
        super.viewWillLayoutSubviews()

        // Setup rects for both barcode reader views
        let certificatBarcodeRect = CGRect(x: 10, y: 450, width: 150, height: 40)
        let birthdayBarcodeRect = CGRect(x: 210, y:450, width: 150, height: 40)
        
        _certificateBarcodeReader = UIView(frame: certificatBarcodeRect)
        _birthdayBarcodeReader = UIView(frame: birthdayBarcodeRect)
        
        _promptLabel = UILabel(frame: CGRect(x: 10, y: self.view.frame.height - 200, width: self.view.frame.width, height: 50))
        
        //Configure prompt label
        _promptLabel.textAlignment = NSTextAlignment.center
        _promptLabel.textColor = UIColor.red;
        _promptLabel.numberOfLines = 0
        _promptLabel.text = ""
        
        // Set certificate and birthday View properties
        _certificateBarcodeReader.layer.borderWidth = 1.0
        _certificateBarcodeReader.layer.borderColor = UIColor.black.cgColor
        _certificateBarcodeReader.layer.backgroundColor = UIColor.clear.cgColor
        
        _birthdayBarcodeReader.layer.borderWidth = 1.0
        _birthdayBarcodeReader.layer.borderColor = UIColor.black.cgColor
        _birthdayBarcodeReader.layer.backgroundColor = UIColor.clear.cgColor
        
        // Add certificate and birthday view to cameraPreview
        self._cameraPreview.addSubview(_certificateBarcodeReader)
        self._cameraPreview.addSubview(_birthdayBarcodeReader)
        
        self.view.addSubview(_promptLabel)
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
    
    func isValidBarcodeInView(barcode: VisionBarcode, barcodeType: BarcodeType, containerView: UIView, imageSize: CGSize) -> Bool {
        // Initialize valid flag as false
        var isValid = false
        
        let barcodeTopLeft = _cameraPreview.translateImagePointToPreviewLayer(forPoint: barcode.cornerPoints![0].cgPointValue, relativeTo: imageSize)
        let barcodeBottomLeft = _cameraPreview.translateImagePointToPreviewLayer(forPoint: barcode.cornerPoints![3].cgPointValue, relativeTo: imageSize)
        let barcodeTopRight = _cameraPreview.translateImagePointToPreviewLayer(forPoint: barcode.cornerPoints![1].cgPointValue, relativeTo: imageSize)
        let barcodeBottomRight = _cameraPreview.translateImagePointToPreviewLayer(forPoint: barcode.cornerPoints![2].cgPointValue, relativeTo: imageSize)

        // Rect around the scanned barcode
        let barcodeRect = CGRect(x: barcodeTopLeft.x, y: barcodeTopLeft.y, width: barcodeTopRight.x - barcodeTopLeft.x, height: barcodeBottomRight.y - barcodeTopRight.y)
        if(barcodeType == BarcodeType.DateOfBirth) {
            print("---- Date of Birth -----")
            print("Barcode Corner Points: \(String(describing: barcode.cornerPoints))")
            print("Top Left: \(barcodeTopLeft)")
            print("Bottom Left: \(barcodeBottomLeft)")
            print("Top Right: \(barcodeTopRight)")
            print("Bottom Right: \(barcodeBottomRight)")

            print("Barcode Type: \(barcodeType), Rect: \(barcodeRect)")

        } else {
            print("---- Certificate No -----")
            print("Barcode Corner Points: \(String(describing: barcode.cornerPoints))")
            print("Top Left: \(barcodeTopLeft)")
            print("Bottom Left: \(barcodeBottomLeft)")
            print("Top Right: \(barcodeTopRight)")
            print("Bottom Right: \(barcodeBottomRight)")
            
            print("Barcode Type: \(barcodeType), Rect: \(barcodeRect)")

        }
        
        let barcodeView = UIView(frame: barcodeRect)
        
        // Remove old barcode view from camera preview
        let id = barcodeType == BarcodeType.CertificateNo ? BarcodeTypeId.CertificateNo.rawValue : BarcodeTypeId.DateOfBirth.rawValue
        if let oldBarcodeView = self._cameraPreview.viewWithTag(id) {
            oldBarcodeView.removeFromSuperview()
        }
        
        // Set barcode tag and props
        barcodeView.tag = id
        barcodeView.layer.borderWidth = 2
        barcodeView.layer.borderColor = UIColor.blue.cgColor
        
        // Add barcode rect view onto the camera preview
        self._cameraPreview.addSubview(barcodeView)
        
        //Get container view Origin point relative to the camera preview view
        let viewOriginX = containerView.frame.origin.x
        let viewOriginY = containerView.frame.origin.y
        
        let viewWidth = containerView.frame.size.width
        let viewHeight = containerView.frame.size.height
        
        // If the barcode is above the container view
        if(barcodeBottomLeft.y < (viewOriginY - CGFloat(self.Y_VALID_MARGIN))) {
            self._promptLabel.text = "Move \(barcodeType) camera up"
        } else if (barcodeBottomLeft.y > (viewOriginY + viewHeight + CGFloat(self.Y_VALID_MARGIN))) {
            // If the barcode is below the container view
            self._promptLabel.text = "Move \(barcodeType) Camera Down"
        } else if (barcodeBottomLeft.x < (viewOriginX + CGFloat(self.X_VALID_MARGIN))) {
            // If the barcode is to the left of the container view
            self._promptLabel.text = "Move \(barcodeType) Camera to the Left"
        } else if (barcodeTopRight.x > (viewOriginX + viewWidth + CGFloat(self.X_VALID_MARGIN))) {
            // If the barcode is to the right of the container view
            self._promptLabel.text = "Move \(barcodeType) Camera to the Right"
        } else {
            // Barcode is within the correct container, yay
            isValid = true
        }
        
        return isValid
    }
    
    func getBarcodeType(barcode: VisionBarcode) -> BarcodeType{
        let rawValue = barcode.rawValue
        // If no value can be read, return invalid type
        if(rawValue == nil) {
            return BarcodeType.Invalid
        }
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy/MM/dd"
        guard dateFormatter.date(from: rawValue!) != nil else {
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
    func getImagePointOffset(barcodePoint: CGPoint) -> CGPoint {
        
        // Width and height of the camera preview
        let previewWidth = self._cameraPreview.frame.width
        let previewHeight = self._cameraPreview.frame.height
        

        // Difference in width and height between the camera preview view and the native image containing the barcode
        let widthPercentDiff = Float32(previewWidth) / Float32(self._nativeImageWidth!)
        let heightPercentDiff = Float32(previewHeight) / Float32(self._nativeImageHeight!)
       
        return CGPoint(x: barcodePoint.x * CGFloat(widthPercentDiff), y: barcodePoint.y * CGFloat(heightPercentDiff))
        
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
