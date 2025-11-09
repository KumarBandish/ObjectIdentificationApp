//
//  CameraManager.swift
//  App
//
//  Created by Bandish Kumar on 03/11/25.
//

import SwiftUI
import Vision
internal import AVFoundation
import Combine
import CoreML

class CameraManager: NSObject, ObservableObject {
    
    @Published var session = AVCaptureSession()
    @Published var videoOutput = AVCaptureVideoDataOutput()
    @Published var previewLayer = AVCaptureVideoPreviewLayer()
    
    @Published var detectedObjects: [String] = []
    @Published var isRecording = false
    @Published var recordingURL: URL?
    @Published var detectionTime: Double = 0
    
    private var videoDevice: AVCaptureDevice?
    private var movieOutput: AVCaptureMovieFileOutput?
    private var detectionRequests: [VNRequest] = []
    private var visionModel: VNCoreMLModel?
    
    // MARK: - Throttling Properties
//      private var frameCounter = 0
//      private let detectionFrameInterval = 1 // Perform detection every 5th frame
    
    override init() {
        super.init()
        setupYOLOModel()
        checkCameraPermissions()
    }
    
    func setupYOLOModel() {
        do {
            guard let model8s = try? YOLOv8s(configuration: MLModelConfiguration()) else {
                setupObjectDetection()
                return
            }
//            guard let model = try? yolov8n(configuration: MLModelConfiguration()) else {
//                setupObjectDetection()
//                return
//            }
            
            let visionModel = try VNCoreMLModel(for: model8s.model)
            self.visionModel = visionModel
            print("YOLOv8n model loaded successfully")
        } catch {
            print("Failed to setup YOLO model: \(error)")
        }
    }
    
    func checkCameraPermissions() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            setupSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                if granted {
                    DispatchQueue.main.async {
                        self?.setupSession()
                    }
                }
            }
        default:
            print("Camera access denied")
        }
    }
    
    func setupSession() {
        if session.isRunning {
            session.stopRunning()
        }
        
        session.beginConfiguration()
        session.sessionPreset = .hd1280x720 ///Higher resolution for better detection
        
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            print("Back camera not available")
            return
        }
        
        self.videoDevice = device
        
        do {
            // Add video input
            let videoInput = try AVCaptureDeviceInput(device: device)
            if session.canAddInput(videoInput) {
                session.addInput(videoInput)
            }
            
            // Add video output for object detection
            videoOutput.alwaysDiscardsLateVideoFrames = true
            videoOutput.videoSettings = [
                kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_420YpCbCr8BiPlanarFullRange)
            ]
            videoOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "videoQueue"))
            
            if session.canAddOutput(videoOutput) {
                session.addOutput(videoOutput)
            }
            
            // Add movie output for recording
            movieOutput = AVCaptureMovieFileOutput()
            if let movieOutput = movieOutput, session.canAddOutput(movieOutput) {
                session.addOutput(movieOutput)
            }
            
            session.commitConfiguration()
            
            // Setup preview layer
            previewLayer.session = session
            previewLayer.videoGravity = .resizeAspectFill
            
            // Setup object detection with YOLO
            setupYOLODetection()
            
            DispatchQueue.global(qos: .userInitiated).async {
                self.session.startRunning()
            }
            
        } catch {
            print("Error setting up camera: \(error)")
        }
    }
    
    func setupYOLODetection() {
        guard let visionModel = visionModel else {
            print("YOLO model not available, falling back to built-in detection")
            setupObjectDetection()
            return
        }
        ///An image-analysis request that uses a Core ML model to process images.
        let detectionRequest = VNCoreMLRequest(model: visionModel) { [weak self] request, error in
            self?.processYOLODetectionResults(request: request, error: error)
        }
        
        // Configure for best performance with YOLO
        detectionRequest.imageCropAndScaleOption = .scaleFill
        
        detectionRequests = [detectionRequest]
        print("YOLO detection setup complete")
    }

    func setupObjectDetection() {
        // Load the YOLOv8n Core ML model
        guard let model = try? VNCoreMLModel(for: yolov8n().model) else {
            fatalError("Failed to load YOLOv8n model")
        }
        
        // Create a Vision request using the Core ML model
        let request = VNCoreMLRequest(model: model) { [weak self] request, error in
            guard let self = self else { return }
            if let error = error {
                print("Object detection error: \(error.localizedDescription)")
                return
            }
            self.processDetectionResults(request: request, error: nil)
        }
        
        // Configure the request
        request.imageCropAndScaleOption = .scaleFill
        
        // Assign to detectionRequests array
        detectionRequests = [request]
        
        print("Using YOLOv8n with Vision for object detection")
    }

    func startRecording() {
        guard let movieOutput else { return }
        
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("recording-\(Date().timeIntervalSince1970).mov")
        
        if !movieOutput.isRecording {
            if let connection = movieOutput.connection(with: .video) {
               
                if connection.isVideoOrientationSupported {
                    connection.videoOrientation = .portrait
                }
                if connection.isVideoStabilizationSupported {
                    connection.preferredVideoStabilizationMode = .auto
                }
            }
            
            movieOutput.startRecording(to: tempURL, recordingDelegate: self)
            isRecording = true
        }
    }
    
    func stopRecording() {
        guard let movieOutput, movieOutput.isRecording else { return }
        movieOutput.stopRecording()
        isRecording = false
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate
extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    
    ///This delegate method is called every time a video frame is captured from the camera.

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        ///Extracts the image buffer from the video frame:
        
//        frameCounter += 1
//        guard frameCounter % detectionFrameInterval == 0 else {
//            // Skip detection for this frame if it's not the interval frame
//            return
//        }
        
        // Reset frameCounter if it grows too large, though it's usually fine to just let it increment.
       
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        ///Creates a Vision request handler to process the image:
        
        let imageRequestHandler = VNImageRequestHandler(
            cvPixelBuffer: pixelBuffer,
            orientation: .up,
            options: [:]
        )
        
        ///Performs object detection using YOLO or other Vision requests:
        do {
            try imageRequestHandler.perform(detectionRequests)
        } catch {
            print("Failed to perform detection: \(error)")
        }
    }
    /*
     - This function handles the results returned by the YOLO model.
    - Processing YOLO Detection Results
     */
    private func processYOLODetectionResults(request: VNRequest, error: Error?) {
        let startTime = CACurrentMediaTime()
        
        if let error = error {
            print("YOLO detection error: \(error)")
            return
        }
        
        guard let observations = request.results as? [VNRecognizedObjectObservation] else {
            // YOLO might return different output format, try to handle it
            processAlternativeYOLOOutput(request.results)
            return
        }
        
        DispatchQueue.main.async { [weak self] in
            let detectionTime = (CACurrentMediaTime() - startTime) * 1000 // Convert to milliseconds
            
            ///Sorts by confidence and limits to top 10:

            let topDetections = observations.filter { $0.confidence > 0.5 }.sorted { $0.confidence > $1.confidence }.prefix(10) // Show more detections
            
            ///Converts results into readable labels
            ///Updates the UI with detected objects and detection time.
            self?.detectedObjects = topDetections.compactMap { observation in
                guard let topLabel = observation.labels.first else { return nil }
                let confidencePercentage = Int(topLabel.confidence * 100)
                return "\(topLabel.identifier) (\(confidencePercentage)%)"
            }
            
            self?.detectionTime = detectionTime
        }
    }
    
    private func processAlternativeYOLOOutput(_ results: [Any]?) {
        // Handle cases where YOLO output format might be different
        // This is a fallback method
        DispatchQueue.main.async { [weak self] in
            if let results = results, !results.isEmpty {
                self?.detectedObjects = ["YOLO detection working - processing results"]
            } else {
                self?.detectedObjects = ["No objects detected"]
            }
        }
    }
    
    private func processDetectionResults(request: VNRequest, error: Error?) {
        // Original built-in detection processing
        if let error = error {
            print("Detection error: \(error)")
            return
        }
        
        guard let observations = request.results as? [VNRecognizedObjectObservation] else { return }
        
        DispatchQueue.main.async { [weak self] in
            let topDetections = observations
                .filter { $0.confidence > 0.3 }
                .sorted { $0.confidence > $1.confidence }
                .prefix(5)
            
            self?.detectedObjects = topDetections.compactMap { observation in
                guard let topLabel = observation.labels.first else { return nil }
                let confidencePercentage = Int(topLabel.confidence * 100)
                return "\(topLabel.identifier) (\(confidencePercentage)%)"
            }
        }
    }
}

// MARK: - AVCaptureFileOutputRecordingDelegate
//Video Recording Events
extension CameraManager: AVCaptureFileOutputRecordingDelegate {
    
    //Start recording
    func fileOutput(_ output: AVCaptureFileOutput, didStartRecordingTo fileURL: URL, from connections: [AVCaptureConnection]) {
        print("Started recording to: \(fileURL)")
    }
    
    //Finish recording
    ///Logs recording start and end.
    ///Saves the video file URL for later use.
    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        if let error = error {
            print("Recording error: \(error)")
        } else {
            self.recordingURL = outputFileURL
            print("Finished recording to: \(outputFileURL)")
        }
    }
}

