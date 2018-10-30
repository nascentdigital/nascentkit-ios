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


class VisionController: UIViewController {

    @IBOutlet weak var _cameraPreview: CameraFeedView!
    @objc @IBOutlet weak var _takePhotoButton: UIButton!

    private let _cameraFeed = CameraFeed()
    private var _cameraDirection = AVCaptureDevice.Position.back
    
    private var _takePhotoObserver: NSKeyValueObservation?


    override func viewDidLoad() {
        
        // call base implementation
        super.viewDidLoad()
        
        // customize photo button to be round
        _takePhotoButton.layer.masksToBounds = false
        _takePhotoButton.layer.cornerRadius = _takePhotoButton.bounds.width / 2
        _takePhotoButton.layer.borderWidth = 2
        _takePhotoButton.layer.borderColor = UIColor.black.cgColor
        
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

