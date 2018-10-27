import Foundation
import AVKit
import RxSwift


public class CameraFeed: NSObject,
        AVCaptureVideoDataOutputSampleBufferDelegate,
        AVCapturePhotoCaptureDelegate {

    internal let captureSession = AVCaptureSession()
    private let _context = CIContext()
    private var _cameraPosition: AVCaptureDevice.Position!
    private var _photoOutput: AVCapturePhotoOutput!

    private let _videoSample$ = PublishSubject<UIImage>()
    private var _takePhotoCompletion: Single<UIImage>.SingleObserver?
    
    
    public var videoSamples: Observable<UIImage> { return _videoSample$ }


    public static func getPermission() -> AVAuthorizationStatus {
        return AVCaptureDevice.authorizationStatus(for: .video)
    }

    public static func requestPermission() -> Single<AVAuthorizationStatus> {
        return Single.create {
            single in
            
            // skip if user has already given permission or if restricted
            let permission = CameraFeed.getPermission()
            if (permission == .authorized
                || permission == .restricted) {
                single(.success(permission))
            }
            
            // otherwise, ask and return result
            else {
                AVCaptureDevice.requestAccess(for: .video) {
                    granted in
                    
                    single(.success(granted
                        ? .authorized
                        : .denied))
                }
            }
            
            // return disposable
            return Disposables.create()
        }
    }

    public func start(cameraPosition: AVCaptureDevice.Position) throws {
    
        // fail immediately if camera permission isn't granted
        if (CameraFeed.getPermission() != .authorized) {
            throw CameraFeedError.permissionRequired
        }
    
        // initialize (may throw)
        try initializeSession(cameraPosition: cameraPosition)

        // start capture session
        captureSession.startRunning()
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
        else if (_takePhotoCompletion != nil) {
            return Single.error(CameraFeedError.photoInProgress)
        }
    
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
        
            // capture single
            self._takePhotoCompletion = single
            
            // setup photo capture settings
            let photoSettings: AVCapturePhotoSettings
            if self._photoOutput.availablePhotoCodecTypes.contains(.hevc) {
                photoSettings = AVCapturePhotoSettings(format:
                    [AVVideoCodecKey: AVVideoCodecType.hevc])
            }
            else {
                photoSettings = AVCapturePhotoSettings()
            }
            photoSettings.flashMode = .auto
            photoSettings.isAutoStillImageStabilizationEnabled =
                self._photoOutput.isStillImageStabilizationSupported

            // capture photo
            self._photoOutput.capturePhoto(with: photoSettings, delegate: self)

            return Disposables.create()
        }.subscribeOn(MainScheduler.instance)
    }

    private func initializeSession(cameraPosition: AVCaptureDevice.Position) throws {
 
        // skip if position is the same
        if (_cameraPosition != nil
            && _cameraPosition! == cameraPosition) {

            return
        }
        
        // begin capture session config
        captureSession.beginConfiguration()

        // reset camera session if there is one
        


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

        // skip if there is no completion
        guard let single = _takePhotoCompletion
        else {
            return
        }
        
        // make sure to clear completion (one-time use only)
        _takePhotoCompletion = nil;
        
        // fail immediately if there is an error
        if (error != nil) {
            single(.error(error!))
        }

        // or return image
        else {
            // using fileDataRepresentation instead of cgImageRepresentation automatically
            // sets the correct orientation
            
            let image = UIImage(data: photo.fileDataRepresentation()!)!
            single(.success(image))
        }
    }
}
