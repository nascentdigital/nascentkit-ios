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


extension UIImage {
    func fixedOrientation() -> UIImage? {
        
        guard imageOrientation != UIImage.Orientation.up else {
            //This is default orientation, don't need to do anything
            return self.copy() as? UIImage
        }
        
        guard let cgImage = self.cgImage else {
            //CGImage is not available
            return nil
        }
        
        guard let colorSpace = cgImage.colorSpace, let ctx = CGContext(data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: cgImage.bitsPerComponent, bytesPerRow: 0, space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return nil //Not able to create CGContext
        }
        
        var transform: CGAffineTransform = CGAffineTransform.identity
        
        switch imageOrientation {
        case .down, .downMirrored:
            transform = transform.translatedBy(x: size.width, y: size.height)
            transform = transform.rotated(by: CGFloat.pi)
            break
        case .left, .leftMirrored:
            transform = transform.translatedBy(x: size.width, y: 0)
            transform = transform.rotated(by: CGFloat.pi / 2.0)
            break
        case .right, .rightMirrored:
            transform = transform.translatedBy(x: 0, y: size.height)
            transform = transform.rotated(by: CGFloat.pi / -2.0)
            break
        case .up, .upMirrored:
            break
        }
        
        //Flip image one more time if needed to, this is to prevent flipped image
        switch imageOrientation {
        case .upMirrored, .downMirrored:
            transform.translatedBy(x: size.width, y: 0)
            transform.scaledBy(x: -1, y: 1)
            break
        case .leftMirrored, .rightMirrored:
            transform.translatedBy(x: size.height, y: 0)
            transform.scaledBy(x: -1, y: 1)
        case .up, .down, .left, .right:
            break
        }
        
        ctx.concatenate(transform)
        
        switch imageOrientation {
        case .left, .leftMirrored, .right, .rightMirrored:
            ctx.draw(self.cgImage!, in: CGRect(x: 0, y: 0, width: size.height, height: size.width))
        default:
            ctx.draw(self.cgImage!, in: CGRect(x: 0, y: 0, width: size.width, height: size.height))
            break
        }
        
        guard let newCGImage = ctx.makeImage() else { return nil }
        return UIImage.init(cgImage: newCGImage, scale: 1, orientation: .up)
    }
}

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
    var shouldScan: Bool = true;
    
    
    @IBOutlet weak var _cameraPreview: CameraFeedView!
    @IBOutlet weak var _certificateLabel: UILabel!
    var _certificateBarcodeReader: UIView!
    var _birthdayBarcodeReader: UIView!
    var certificateBarcodeLabel: UILabel!
    var birthdayBarcodeLabel: UILabel!
    var _promptLabel: UILabel!
    
    var statusView: UIView!
    
    private let _cameraFeed = CameraFeed()
    private var _cameraDirection = AVCaptureDevice.Position.back
    
    private var _takePhotoObserver: NSKeyValueObservation?
    private var barcodeDetector: VisionBarcodeDetector!
    private let _disposeBag = DisposeBag()
    private var _nativeImageSize: CGSize?
    private var _imageXOffset: Int!
    private var _imageYOffset: Int!
    
    override func viewDidLoad() {
        
        // call base implementation
        super.viewDidLoad()
        
        //Setup status view to prompt the user of any issues
        let statusRect = CGRect(x: 0, y: 0, width: self.view.frame.width, height: 50)
        statusView = UIView(frame: statusRect)
        statusView.layer.backgroundColor = UIColor.blue.cgColor
        self._cameraPreview.setAdditionalTopOffsetAmount(By: statusRect.height)
        self._cameraPreview.addSubview(statusView)
        
    }

    override func viewDidLayoutSubviews() {
        super.viewWillLayoutSubviews()

        
        let previewFrame = self._cameraPreview.frame
        
        /*  Each barcode reader view will be 50% of total view width minus padding
            5 padding from border on either side + 20 adding between both rects = 30
         */
        let barcodeRectWidth = (self._cameraPreview.frame.width - 30) / 2
        let barcodeRectHeight: CGFloat = 40
        
        let yOffset: CGFloat = (previewFrame.origin.y + (barcodeRectHeight / 2))
        
        // Setup rects for both barcode reader views
        let certificateBarcodeRect = CGRect(x: previewFrame.origin.x + 5,
                                           y: (previewFrame.height - previewFrame.origin.y) - yOffset,
                                           width: barcodeRectWidth,
                                           height: barcodeRectHeight)
        
        let birthdayBarcodeRect = CGRect(x: (certificateBarcodeRect.origin.x + barcodeRectWidth) + 20,
                                         y:(previewFrame.height - previewFrame.origin.y) - yOffset,
                                         width: barcodeRectWidth,
                                         height: barcodeRectHeight)
        
        _certificateBarcodeReader = UIView(frame: certificateBarcodeRect)
        _birthdayBarcodeReader = UIView(frame: birthdayBarcodeRect)

        _promptLabel = UILabel(frame: CGRect(x: 10, y: 5, width: self.statusView.frame.width - 20, height: self.statusView.frame.height))
        
        //Configure prompt label
        _promptLabel.contentMode = .scaleToFill
        _promptLabel.textColor = UIColor.white;
        _promptLabel.numberOfLines = 0
        _promptLabel.text = ""
        _promptLabel.font = UIFont(name: "AppleSDGothicNeo-Thin", size: 12)
        _promptLabel.layer.zPosition = 1
        
        //Configure Barcode Label
        certificateBarcodeLabel = UILabel(frame: CGRect(x: certificateBarcodeRect.origin.x,
                                              y: certificateBarcodeRect.origin.y - 20,
                                              width: certificateBarcodeRect.size.width,
                                              height: 15))
        
        certificateBarcodeLabel.contentMode = .scaleToFill
        certificateBarcodeLabel.textColor = UIColor.white
        certificateBarcodeLabel.font = UIFont(name: "AppleSDGothicNeo-Thin", size: 16)
        certificateBarcodeLabel.text = "Barcode"
        certificateBarcodeLabel.layer.zPosition = 1
        
        // Copy over certificate label and change origin x for birthday
        birthdayBarcodeLabel = UILabel(frame: CGRect(x: birthdayBarcodeRect.origin.x,
                                                        y: birthdayBarcodeRect.origin.y - 20,
                                                        width: birthdayBarcodeRect.size.width,
                                                        height: 15))
        
        birthdayBarcodeLabel.contentMode = .scaleToFill
        birthdayBarcodeLabel.textColor = UIColor.white
        birthdayBarcodeLabel.font = UIFont(name: "AppleSDGothicNeo-Thin", size: 16)
        birthdayBarcodeLabel.text = "Barcode"
        birthdayBarcodeLabel.layer.zPosition = 1
        
        // Set certificate and birthday View properties
        _certificateBarcodeReader.layer.borderWidth = 1.0
        _certificateBarcodeReader.layer.borderColor = UIColor.black.cgColor
        _certificateBarcodeReader.layer.backgroundColor = UIColor.clear.cgColor
        _certificateBarcodeReader.layer.zPosition = 1
        
        _birthdayBarcodeReader.layer.borderWidth = 1.0
        _birthdayBarcodeReader.layer.borderColor = UIColor.black.cgColor
        _birthdayBarcodeReader.layer.backgroundColor = UIColor.clear.cgColor
        _birthdayBarcodeReader.layer.zPosition = 1
        
        // Add certificate and birthday view to cameraPreview
        self._cameraPreview.addSubview(_certificateBarcodeReader)
        self._cameraPreview.addSubview(_birthdayBarcodeReader)
        self._cameraPreview.addSubview(certificateBarcodeLabel)
        self._cameraPreview.addSubview(birthdayBarcodeLabel)
        
        self.statusView.addSubview(_promptLabel)
        
        // Show initial status to prompt the user
        self.showStatusView(statusText: "Scanning document to validate. Please line up with guides", isError: false)
        initializeCameraFeedVideoSampler()
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
    
    private func initializeCameraFeedVideoSampler() {
        //Initialize barcode scanner
        let format = VisionBarcodeFormat.all
        let barcodeOptions = VisionBarcodeDetectorOptions(formats: format)
        
        var vision = Vision.vision()
        barcodeDetector = vision.barcodeDetector(options: barcodeOptions)
        
        _cameraFeed.videoSamples
                .throttle(3.5, scheduler: ConcurrentMainScheduler.instance)
                .subscribe(
                    onNext: {
                        [unowned self]
                        image in
                        self.showStatusView(statusText: "Attempting to capture image", isError: false)
                        if(!self.shouldScan) {
                            
                            return
                        }
                        let _visionImage = VisionImage(image: image)
                        self.barcodeDetector.detect(in: _visionImage) {
                            features, error in
                            
                            guard error == nil, let features = features, !features.isEmpty else {
                                self.showStatusView(statusText: "No full barcode within view", isError: true)
                                return
                            }
                            
                            if(features.count != self.NUM_OF_BARCODES) {
                                self.showStatusView(statusText: "Please have both barcodes clearly visible in camera", isError: true)
                                return
                            }
                            
                            // Flag to determin if any read barcode is invalid / can't be read
                            var isValid = true
                            var statusText: String = ""
                            
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
                                if !validBarcode.isValid {
                                    // If any of the barcodes fail, false flag
                                    isValid = false
                                    statusText = validBarcode.statusText
                                }
                            }
                            
                            // Both Barcodes were read successfully
                            if(isValid) {
                                statusText = "Yay both barcodes read!"
                                self.takeImagePhoto()
                            }
                            self.showStatusView(statusText: statusText, isError: !isValid)
                        }
                    },
                    onError: {
                        error in
                        print("error")
                }
                )
                .disposed(by: self._disposeBag)
 
    }
    
    private func takeImagePhoto(){
        self._cameraFeed.takePhoto()
            .subscribeOn(ConcurrentMainScheduler.instance)
            .subscribe(onSuccess: {
                [unowned self]
                image in
                
                if let fixedImage = image.fixedOrientation() {
                    self.showStatusView(statusText: "Successfully captured Photo", isError: false)
                    self.shouldScan = false;
                    self.readImageText(image: fixedImage)
                }
            }, onError: {
                error in
                print("Capture photo error \(error)")
                self.showStatusView(statusText: "Capture Photo Error: \(error)", isError: true)
            })
    }
    
    private func readImageText(image: UIImage) {
        let vision = Vision.vision()
        
        let textRecognizer = vision.onDeviceTextRecognizer()
        
        let image = VisionImage(image: image)
        
        textRecognizer.process(image) {
            [unowned self]
            result, error in
            guard error == nil, let result = result else {
                
                return
            }
            
            for block in result.blocks {
                print("Block: \(block.text)")
            }
        }
        
    }
    
    private func isValidBarcodeInView(barcode: VisionBarcode, barcodeType: BarcodeType, containerView: UIView, imageSize: CGSize) -> (isValid: Bool, statusText: String) {
        // Initialize valid flag as false
        var isValid = false
        var statusText: String = ""
        
        let barcodeTopLeft = _cameraPreview.translateImagePointToPreviewLayer(forPoint: barcode.cornerPoints![0].cgPointValue, relativeTo: imageSize)
        let barcodeBottomLeft = _cameraPreview.translateImagePointToPreviewLayer(forPoint: barcode.cornerPoints![3].cgPointValue, relativeTo: imageSize)
        let barcodeTopRight = _cameraPreview.translateImagePointToPreviewLayer(forPoint: barcode.cornerPoints![1].cgPointValue, relativeTo: imageSize)
        let barcodeBottomRight = _cameraPreview.translateImagePointToPreviewLayer(forPoint: barcode.cornerPoints![2].cgPointValue, relativeTo: imageSize)

        //Get container view Origin point relative to the camera preview view
        let viewOriginX = containerView.frame.origin.x
        let viewOriginY = containerView.frame.origin.y
        
        let viewWidth = containerView.frame.size.width
        let viewHeight = containerView.frame.size.height
        
        // If the barcode is above the container view
        if(barcodeBottomLeft.y < (viewOriginY - CGFloat(self.Y_VALID_MARGIN))) {
            statusText = "Move camera up"
        } else if (barcodeBottomLeft.y > (viewOriginY + viewHeight + CGFloat(self.Y_VALID_MARGIN))) {
            // If the barcode is below the container view
            statusText = "Move Camera Down"
        } else if (barcodeBottomLeft.x < (viewOriginX + CGFloat(self.X_VALID_MARGIN))) {
            // If the barcode is to the left of the container view
            statusText = "Move Camera to the Left"
        } else if (barcodeTopRight.x > (viewOriginX + viewWidth + CGFloat(self.X_VALID_MARGIN))) {
            // If the barcode is to the right of the container view
            statusText = "Move Camera to the Right"
        } else {
            // Barcode is within the correct container, yay
            isValid = true
        }
        
        return (isValid, statusText)
    }
    
    private func getBarcodeType(barcode: VisionBarcode) -> BarcodeType{
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
    
    private func showStatusView(statusText: String, isError: Bool) {
        
        if(isError) {
            self.statusView.layer.backgroundColor = UIColor.red.cgColor
        } else {
            self.statusView.layer.backgroundColor = UIColor(red: 0, green: 0.5294, blue: 1, alpha: 1.0).cgColor
        }
        
        self._promptLabel?.text = statusText
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
