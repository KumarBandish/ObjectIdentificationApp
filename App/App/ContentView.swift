//
//  ContentView.swift
//  App
//
//  Created by Bandish Kumar on 03/11/25.
//
import SwiftUI
internal import AVFoundation

struct ContentView: View {
    @StateObject private var cameraManager = CameraManager()
    @State private var showAlert = false
    @State private var alertMessage = ""
    
    var body: some View {
        ZStack {
            // Camera Preview
            CameraPreview(cameraManager: cameraManager)
                .edgesIgnoringSafeArea(.all)
            
            VStack {
                // Header with status info
                HStack {
                    VStack(alignment: .leading) {
                        if cameraManager.isRecording {
                            HStack {
                                Circle()
                                    .fill(Color.red)
                                    .frame(width: 8, height: 8)
                                Text("REC")
                                    .font(.caption)
                                    .foregroundColor(.red)
                            }
                        }
                        
                        Text("Object Detection")
                            .font(.headline)
                            .foregroundColor(.white)
                        
                        Text("\(cameraManager.detectionTime, specifier: "%.1f") ms")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.8))
                    }
                    
                    Spacer()
                    
                }
                .padding()
                
                Spacer()
                
                // Detected Objects Display
                if !cameraManager.detectedObjects.isEmpty {
                    ScrollView {
                        VStack(alignment: .leading) {
                            Text("Detected Objects:")
                                .font(.headline)
                                .foregroundColor(.white)
                            
                            LazyVStack(alignment: .leading, spacing: 4) {
                                ForEach(cameraManager.detectedObjects, id: \.self) { object in
                                    HStack {
                                        Circle()
                                            .fill(Color.green)
                                            .frame(width: 6, height: 6)
                                        Text(object)
                                            .font(.system(size: 14, weight: .medium))
                                    }
                                    .padding(6)
                                    .background(Color.black.opacity(0.7))
                                    .foregroundColor(.white)
                                    .cornerRadius(6)
                                }
                            }
                        }
                    }
                    .frame(maxHeight: 200)
                    .padding()
                    .background(Color.black.opacity(0.5))
                    .cornerRadius(12)
                    .padding()
                } else {
                   // Show waiting message
                    Text("Detecting objects...")
                        .padding()
                        .background(Color.black.opacity(0.5))
                        .foregroundColor(.white)
                        .cornerRadius(8)
                        .padding()
                }
                
                // Recording Button
                HStack {
                    Spacer()
                    
                    Button(action: {
                        if cameraManager.isRecording {
                            cameraManager.stopRecording()
                        } else {
                            cameraManager.startRecording()
                        }
                    }) {
                        ZStack {
                            Circle()
                                .fill(cameraManager.isRecording ? Color.red : Color.white)
                                .frame(width: 70, height: 70)
                            
                            if cameraManager.isRecording {
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Color.white)
                                    .frame(width: 25, height: 25)
                            } else {
                                Circle()
                                    .stroke(Color.white, lineWidth: 4)
                                    .frame(width: 80, height: 80)
                            }
                        }
                    }
                    
                    Spacer()
                }
                .padding(.bottom, 50)
            }
        }
        .onAppear {
            if !cameraManager.session.isRunning {
                cameraManager.checkCameraPermissions()
            }
        }
        .alert(isPresented: $showAlert) {
            Alert(title: Text("Info"), message: Text(alertMessage), dismissButton: .default(Text("OK")))
        }
    }
}
#Preview {
    ContentView()
}
