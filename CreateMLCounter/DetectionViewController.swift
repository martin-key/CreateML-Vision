//
//  FaceDetectionViewController.swift
//  CreateMLCounter
//
//  Created by Martin Kuvandzhiev on 18.07.2018.
//  Copyright © 2018 Rapid Development Crew. All rights reserved.
//

import UIKit
import ARKit
import Vision
import CoreML


class DetectionViewController: UIViewController {
    
    @IBOutlet weak var sceneView: ARSCNView!
    @IBOutlet weak var recognitionInProgressLabel: UILabel!
    
    //scan timer
    private var scanTimer: Timer?
//    private var scannedFaceViews = [UIView]()
    
    fileprivate var analysisRequests = [VNRequest]()
    fileprivate var sequenceRequestHandler = VNSequenceRequestHandler()
    
    fileprivate let maximumHistoryLength = 15
    fileprivate var transpositionHistoryPoints = [CGPoint]()
    fileprivate var previousPixelBuffer: CVPixelBuffer?
    
    fileprivate var currentAnalysisBuffer: CVPixelBuffer?
    
    private var visionQueue = DispatchQueue(label: "com.HappyBirthdaySwiftSofia🎉")
    
    var productViewOpen = false
    var recognitionInProgress = false
    
    //get the orientation of the image that correspond's to the current device orientation
    private var imageOrientation: CGImagePropertyOrientation {
        switch UIDevice.current.orientation {
        case .portrait: return .right
        case .landscapeRight: return .down
        case .portraitUpsideDown: return .left
        case .unknown: fallthrough
        case .faceUp: fallthrough
        case .faceDown: fallthrough
        case .landscapeLeft: return .up
        }
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        sceneView.delegate = self
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        self.setupVision()
        
        let configuration = ARWorldTrackingConfiguration()
        sceneView.session.run(configuration)
        
        //scan for faces in regular intervals
        scanTimer = Timer.scheduledTimer(timeInterval: 0.1, target: self, selector: #selector(executeScanning), userInfo: nil, repeats: true)
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        scanTimer?.invalidate()
        sceneView.session.pause()
    }
    
    
    func setupVision() {
        let barcodeDetection = VNDetectBarcodesRequest { (request, error) in
            if let results = request.results?.first as? [VNBarcodeObservation] {
                if let mainBarcode = results.first {
                    if let payloadString = mainBarcode.payloadStringValue {
                        self.showProductInfo(identifier: payloadString)
                    }
                }
            }
        }
        
        self.analysisRequests = [barcodeDetection]
        guard let modelURL = Bundle.main.url(forResource: "MyAwesomeModel", withExtension: "mlmodelc") else {
            assertionFailure("I suck. Something is broken again.")
            return
        }
        
        do {
            let objectClassifier = try VNCoreMLModel(for: MLModel(contentsOf: modelURL))
            let objectRecognition = VNCoreMLRequest(model: objectClassifier) { (request, error) in
                if let results = request.results as? [VNClassificationObservation] {
                    print(results)
                    if results.first!.confidence >= 0.98 {
                        self.showProductInfo(identifier: results.first!.identifier)
                    }
                }
            }
            self.analysisRequests.append(objectRecognition)
        }
        catch {
            assertionFailure("I suck. Something is broken again.")
        }
        
        
    }
    
    
    private func analyzeCurrentImage() {
        
        guard let currentAnalysisBuffer = self.currentAnalysisBuffer else {
            return
        }
        
        recognitionInProgress = true
        
        let requestHandler = VNImageRequestHandler(cvPixelBuffer: currentAnalysisBuffer, orientation: self.imageOrientation)
        visionQueue.async {
            do {
                self.recognitionInProgress = false
                // release the buffer when completed
                defer {
                    self.currentAnalysisBuffer = nil
                }
                try requestHandler.perform(self.analysisRequests)
                
            } catch {
                assertionFailure("I suck. Something is broken again.")
            }
        }
    }
    
    
    
    func clearTranspositionPoints() {
        self.transpositionHistoryPoints.removeAll()
    }
    
    func addTranspotionPoints(_ point: CGPoint) {
        transpositionHistoryPoints.append(point)
        
        if transpositionHistoryPoints.count > self.maximumHistoryLength {
            transpositionHistoryPoints.removeFirst()
        }
    }
    
    var sceneStabilityAchieved: Bool {
        guard transpositionHistoryPoints.count == self.maximumHistoryLength else {
            return false
        }
        
        var movingAverage = CGPoint.zero
        for currentPoint in self.transpositionHistoryPoints {
            movingAverage.x += currentPoint.x
            movingAverage.y += currentPoint.y
        }
        
        let distance = abs(movingAverage.x) + abs(movingAverage.y)
        if distance < 50 {
            return true
        }
        
        return false
    }
    
    
    @objc
    private func executeScanning() {
        
        //remove the test views and empty the array that was keeping a reference to them
//        _ = scannedFaceViews.map { $0.removeFromSuperview() }
//        scannedFaceViews.removeAll()
        
        //get the captured image of the ARSession's current frame
        guard let currentPixelBuffer = sceneView.session.currentFrame?.capturedImage else { return }
        
        guard let previousPixelBufer = self.previousPixelBuffer else {
            previousPixelBuffer = currentPixelBuffer
            self.clearTranspositionPoints()
            return
        }
        
        guard productViewOpen == false else {
            return
        }
        
        
        
        let registrationRequest = VNTranslationalImageRegistrationRequest(targetedCVPixelBuffer: currentPixelBuffer)
        
        do {
            try sequenceRequestHandler.perform([registrationRequest], on: previousPixelBufer)
        } catch {
            assertionFailure("I suck. Something is broken again.")
        }
        
        guard recognitionInProgress == false else {
            return
        }
        
        previousPixelBuffer = currentPixelBuffer
        
        if let results = registrationRequest.results {
            if let allignmentObservation = results.first as? VNImageTranslationAlignmentObservation{
                let allignmentTransform = allignmentObservation.alignmentTransform
                self.addTranspotionPoints(CGPoint(x: allignmentTransform.tx, y: allignmentTransform.ty))
            }
        }
        
        if self.sceneStabilityAchieved == true {
            //show detection overlay
            self.recognitionInProgressLabel.isHidden = false
            self.currentAnalysisBuffer = currentPixelBuffer
            self.analyzeCurrentImage()
        } else {
            self.recognitionInProgressLabel.isHidden = true
        }
    }
    
    func showProductInfo(identifier: String) {
       let alert = UIAlertController(title: "Object recognized", message: identifier, preferredStyle: .alert)
        let action = UIAlertAction(title: "OK", style: .default) { (action) in
            alert.dismiss(animated: true, completion: nil)
            self.productViewOpen = false
        }
        alert.addAction(action)
        self.productViewOpen = true
        self.present(alert, animated: true, completion: nil)
    }
    
    
}

extension DetectionViewController: ARSCNViewDelegate {
    //implement ARSCNViewDelegate functions for things like error tracking
}
