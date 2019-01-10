# Camera Vision

Camera vision is a native iOS app written in Swift. It is used to scan immigration documents barcodes as well as text. This scanning happens one of two ways, in real time through the camera feed, or manually through user activated photo capture. 

Real time capture is limited currently due to device limitations Live feed captured images are lower resolution than manually captured photos so only higher end iPhones can accurately utilize the live scanning feature.

Barcode scanning is done through Firebase MLKit (https://firebase.google.com/docs/ml-kit/ios/read-barcodes)
OCR text detection is also done through Firebase MLKit (https://firebase.google.com/docs/ml-kit/ios/recognize-text)


## Pods

Camera vision relies heavily on the Nascent Kit development framework pods. It leverages the frameworks access to the phones camera. The framework handles granting permission for camera access, initializing the live feed and taking the photo. 

### Key methods

```swift
public func translateImagePointToPreviewLayer(forPoint point: CGPoint, relativeTo size: CGSize) -> CGPoint
```
This method is called when the following condition is met:
* Both barcodes have been successfully picked up by the MLKit barcode reader. If no barcode is picked up, or if only 1 is picked up this method isnt called

This method is used to translate the corner points of the scanned barcode from the coordinate system of the captured image into the coordinate system of the preview layer. Once the points are translated, they are compared to the coresponding view box on the layer to make sure the barcode is within the bounds with some relative margin.

The captured image is "flipped" relative to the preview layer when doing the translation between coordinate systems,because of this we need to reverse the X and Y relative point calculations:

```swift
        /*
            Since the image captured will have its X,Y coordinated flipped
            [(0,0) -> BottomLeft coordinate on native image translates to (0,1) -> BottomRight coordinate of preview layer coordinate system and vice versa]
            need to flip relative point calculations
         */
        let relativePoint = CGPoint(x: point.y / size.height, y: point.x / size.width)
```

This is done to give user valuable feedback such as "Move camera Down/Up/Left/Right" relative to the static view boxes on the UI. 

## VisionController 

The VisionController handles the majority of the flow within the application. Once the application has camera permission, it takes the user to the main scene (Vision Demo Scene). Once on this scene the application follows the following flow:

1. Labels, views and the mask view are initialized and configured accordingly. Most of this happens within the ovveridden ```viewDidLayoutSubviews()``` method

2. The camera feed is initialized via NascentKit. The camera feed is configured with a throttle value for how often a captured image is sent. This is configured through the constant ```CAMERA_FEED_THROTTLE```

> At this point everything now happens on a loop based on the camera feed throttle i.e the following happens every ```CAMERA_FEED_THROTTLE``` seconds until an exit condition is met. An exit condition is if both barcodes have been read successfully.

3. Utilize the MLKit on the captured image from the live feed to check if any visible barcode exists through the method ```detectBarcodeInImage(image: UIImage)``` This method is delegated to a background thread as this is where the calling of the aboved mentioned ```translateImagePointToPreviewLayer``` is used, as well as other analysis including illuminosity.

    #### If 1 or less barcodes are detected
    3.1 If we find we havn't detected two barcodes, the first thing we check is brightness via ` isImageValidBrightness(image: UIImage) -> Bool` method. The basics of the brightness check is we first scale down the image to a fraction of its size (100 width with ratio scaled height). We then filter the image so it becomes greyscale. At this point we are able to get an array of pixel values (each ranging from 0 [Dark or Black] to 255[Bright or white]). We can then calculate the Average Luminosity or Median Luminosity to determin if the image is darker than expected. An explination of this algorithm can be [found here](https://www.transpire.com/insights/blog/obtaining-luminosity-ios-camera/). Although not the exact same, we utilize the same concept.
    
    3.2 If the brightness isnt the issue, we can determin which barcode is missing based on the one we have. This can be displayed to the user to prompt them to make the second barcode more visible
    
    3.3 If no barcode is visible, we again check if brightness is the issue. Based on this we would display a valid message telling the user to either increase brightness or to reposition the camera to make sure both barcodes are visibe

4. If both barcodes are read, we need to check that they are within their corresponding view boxes (utilizing the `translateImagePointToPreviewLayer` method from the Nascent Kit framework). If they are not within the view boxes we display a helpful messages such as "Move Up/Down/Left/Right". This continues until the barcodes are positioned correctly

5. If both barcodes are read correctly, we save their values into the variable `private var finalBarcodeValues:[(barcodeType: BarcodeType, barcodeValue: String)] = []`. We also update our tuple variable `private var needValuesFrom = (barcode: true, ocr: true)` To indicate that we no longer need barcode values. This also causes the Camera Feed subscription to stop sending updates.

6. At this point we now force the device to capture a photo. Once we have this high res captured photo we run it through the MLKit text recognizer. Once we have the text from the document, we then need to accurately parse the relevant data (TBD) 

### Manual Scan

Currently we allow users to manually scan the document after a set time `MANUAL_SCAN_WAIT_TIME`. When the user manually scans the document, a photo is taken and then the Barcode detection and text recognition is run on the captured photo instead of the camera feed photo instance. The captured photo will be much higher quality and therefore *usually* more accurate barcode/text detection. On lower end phones this will be required to get an accurate reading of the barcodes/text. 

## Known Issues

* There is a random freeze that happens which locks up the entire UI. After profiling and debugging the issue it appears to be caused via the Nacent Kit Framework. It seems like a potential culprit is coming from the CameraFeed.swift file in the method `captureOutput` . We also get a console error when the freeze happens which can be seen below.

```swift     
@objc(captureOutput:didOutputSampleBuffer:fromConnection:)
    public func captureOutput(_ output: AVCaptureOutput,
            didOutput buffer: CMSampleBuffer,
            from connection: AVCaptureConnection) 

    // This issue may be due to the following. Converting the ciImage to a cgImage is expensive on the GPU
   guard let cgImage = _context.createCGImage(ciImage, from: ciImage.extent)`

   //This is the console error that gets displayed
   CameraVision[297:12703] Execution of the command buffer was aborted due to an error during execution. Caused GPU Timeout Error (IOAF code 2)
```

## TODO

* Fix up UX experience. Make sure correct messages are displayed at correct times for the user. 
* Add better user feedback when the manual scan photo button is taken (sync with design to figure out best approach)
