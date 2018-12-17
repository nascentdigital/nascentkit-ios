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

enum StatusColors {
    case infoColor
    case successColor
    case errorColor
}
enum StatusIcons {
    case infoIcon
    case successIcon
    case errorIcon
}

extension StatusColors {
    var value: UIColor {
        get {
            switch self {
            case .infoColor :
                return UIColor(red: 5/255, green: 31/255, blue: 65/255, alpha: 1)
            case .successColor:
                return UIColor(red: 5/255, green: 74/255, blue: 170/255, alpha: 1)
            case .errorColor:
                return UIColor(red: 196/255, green: 22/255, blue: 133/255, alpha: 1)
            default:
                return UIColor.clear
            }
        }
    }
}

extension StatusIcons {
    var value: UIImage {
        get {
            switch self {
            case .infoIcon:
                return UIImage(named: "info.png")!
            case .successIcon:
                return UIImage(named: "Success.png")!
            case .errorIcon:
                return UIImage(named: "Error.png")!
            }
        }
    }
}

// Extension to get user friendly full name of barcode
extension BarcodeType {
    var name: String {
        get {
            switch self {
            case .CertificateNo:
                return "Certificate No."
            case .DateOfBirth:
                return "Date of Birth"
            case .Invalid:
                return "Invalid"
            default:
                return ""
            }
        }
    }
}


class VisionController: UIViewController {

    let X_VALID_MARGIN: Int = 5
    let Y_VALID_MARGIN: Int = 5
    let NUM_OF_BARCODES: Int = 2
    let MANUAL_SCAN_WAIT_TIME = 5.0
    
    @IBOutlet weak var _cameraPreview: CameraFeedView!
    @IBOutlet weak var _certificateLabel: UILabel!
    var _certificateBarcodeReader: UIView!
    var _birthdayBarcodeReader: UIView!
    var certificateBarcodeLabel: UILabel!
    var birthdayBarcodeLabel: UILabel!
    var _promptLabel: UILabel!
    
    @IBOutlet weak var scanButton: UIButton!
    
    var statusView: UIView!
    
    private let _cameraFeed = CameraFeed()
    private var _cameraDirection = AVCaptureDevice.Position.back
    
    private var _takePhotoObserver: NSKeyValueObservation?
    private var barcodeDetector: VisionBarcodeDetector!
    private let _disposeBag = DisposeBag()
    private var _nativeImageSize: CGSize?
    private var _imageXOffset: Int!
    private var _imageYOffset: Int!
    
    private var needValuesFrom = (barcode: true, ocr: true)
    private var finalFullImage: UIImage?
    
    override func viewDidLoad() {
        
        // call base implementation
        super.viewDidLoad()
        
        // Hide scan button on first load until user doesnt take proper photo
        self.scanButton.isHidden = true
        
        // self.view.backgroundColor = UIColor(patternImage: UIImage(named: "background.png")!)
        self.view.layer.contents = UIImage(named: "background.png")?.cgImage
        
        //Setup status view to prompt the user of any issues
        let statusRect = CGRect(x: 0, y: 0, width: self.view.frame.width, height: 50)
        statusView = UIView(frame: statusRect)
        statusView.layer.backgroundColor = StatusColors.infoColor.value.cgColor
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
        
        // Setup rects for both barcode reader views
        let certificateBarcodeRect = CGRect(x: previewFrame.origin.x + 5,
                                           y: (previewFrame.height - previewFrame.origin.y),
                                           width: barcodeRectWidth,
                                           height: barcodeRectHeight)
        
        let birthdayBarcodeRect = CGRect(x: (certificateBarcodeRect.origin.x + barcodeRectWidth) + 20,
                                         y:(previewFrame.height - previewFrame.origin.y),
                                         width: barcodeRectWidth,
                                         height: barcodeRectHeight)
        
        _certificateBarcodeReader = UIView(frame: certificateBarcodeRect)
        _birthdayBarcodeReader = UIView(frame: birthdayBarcodeRect)

        _promptLabel = UILabel(frame: CGRect(x: 50, y: 0, width: self.statusView.frame.width - 20, height: self.statusView.frame.height))
        
        //Configure prompt label
        _promptLabel.contentMode = .scaleToFill
        _promptLabel.textColor = UIColor.white;
        _promptLabel.numberOfLines = 0
        _promptLabel.text = ""
        _promptLabel.font = UIFont(name: "AppleSDGothicNeo-Thin", size: 14)
        _promptLabel.layer.zPosition = 1
        
        // Configure the Scan button
        scanButton.layer.cornerRadius = 20
        scanButton.layer.backgroundColor = UIColor(red: 4/255, green: 26/255, blue: 55/255, alpha: 1).cgColor
        scanButton.setTitleColor(UIColor.white, for: .normal)
        view.bringSubviewToFront(scanButton)
        
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
        self.showStatusView(statusText: "Scanning document to validate. \nPlease line up with guides", isError: false)
        
        // Delay to start the camera feed

        self.initializeCameraFeedVideoSampler()
        self.initiateScanButtonHelper()
    }
    
    override func viewWillAppear(_ animated: Bool) {
    
        // call base implementation
        super.viewWillAppear(animated)

        // try to start camera feed + preview
        do {
        
            // start camera feed
            try _cameraFeed.start(cameraPosition: _cameraDirection)
            
            // start camera preview
            _cameraPreview.startPreview(cameraFeed: _cameraFeed, videoGravity: AVLayerVideoGravity.resizeAspectFill)
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
                .throttle(3.5, scheduler: SerialDispatchQueueScheduler(qos: .userInitiated))
                .subscribe(
                    onNext: {
                        [unowned self]
                        image in
                        if(!self.needValuesFrom.barcode) {
                            return
                        }
                        self.detectBarcodeInImage(image: image)
                    },
                    onError: {
                        error in
                        print("error")
                }
                )
                .disposed(by: self._disposeBag)
 
    }
    
    private func detectBarcodeInImage(image: UIImage) {
        let visionImage = VisionImage(image: image)
        self.barcodeDetector.detect(in: visionImage) {
            features, error in
            
            guard error == nil, let features = features, !features.isEmpty else {
                // self.showStatusView(statusText: "No full barcode within view", isError: true)
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
                } else if (!self.needValuesFrom.ocr) {
                    // If a picture was taken and there are 2 barcodes detected, No need to check if barcodes within bounds of barcode views
                    isValid = true
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
                
                // If both barcodes havn't been picked up, prompt the user of the missing barcode
                if(features.count != self.NUM_OF_BARCODES) {
                    let missingBarcode = barcodeType == BarcodeType.CertificateNo ? BarcodeType.DateOfBirth.name : BarcodeType.CertificateNo.name
                    self.showStatusView(statusText: "One barcode detected. \nPlease move document so \(missingBarcode) is in view", isError: false)
                    return
                }
                
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
                self.needValuesFrom.barcode = false
                if(self.needValuesFrom.ocr) {
                    self.takeImagePhoto()
                } else {
                    self.finalFullImage = image
                }
            }
            self.showStatusView(statusText: statusText, isError: !isValid)
        }
    }
    
    private func takeImagePhoto(){
        self._cameraFeed.takePhoto()
            .subscribeOn(ConcurrentMainScheduler.instance)
            .subscribe(onSuccess: {
                [unowned self]
                image in
                
                if let fixedImage = image.fixedOrientation() {
                    self.showStatusView(statusText: "Successfully captured Photo", isError: false)
                    self.readImageText(image: fixedImage)
                    self.needValuesFrom.ocr = false
                    if(self.needValuesFrom.barcode) {
                        self.detectBarcodeInImage(image: fixedImage)
                    } else {
                        self.finalFullImage = fixedImage
                    }
                    
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
            }
            self.needValuesFrom.ocr = false
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
        DispatchQueue.main.async {
            [weak self] in
            var icon: UIImage!
            if(isError) {
                self?.statusView.layer.backgroundColor = StatusColors.errorColor.value.cgColor
                icon = StatusIcons.errorIcon.value
            } else {
                self?.statusView.layer.backgroundColor = StatusColors.infoColor.value.cgColor
                // icon = StatusIcons.infoIcon.value
            }
            
            // Load icon to be displayed with text
            let iconAttachment = NSTextAttachment()
            iconAttachment.image = icon
            let iconString = NSAttributedString(attachment: iconAttachment)
            var displayString = statusText
            if(icon != nil) {
                displayString = "\t" + statusText
            }
            let stringText = NSAttributedString(string: displayString)
            let mutableAttachmentString = NSMutableAttributedString(attributedString: iconString)
            mutableAttachmentString.append(stringText)
            
            self?._promptLabel?.attributedText = mutableAttachmentString
            
        }
    }
    
    /*
        Function to display the manual picture scan button if the user hasnt lined up ( or cant line up ) within set time
     */
    private func initiateScanButtonHelper() {
        DispatchQueue.main.asyncAfter(deadline: .now() + self.MANUAL_SCAN_WAIT_TIME) {
            [weak self] in
            self?.scanButton.isHidden = false
        }
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
    
    @IBAction func takePhoto(_ sender: Any) {
        self.takeImagePhoto()
    }
}
