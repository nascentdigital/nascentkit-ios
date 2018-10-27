//
//  VisionController.swift
//  CameraVision
//
//  Created by Simeon de Dios on 2018-10-26.
//  Copyright © 2018 Nascent Digital. All rights reserved.
//

import UIKit
import NascentKit
import RxSwift


class VisionController: UIViewController {

    @IBOutlet weak var _cameraPreview: CameraFeedView!
    
    private let _cameraFeed = CameraFeed()
    

    override func viewWillAppear(_ animated: Bool) {
    
        // call base implementation
        super.viewWillAppear(animated)

        // try to start camera feed + preview
        do {
        
            // start camera feed
            try _cameraFeed.start(cameraPosition: .back)

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
}

