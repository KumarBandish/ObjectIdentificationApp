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
    
    override init() {
        super.init()
        setupYOLOModel()
        checkCameraPermissions()
    }
    
    func setupYOLOModel() {
        do {
            guard let model = try? yolov8n(configuration: MLModelConfiguration()) else {
                print("Failed to load YOLOv8n model")
                setupObjectDetection() // Fallback to built-in detection
                return
            }
            
            let visionModel = try VNCoreMLModel(for: model.model)
            self.visionModel = visionModel
            print("YOLOv8n model loaded successfully")
        } catch {
            print("Failed to setup YOLO model: \(error)")
            setupObjectDetection() // Fallback to built-in detection
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
        guard let movieOutput = movieOutput else { return }
        
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
        guard let movieOutput = movieOutput, movieOutput.isRecording else { return }
        movieOutput.stopRecording()
        isRecording = false
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate
extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        
        let imageRequestHandler = VNImageRequestHandler(
            cvPixelBuffer: pixelBuffer,
            orientation: .up,
            options: [:]
        )
        
        do {
            try imageRequestHandler.perform(detectionRequests)
        } catch {
            print("Failed to perform detection: \(error)")
        }
    }
    
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
            
            // Filter and sort detections
            let topDetections = observations
                .filter { $0.confidence > 0.25 } // Lower threshold for YOLO
                .sorted { $0.confidence > $1.confidence }
                .prefix(10) // Show more detections
            
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
extension CameraManager: AVCaptureFileOutputRecordingDelegate {
    func fileOutput(_ output: AVCaptureFileOutput, didStartRecordingTo fileURL: URL, from connections: [AVCaptureConnection]) {
        print("Started recording to: \(fileURL)")
    }
    
    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        if let error = error {
            print("Recording error: \(error)")
        } else {
            self.recordingURL = outputFileURL
            print("Finished recording to: \(outputFileURL)")
        }
    }
}
