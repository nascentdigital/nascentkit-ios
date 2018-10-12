import Foundation
import AVKit
import RxSwift


public class CameraFeed: NSObject,
        AVCaptureVideoDataOutputSampleBufferDelegate,
        AVCapturePhotoCaptureDelegate {

    private let context = CIContext()
    internal let captureSession = AVCaptureSession()
    private var photoOutput: AVCapturePhotoOutput!

    private let videoSample$ = PublishSubject<UIImage>()
    private var takePhotoCompletion: Single<UIImage>.SingleObserver?
    private var disposeBag = DisposeBag();
    
    public var videoSamples: Observable<UIImage> { return videoSample$ }

    public func initialize(cameraPosition: AVCaptureDevice.Position) -> Completable {
        return checkPermissions()
            .andThen(startCaptureSession(cameraPosition: cameraPosition))
    }
    
    public func takePhoto() -> Single<UIImage> {
    
        // fail immediately if not initialized
        if (photoOutput == nil) {
            return Single.error(CameraFeedError.notInitialized)
        }
    
        // fail immediately if there's an inflight photo
        else if (takePhotoCompletion != nil) {
            return Single.error(CameraFeedError.photoInProgress)
        }
    
        // create single for new photo
        return Single.create {
            [weak self]
            single in
            
            // bail if already disposed (no need to raise error)
            guard let self = self else {
                single(.error(CameraFeedError.disposed))
                return Disposables.create()
            }
        
            // capture single
            self.takePhotoCompletion = single
            
            // setup photo capture settings
            let photoSettings: AVCapturePhotoSettings
            if self.photoOutput.availablePhotoCodecTypes.contains(.hevc) {
                photoSettings = AVCapturePhotoSettings(format:
                    [AVVideoCodecKey: AVVideoCodecType.hevc])
            } else {
                photoSettings = AVCapturePhotoSettings()
            }
            photoSettings.flashMode = .auto
            photoSettings.isAutoStillImageStabilizationEnabled =
                self.photoOutput.isStillImageStabilizationSupported

            // capture photo
            self.photoOutput.capturePhoto(with: photoSettings, delegate: self)

            return Disposables.create()
        }.subscribeOn(MainScheduler.instance)
    }

    private func checkPermissions() -> Completable {
        return Completable.create {
            completable in
            
            // check camera context
            switch AVCaptureDevice.authorizationStatus(for: .video) {
            
                // user has already given permission
                case .authorized:
                    completable(.completed)
                
                // user hasn't given permission (try to request)
                case .notDetermined:
                    AVCaptureDevice.requestAccess(for: .video) {
                        granted in
                        
                        // continue if granted
                        if granted {
                            completable(.completed)
                        }
                        
                        // or throw
                        else {
                            completable(.error(CameraFeedError.permissionRequired))
                        }
                    }
                
                // user has already denied access
                case .denied:
                    completable(.error(CameraFeedError.permissionRequired))
                
                // user doesn't have priviledges required to grant permission
                case .restricted:
                    completable(.error(CameraFeedError.permissionUnavailable))
            }
            
            // return disposable
            return Disposables.create()
        }
    }

    private func startCaptureSession(cameraPosition: AVCaptureDevice.Position) -> Completable {
    
        return Completable.create {
            [weak self]
            completable in
            
            // bail if already disposed (no need to raise error)
            guard let self = self else {
                completable(.error(CameraFeedError.disposed))
                return Disposables.create()
            }
        
            // begin capture session config
            self.captureSession.beginConfiguration()

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
                self.captureSession.canAddInput(captureInput)
                
            // raise error if no usable camera is found
            else {
                completable(.error(CameraFeedError.cameraNotFound))
                return Disposables.create()
            }
            
            // bind camera device to session
            self.captureSession.addInput(captureInput)
        
            // bind video capture to session (raise error if camera can't be used for video)
            let videoOutput = AVCaptureVideoDataOutput();
            videoOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "CamaraFeed.Samples"))
            guard self.captureSession.canAddOutput(videoOutput) else {
                completable(.error(CameraFeedError.cameraNotCompatible))
                return Disposables.create()
            }
            self.captureSession.sessionPreset = .high
            self.captureSession.addOutput(videoOutput)
            
            // this ensures that the UIImage built in captureOutput has correct orientation
            guard let videoOutputConnection = videoOutput.connection(with: .video) else {
                completable(.error(CameraFeedError.cameraNotCompatible))
                return Disposables.create()
            }
            
            if videoOutputConnection.isVideoOrientationSupported {
                videoOutputConnection.videoOrientation = .portrait
            }

            // bind photo capture to session (raise error if camera can't be used for photo)
            self.photoOutput = AVCapturePhotoOutput()
            self.photoOutput.isHighResolutionCaptureEnabled = true
            self.photoOutput.isLivePhotoCaptureEnabled = false
            guard self.captureSession.canAddOutput(self.photoOutput) else {
                completable(.error(CameraFeedError.cameraNotCompatible))
                return Disposables.create()
            }
            self.captureSession.sessionPreset = .photo
            self.captureSession.addOutput(self.photoOutput)

            // end configuration
            self.captureSession.commitConfiguration()
        
            // set camera orientation
//            guard let outputConnection = photoOutput.connection(with: .video) else { return }
//        guard let outputConnection = photoOutput.connection(with: .video) else { return }
//        if (outputConnection.isVideoOrientationSupported) {
//            outputConnection.videoOrientation = .portrait
//        }
//
            // start capturing
            self.captureSession.startRunning()
            
            // mark completed
            completable(.completed)
            
            // return disposable
            return Disposables.create()
        }
    }
    
    
    // MARK: AVCaptureVideoDataOutputSampleBufferDelegate
    
    @objc(captureOutput:didOutputSampleBuffer:fromConnection:)
    public func captureOutput(_ output: AVCaptureOutput,
            didOutput buffer: CMSampleBuffer,
            from connection: AVCaptureConnection) {
        
        // get image buffer (or fail)
        guard let imageBuffer = CMSampleBufferGetImageBuffer(buffer) else { return }

        // convert raw image data to CGImage
        let ciImage = CIImage(cvPixelBuffer: imageBuffer)
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { return }
        
        // convert CGImage to UIImage
        let image = UIImage(cgImage: cgImage)
        
        // publish image
        videoSample$.on(.next(image))
    }

    // MARK: AVCapturePhotoDelegate
    
    @objc(captureOutput:didFinishProcessingPhoto:error:)
    public func photoOutput(_ output: AVCapturePhotoOutput,
            didFinishProcessingPhoto photo: AVCapturePhoto,
            error: Error?) {
        
        print("[CameraFeed] captured photo")

        // skip if there is no completion
        guard let single = takePhotoCompletion else { return }
        
        // make sure to clear completion (one-time use only)
        takePhotoCompletion = nil;
        
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
