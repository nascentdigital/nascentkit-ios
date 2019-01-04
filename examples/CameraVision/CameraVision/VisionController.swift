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

// Extension for getting associated colors for known status
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
            }
        }
    }
}

// Extension for getting associated images for known status
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
            }
        }
    }
}


class VisionController: UIViewController {

    let X_VALID_MARGIN: Int = 5
    let Y_VALID_MARGIN: Int = 5
    let NUM_OF_BARCODES: Int = 2
    let MANUAL_SCAN_WAIT_TIME = 5.0
    // Lower bound for luminosity value ( Currently this is just a magic number )
    let LOW_LUMINOSITY_LEVEL: Int = 100
    
    //Throttle value for the camera feed to capture images
    let CAMERA_FEED_THROTTLE: RxTimeInterval = 4
    
    @IBOutlet weak var _cameraPreview: CameraFeedView!
    @IBOutlet weak var _certificateLabel: UILabel!
    @IBOutlet weak var scanButton: UIButton!
    @IBOutlet weak var bottomContainerView: UIView!
    @IBOutlet weak var maskView: UIView!
    @IBOutlet weak var certificateBarcodeView: UIView!
    @IBOutlet weak var birthdayBarcodeView: UIView!
    @IBOutlet weak var certificateBarcodeLabel: UILabel!
    @IBOutlet weak var birthdayBarcodeLabel: UILabel!
    @IBOutlet weak var statusView: UIView!
    @IBOutlet weak var bottomViewHeightConstraint: NSLayoutConstraint!
    
    var _promptLabel: UILabel!
    
    private let _cameraFeed = CameraFeed()
    private var _cameraDirection = AVCaptureDevice.Position.back
    
    private var _takePhotoObserver: NSKeyValueObservation?
    private var barcodeDetector: VisionBarcodeDetector!
    private let _disposeBag = DisposeBag()
    
    private var needValuesFrom = (barcode: true, ocr: true)
    private var finalBarcodeValues:[(barcodeType: BarcodeType, barcodeValue: String)] = []
    
    private var finalFullImage: UIImage?
    
    private var takeNextSample: Bool! = true
    
    override func viewDidLoad() {
        
        // call base implementation
        super.viewDidLoad()
        
        // Hide scan button on first load until user doesnt take proper photo
        self.scanButton.isHidden = true
        
        bottomContainerView.layer.contents = UIImage(named: "background.png")?.cgImage
        
        //Setup status view to prompt the user of any issues
        statusView.layer.backgroundColor = StatusColors.infoColor.value.cgColor
        
    }

    override func viewDidLayoutSubviews() {
        super.viewWillLayoutSubviews()

        _cameraPreview.previewLayerRect
            .subscribe(
                onNext:{
                [unowned self]
                rect in
                
                // Recalculate the bottom view height when the camera preview layer changes
                self.recalculateBottomViewHeight(cameraFeedRect: rect)
                
            }).disposed(by: _disposeBag)
        

        //Setup Mask color
        maskView.layer.backgroundColor = UIColor(red: 79/255, green: 98/255, blue: 121/255, alpha: 0.4).cgColor
        view.layer.backgroundColor = UIColor(red: 79/255, green: 98/255, blue: 121/255, alpha: 1).cgColor

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
        certificateBarcodeLabel.contentMode = .scaleToFill
        certificateBarcodeLabel.textColor = UIColor.white
        certificateBarcodeLabel.font = UIFont(name: "AppleSDGothicNeo-Thin", size: 16)
        certificateBarcodeLabel.text = "Barcode"
        
        // Copy over certificate label and change origin x for birthday
        birthdayBarcodeLabel.contentMode = .scaleToFill
        birthdayBarcodeLabel.textColor = UIColor.white
        birthdayBarcodeLabel.font = UIFont(name: "AppleSDGothicNeo-Thin", size: 16)
        birthdayBarcodeLabel.text = "Barcode"
        
        // Set certificate and birthday View properties
        certificateBarcodeView.layer.borderWidth = 1.0
        certificateBarcodeView.layer.borderColor = UIColor.black.cgColor
        certificateBarcodeView.layer.backgroundColor = UIColor.clear.cgColor
        certificateBarcodeView.layer.zPosition = 1
        
        birthdayBarcodeView.layer.borderWidth = 1.0
        birthdayBarcodeView.layer.borderColor = UIColor.black.cgColor
        birthdayBarcodeView.layer.backgroundColor = UIColor.clear.cgColor
        birthdayBarcodeView.layer.zPosition = 1
        
        // Add certificate and birthday label to view
        self.statusView.addSubview(_promptLabel)
        
        // Show initial status to prompt the user
        // self.showStatusView(statusText: "Scanning document to validate. \nPlease line up with guides", isError: false)
        
        // Delay to start the camera feed
        self.initializeCameraFeedVideoSampler()
        self.initiateScanButtonHelper()
        addMaskView()
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
        
        let vision = Vision.vision()
        barcodeDetector = vision.barcodeDetector(options: barcodeOptions)
        
        _cameraFeed.videoSamples
                .throttle(self.CAMERA_FEED_THROTTLE, scheduler: SerialDispatchQueueScheduler(qos: .background))
                // Skip while another sample is being processed
                .skipWhile({ (image) -> Bool in
                   return !self.takeNextSample || !self.needValuesFrom.barcode
                })
                .subscribe(
                    onNext: {
                        [unowned self]
                        image in

                        // Set sample flag
                        self.takeNextSample = false
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
        // Run barcode detection in background thread off main UI thread
        DispatchQueue.global(qos: .background).async {
            [weak self] in
            
            let visionImage = VisionImage(image: image)
            self?.barcodeDetector.detect(in: visionImage) {
                features, error in
                
                guard error == nil, let features = features, !features.isEmpty else {
                    // Check if brightness is a possible reason barcodes were not scanned
                    if (!(self?.isImageValidBrightness(image: image))!) {
                        self?.showStatusView(statusText: "Image brightness appears low. \nPlease make sure document is well lit", isError: true)
                        return
                    } else {
                        self?.showStatusView(statusText: "Unable to detect barcode \nPlease reposition until both barcodes are within view", isError: true)
                        return
                    }

                }
                
                // Flag to determin if any read barcode is invalid / can't be read
                var isValid = true
                var statusText: String = ""
                
                // If both barcodes havn't been picked up, prompt the user of the missing barcode
                if(features.count != self?.NUM_OF_BARCODES) {
                    let barcodeType = self?.getBarcodeType(barcode: features.first)
                    
                    isValid = false
                    let missingBarcode = barcodeType == BarcodeType.CertificateNo ? BarcodeType.DateOfBirth.name : BarcodeType.CertificateNo.name
                    if(!(self?.isImageValidBrightness(image: image))!) {
                        self?.showStatusView(statusText: "Unable to detect \(missingBarcode) barcode. \nPlease make sure document is well lit", isError: true)
                        return
                    } else {
                        self?.showStatusView(statusText: "One barcode detected. \nPlease move document so \(missingBarcode) is in view", isError: false)
                        return

                    }
                }
                
                // Reset the final barcode values array
                self?.finalBarcodeValues.removeAll()
                
                /*
                 Date Barcode Raw Value: e.g 1991/04/29
                 CertificateNo Raw Value: e.g K9548487
                 */
                for feature in features {
                    // If an invalid barcode was scanned, no need to continue
                    if (!isValid) {
                        break
                    } else if (!(self?.needValuesFrom.ocr)!) {
                        // If a picture was taken and there are 2 barcodes detected, No need to check if barcodes within bounds of barcode views
                        isValid = true
                        break
                    }
                    
                    // Figure out which container the barcode belongs to
                    let barcodeTopLeft =  self?._cameraPreview.translateImagePointToPreviewLayer(forPoint: feature.cornerPoints![0].cgPointValue, relativeTo: image.size)
                    var _containerView: UIView!
                    
                    // If the top left of the barcode is further past the right border of the the certificate view, assume barcode is for DoB
                    if(barcodeTopLeft!.x > (self?.certificateBarcodeView.frame.origin.x)! + (self?.certificateBarcodeView.frame.width)!) {
                        _containerView = self?.birthdayBarcodeView
                    } else {
                        // Otherwise assume barcode is for Certificate No
                        _containerView = self?.certificateBarcodeView
                    }
                    
                    
                    let barcodeType = self?.getBarcodeType(barcode: feature)
                    
                    // Check if barcode is within view
                    let validBarcode = self!.isValidBarcodeInView(barcode: feature, barcodeType: barcodeType!, containerView: _containerView, imageSize: image.size)
                    if !validBarcode.isValid {
                        // If any of the barcodes fail, false flag
                        isValid = false
                        statusText = validBarcode.statusText
                    }
                    
                    // Add valid barcode to array of barcodes
                    self?.finalBarcodeValues.append((barcodeType: barcodeType!, barcodeValue: feature.rawValue!))
                }
                
                // Both Barcodes were read successfully
                if(isValid && (self?.needValuesFrom.barcode)!) {
                    statusText = "Yay both barcodes read!"
                    self?.needValuesFrom.barcode = false
                    if((self?.needValuesFrom.ocr)!) {
                        self?.takeImagePhoto()
                    } else {
                        self?.finalFullImage = image
                        // Go to next page
                        self?.performSegue(withIdentifier: "detailController", sender: nil)

                    }
                }
                self?.showStatusView(statusText: statusText, isError: !isValid)
            }
        }

    }
    
    private func takeImagePhoto(){
        // If both OCR and Barcode were read, no need to take another photo
        if(!self.needValuesFrom.ocr && !self.needValuesFrom.barcode){
            self.showStatusView(statusText: "Acceptable photo already taken", isError: false)

            return
        }
        self._cameraFeed.takePhoto()
            .subscribeOn(SerialDispatchQueueScheduler(qos: .background))
            .subscribe(onSuccess: {
                [unowned self]
                image in
                if let fixedImage = image.fixedOrientation() {
                    self.showStatusView(statusText: "Analyzing photo...", isError: false)
                    self.readImageText(image: fixedImage)
                    self.needValuesFrom.ocr = false
                    if(self.needValuesFrom.barcode) {
                        self.detectBarcodeInImage(image: fixedImage)
                    } else {
                        self.finalFullImage = fixedImage
                        // Go to next page
                        self.performSegue(withIdentifier: "detailController", sender: nil)
                    }
                }
            }, onError: {
                error in
                print("Capture photo error \(error)")
                self.showStatusView(statusText: "Capture Photo Error: \(error)", isError: true)
            })
    }
    
    private func readImageText(image: UIImage) {
        // Run barcode detection in background thread off main UI thread
        DispatchQueue.global(qos: .background).async {
            [weak self] in
            
            let vision = Vision.vision()
            
            let textRecognizer = vision.onDeviceTextRecognizer()
            
            let image = VisionImage(image: image)
            
            textRecognizer.process(image) {
                result, error in
                guard error == nil, let result = result else {
                    
                    return
                }
                
                // OCR text data stored in 'result'
                
                self?.needValuesFrom.ocr = false
            }
        }
    }
    
    private func isValidBarcodeInView(barcode: VisionBarcode, barcodeType: BarcodeType, containerView: UIView, imageSize: CGSize) -> (isValid: Bool, statusText: String) {
        
        if(barcodeType == BarcodeType.Invalid) {
            return (false, "Invalid barcode detected")
        }
        
        // Initialize valid flag as false
        var isValid = false
        var statusText: String = ""
        
        // cornerPoints hold points for 4 corners of scanned barcode starting from top left and going clockwise
        _ = _cameraPreview.translateImagePointToPreviewLayer(forPoint: barcode.cornerPoints![0].cgPointValue, relativeTo: imageSize)
        let barcodeBottomLeft = _cameraPreview.translateImagePointToPreviewLayer(forPoint: barcode.cornerPoints![3].cgPointValue, relativeTo: imageSize)
        let barcodeTopRight = _cameraPreview.translateImagePointToPreviewLayer(forPoint: barcode.cornerPoints![1].cgPointValue, relativeTo: imageSize)
        _ = _cameraPreview.translateImagePointToPreviewLayer(forPoint: barcode.cornerPoints![2].cgPointValue, relativeTo: imageSize)

        // drawBarcodeRect(barcodeTopLeft: barcodeTopLeft, barcodeTopRight: barcodeTopRight, barcodeBottomRight: barcodeBottomRight, barcodeType: barcodeType)

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
    
    private func getBarcodeType(barcode: VisionBarcode?) -> BarcodeType{
        
        if(barcode == nil) {
            return BarcodeType.Invalid
        }
        
        let rawValue = barcode!.rawValue
        // If no value can be read, return invalid type
        if(rawValue == nil) {
            return BarcodeType.Invalid
        }
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy/MM/dd"
        guard dateFormatter.date(from: rawValue!) != nil else {
            // Its not a valid date , check if its a Certificate Number
            // TODO: This isnt always a certificate No. Need criteria to classify string as certificate No. or not
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
                // icon = StatusIcons.errorIcon.value
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
            
            // Update status text
            self?._promptLabel?.text = statusText
            
            // Reset sample flag to now allow next frame sample to be accepted
            self?.takeNextSample = true
            
        }
    }
    
    /*
        Function to display the manual picture scan button if the user hasnt lined up ( or cant line up ) within set time
     */
    private func initiateScanButtonHelper() {
        DispatchQueue.main.asyncAfter(deadline: .now() + self.MANUAL_SCAN_WAIT_TIME) {
            [weak self] in
            self?.scanButton.isHidden = false
            self?.showStatusView(statusText: "Cannnot auto-scan. Please capture manually", isError: false)
        }
    }
    
    /*
        Helper function to draw the scanned barcodes frame on the UI
     */
    private func drawBarcodeRect(barcodeTopLeft: CGPoint, barcodeTopRight: CGPoint, barcodeBottomRight: CGPoint, barcodeType: BarcodeType) {
        DispatchQueue.main.async {
            [unowned self] in
            // Rect around the scanned barcode
            let barcodeRect = CGRect(x: barcodeTopLeft.x, y: barcodeTopLeft.y, width: barcodeTopRight.x - barcodeTopLeft.x, height: barcodeBottomRight.y - barcodeTopRight.y)
            
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
        }
    
    }
    
    private func addMaskView() {
        
        // UI changes done on main thread
        DispatchQueue.main.async {
            [weak self] in
            let mutablePath = CGMutablePath()
            mutablePath.addRect((self?.maskView.bounds)!)
            
            mutablePath.addRects([(self?.certificateBarcodeView.frame)!, (self?.birthdayBarcodeView.frame)!])
            
            let maskLayer = CAShapeLayer()
            maskLayer.path = mutablePath
            maskLayer.fillRule = CAShapeLayerFillRule.evenOdd
            maskLayer.backgroundColor = UIColor.clear.cgColor
            
            // Add mask to maskView
            self?.maskView.layer.mask = maskLayer
            
            self?.view.bringSubviewToFront((self?.maskView)!)
        }
    }
    
    private func recalculateBottomViewHeight(cameraFeedRect: CGRect) {
        if(cameraFeedRect.height < _cameraPreview.frame.height) {
            // Set new height constraint on bottom container view
            bottomViewHeightConstraint.constant = bottomContainerView.frame.height + (_cameraPreview.frame.height - cameraFeedRect.height)
            
            // Recalculate mask based on newly positioned barcode views
            addMaskView()
        }
    }
    
    /*
        Check if the image is deemed bright enough to not impact scanning
     */
    private func isImageValidBrightness(image: UIImage) -> Bool{
        
        let imageLuminosity = calculateImageLuminosity(image: image)
        
        // TODO: Potentially have more 'brightness' options instead of 1 basic check.
        if(imageLuminosity < LOW_LUMINOSITY_LEVEL) {
            // Image brightness is lower than expected
            return false
        } else {
            // Image brightness is of acceptable value
            return true
        }
        
    }
    
    /*
        Calculates the average luminosity intensity for the Image
     */
    private func calculateImageLuminosity(image: UIImage) -> Int {
        
        //Resize image to perform luminosity calculations, resizing to 100 width while keeping aspect ratio
        let newImageWidth:CGFloat = 100.0
        let scale = newImageWidth / image.size.width
        let newImageHeight = image.size.height * scale
        
        UIGraphicsBeginImageContext(CGSize(width: newImageWidth, height: newImageHeight))
        image.draw(in: CGRect(x: 0, y: 0, width: newImageWidth, height: newImageHeight))
        // Save the scaled down res photo
        let scaledDownOriginalImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        
        // Once we have the scaled down image, need to convert to Greyscale for luminosity calculations
        let greyImageRect: CGRect = CGRect(x: 0, y: 0, width: newImageWidth, height: newImageHeight)
        let greyscaleColorSpace = CGColorSpaceCreateDeviceGray()
        
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue)
        let context =   CGContext(data: nil,
                                  width: Int(newImageWidth),
                                  height: Int(newImageHeight),
                                  bitsPerComponent: 8,
                                  bytesPerRow: 0,
                                  space: greyscaleColorSpace,
                                  bitmapInfo: bitmapInfo.rawValue)
        
        context?.draw((scaledDownOriginalImage?.cgImage)!, in: greyImageRect)
        
        // Save greyscale CG Image
        let greyscaleCgImage: CGImage! = context?.makeImage()
        
        /*
            Once we have the greyscale image, we only look at the intensity near the middle of the image
            We avoid looking at intensity around the edges and near text at top
         */
        let croppedOrigin = CGPoint(x: 0, y: CGFloat(greyscaleCgImage.height) * 0.30)
        let croppedImage: CGImage! = greyscaleCgImage.cropping(to: CGRect(x: croppedOrigin.x,
                                                                          y: croppedOrigin.y,
                                                                          width: (CGFloat(greyscaleCgImage.width) - croppedOrigin.x) - 10.0,
                                                                          height: (CGFloat(greyscaleCgImage.height) - croppedOrigin.y) - 10.0))
        
        let bitsPerComponent = croppedImage.bitsPerComponent
        let bytesPerRow = croppedImage.bytesPerRow
        let totalBytes = croppedImage.height * bytesPerRow
        
        /*
         Array of greyscale pixel values for sized down image
         Values range from 0 (being dark or black) to 255 (being bright or white)
         */
        var intensities = [UInt8](repeating: 0, count: totalBytes)
        
        let contextRef = CGContext(data: &intensities,
                                   width: croppedImage.width,
                                   height: croppedImage.height,
                                   bitsPerComponent: bitsPerComponent,
                                   bytesPerRow: bytesPerRow,
                                   space: greyscaleColorSpace,
                                   bitmapInfo: 0)
        
        contextRef?.draw(croppedImage, in: CGRect(x: 0,
                                                  y: 0,
                                                  width: croppedImage.width,
                                                  height: croppedImage.height))
        
        var intensitySum: Int = 0;
        
        // Calculate Avg and Median from the array of intensity values
        for intensity in intensities {
            intensitySum += Int(intensity)
        }
        let averageIntensity = intensitySum / intensities.count
        let medianIntensity = intensities.sorted(by: <)[intensities.count / 2]
        
        print("Avg Intensities: \(averageIntensity)")
        print("median Intensity: \(medianIntensity)")
        
        return averageIntensity

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
