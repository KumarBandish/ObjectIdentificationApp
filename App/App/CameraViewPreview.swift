//
//  CameraViewPreview.swift
//  App
//
//  Created by Bandish Kumar on 03/11/25.
//

import SwiftUI
import Vision

// MARK: - BoundingBoxOverlay

struct CameraPreview: UIViewRepresentable {
    @ObservedObject var cameraManager: CameraManager
    
    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: UIScreen.main.bounds)
        cameraManager.previewLayer.frame = view.frame
        view.layer.addSublayer(cameraManager.previewLayer)
        return view
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        // Update view if needed
    }
}
