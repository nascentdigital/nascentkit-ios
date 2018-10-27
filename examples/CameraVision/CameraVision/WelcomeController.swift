//
//  WelcomeController.swift
//  CameraVision
//
//  Created by Simeon de Dios on 2018-10-26.
//  Copyright © 2018 Nascent Digital. All rights reserved.
//

import UIKit
import AVKit
import RxSwift
import NascentKit


class WelcomeController: UIViewController {

    @IBOutlet weak var _permissionPanel: UIView!
    @IBOutlet weak var _continuePanel: UIView!
    
    private let _disposeBag = DisposeBag()
    
    
    override func viewDidLoad() {
    
        // call base implementation
        super.viewDidLoad()
    }
    
    override func viewWillAppear(_ animated: Bool) {

        // update panels before view appears
        updatePanels(CameraFeed.getPermission())
    }
    
    private func updatePanels(_ cameraPermission: AVAuthorizationStatus) {
    
        // TODO: we should handle other cases, like the camera access not being
        //       available due to access control restrictions

        // show permission panel if required
        _permissionPanel.isHidden = cameraPermission == .authorized
        _continuePanel.isHidden = !_permissionPanel.isHidden
    }
    
    @IBAction func grantPermission() {
    
        print("[WelcomeController] granting camera permission")
        
        // open settings if permission was previously denied
        if (CameraFeed.getPermission() == .denied) {
            let settingsUrl = UIApplication.openSettingsURLString
            UIApplication.shared.open(URL(string: settingsUrl)!)
        }
        
        // or request camera permissions
        else {
            CameraFeed.requestPermission()
                .subscribeOn(ConcurrentMainScheduler.instance)
                .subscribe(
                    onSuccess: {
                        [unowned self]
                        cameraPermission in
                        
                        // update state based on permissions
                        self.updatePanels(cameraPermission)
                    },
                    onError: {
                        error in
                        
                        print("[WelcomeController] unexpected error: \(error)")
                    }
                )
                .disposed(by: _disposeBag)
        }
    }
}

