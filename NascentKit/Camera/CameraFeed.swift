import Foundation
import AVKit
import RxSwift


public class CameraFeed: NSObject,
        AVCaptureVideoDataOutputSampleBufferDelegate,
        AVCapturePhotoCaptureDelegate {

    public var cameraPosition = AVCaptureDevice.Position.unspecified
    internal let captureSession = AVCaptureSession()
    private let _context = CIContext()
    private var _photoOutput: AVCapturePhotoOutput!

    private let _videoSample$ = PublishSubject<UIImage>()
    
    private var _photoPending = false
    private var _photo: UIImage?
    private var _photoError: Error?
    private var _photoCompletion: Single<UIImage>.SingleObserver?
    
    private var _sampling = false
    public var sampling: Bool {
        get {
            return _sampling
        }
        set(value) {
            _sampling = value
        }
    }
    public var videoSamples: Observable<UIImage> { return _videoSample$ }


    public static func getPermission() -> AVAuthorizationStatus {
        return AVCaptureDevice.authorizationStatus(for: .video)
    }

    public static func requestPermission() -> Observable<AVAuthorizationStatus> {

        // return immediately if permission can't be requested
        let permission = CameraFeed.getPermission()
        if (permission != .notDetermined) {
            return Observable.just(permission,
                                   scheduler: ConcurrentMainScheduler.instance)
        }
        
        // start request
        let deferral: AsyncSubject<AVAuthorizationStatus> = AsyncSubject()
        AVCaptureDevice.requestAccess(for: .video) {
            granted in
            
            // raise deferral
            deferral.onNext(granted
                ? .authorized
                : .denied)
            
            // complete
            deferral.onCompleted()
        }
        
        // return deferral
        return deferral.asObservable()
    }

    public func start(cameraPosition: AVCaptureDevice.Position, sampling: Bool = false) throws {
    
        // fail immediately if camera permission isn't granted
        if (CameraFeed.getPermission() != .authorized) {
            throw CameraFeedError.permissionRequired
        }
    
        // initialize (may throw)
        try initializeSession(cameraPosition: cameraPosition)

        // start capture session
        captureSession.startRunning()
        
        _sampling = sampling
    }
    
    public func stop() {
        
        // stop if running (ignores otherwise)
        if (captureSession.isRunning) {
            captureSession.stopRunning()
        }
    }
    
    public func takePhoto() -> Single<UIImage> {
    
        // fail immediately if not initialized
        if (_photoOutput == nil) {
            return Single.error(CameraFeedError.notInitialized)
        }
    
        // fail immediately if there's an inflight photo
        else if (_photoPending) {
            return Single.error(CameraFeedError.photoInProgress)
        }
        
        // mark photo in progress
        _photoPending = true
    
        // setup photo capture settings using newer HEVC format
        let photoSettings: AVCapturePhotoSettings
        if (_photoOutput.availablePhotoCodecTypes.contains(.hevc)) {
            photoSettings = AVCapturePhotoSettings(format:
                [AVVideoCodecKey: AVVideoCodecType.hevc])
        }
        
        // or use default format
        else {
            photoSettings = AVCapturePhotoSettings()
        }
        
        // TODO: enable these to be configured by caller
        photoSettings.flashMode = .auto
        photoSettings.isAutoStillImageStabilizationEnabled =
            _photoOutput.isStillImageStabilizationSupported

        // capture photo
        _photoOutput.capturePhoto(with: photoSettings, delegate: self)

        // create single for new photo
        return Single.create {
            [weak self]
            single in
            
            // bail if already disposed (no need to raise error)
            guard let self = self
            else {
                single(.error(CameraFeedError.disposed))
                return Disposables.create()
            }
            
            // raise error if there was one
            if (self._photoError != nil) {
            
                // clear previous error
                let photoError = self._photoError!
                self._photoError = nil

                // raise error
                single(.error(photoError))
                
                // mark complete
                self._photoPending = false
            }
            
            // or use image if one was saved
            else if (self._photo != nil) {
            
                // clear previous photo
                let photo = self._photo!
                self._photo = nil
                
                // return immediately with photo
                single(.success(photo))
                
                // mark complete
                self._photoPending = false
            }
            
            // otherwise, capture completion
            else {
                self._photoCompletion = single
            }
        
            // return disposable
            return Disposables.create()
            
        }.subscribeOn(MainScheduler.instance)
    }

    private func initializeSession(cameraPosition: AVCaptureDevice.Position) throws {
 
        // skip if position is the same
        if (self.cameraPosition == cameraPosition) {
            return
        }
        
        // update camera position
        self.cameraPosition = cameraPosition
        
        // begin capture session config
        captureSession.beginConfiguration()

        // reset camera session (if required)
        if (_photoOutput != nil) {
        
            // unbind outputs
            for output in captureSession.outputs {
                captureSession.removeOutput(output)
            }
            _photoOutput = nil
            
            // unbind inputs
            for input in captureSession.inputs {
                captureSession.removeInput(input)
            }
        }

        // resolve camera device (or fail)
        let discoverySession = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInTrueDepthCamera, .builtInDualCamera, .builtInWideAngleCamera],
            mediaType: .video,
            position: cameraPosition)
        let devices = discoverySession.devices
        
        // determine if camera device can be used
        let cameraDevice = devices.first(where: { device in device.position == cameraPosition })
        guard
            cameraDevice != nil,
            let captureInput = try? AVCaptureDeviceInput(device: cameraDevice!),
            captureSession.canAddInput(captureInput)
            
        // raise error if no usable camera is found
        else {
            throw CameraFeedError.cameraNotFound
        }
        
        // bind camera device to session
        captureSession.addInput(captureInput)

        // bind video preview to session (raise error if camera can't be used for video)
        let videoOutput = AVCaptureVideoDataOutput();
        videoOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "CamaraFeed.Samples"))
        guard captureSession.canAddOutput(videoOutput)
        else {
            throw CameraFeedError.cameraNotCompatible
        }
        captureSession.sessionPreset = .high
        captureSession.addOutput(videoOutput)

        // ensure that images built in output have correct orientation
        guard let videoOutputConnection = videoOutput.connection(with: .video)
        else {
            throw CameraFeedError.cameraNotCompatible
        }
        if videoOutputConnection.isVideoOrientationSupported {
            videoOutputConnection.videoOrientation = .portrait
        }

        // bind photo capture to session (raise error if camera can't be used for photo)
        _photoOutput = AVCapturePhotoOutput()
        _photoOutput.isHighResolutionCaptureEnabled = true
        _photoOutput.isLivePhotoCaptureEnabled = false
        guard self.captureSession.canAddOutput(_photoOutput)
        else {
            throw CameraFeedError.cameraNotCompatible
        }
        captureSession.sessionPreset = .photo
        captureSession.addOutput(_photoOutput)

        // end configuration
        captureSession.commitConfiguration()
    }
    
    
    // MARK: AVCaptureVideoDataOutputSampleBufferDelegate

    @objc(captureOutput:didOutputSampleBuffer:fromConnection:)
    public func captureOutput(_ output: AVCaptureOutput,
            didOutput buffer: CMSampleBuffer,
            from connection: AVCaptureConnection) {

        guard sampling else { return }
        // get image buffer (or fail)
        guard let imageBuffer = CMSampleBufferGetImageBuffer(buffer)
        else {
            return
        }

        // convert raw image data to CGImage
        let ciImage = CIImage(cvPixelBuffer: imageBuffer)
        guard let cgImage = _context.createCGImage(ciImage, from: ciImage.extent)
        else {
            return
        }
        
        // convert CGImage to UIImage
        let image = UIImage(cgImage: cgImage)
        
        // publish image
        _videoSample$.on(.next(image))
    }


    // MARK: AVCapturePhotoDelegate
    
    @objc(captureOutput:didFinishProcessingPhoto:error:)
    public func photoOutput(_ output: AVCapturePhotoOutput,
            didFinishProcessingPhoto photo: AVCapturePhoto,
            error: Error?) {
        
        print("[CameraFeed] captured photo")

        // convert photo to image using file representation (handles orientation)
        let image = error != nil
            ? nil
            : UIImage(data: photo.fileDataRepresentation()!)!

        // just capture photo if there is no completion
        guard let single = _photoCompletion
        else {
        
            // capture photo and potential error
            _photo = image
            _photoError = error
            
            // stop processing
            return
        }
        
        // make sure to clear completion (one-time use only)
        _photoCompletion = nil
        
        // mark complete
        _photoPending = false

        // fail immediately if there is an error
        if (error != nil) {
            single(.error(error!))
        }

        // or return photo
        else {
            single(.success(image!))
        }
    }
}
