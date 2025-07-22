//
//  ContentView.swift
//  Nocapcam
//
//  Created by andreas Graffin on 26/06/2025.
//

import SwiftUI
import AVFoundation
import Photos

struct ContentView: View {
    @ObservedObject private var camera = CameraModel()
    
    var body: some View {
        ZStack {
            // Camera preview
            CameraPreview(camera: camera)
                .ignoresSafeArea()
            
            // TOP: Authentication Status Area
            VStack {
                if camera.isProcessingPhoto {
                    HStack {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(0.8)
                        Text("Authenticating photo...")
                            .foregroundColor(.white)
                            .font(.caption)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.black.opacity(0.7))
                    .cornerRadius(20)
                    .padding(.top, 60)
                }
                
                if !camera.lastAuthenticationResult.isEmpty {
                    Text(camera.lastAuthenticationResult)
                        .foregroundColor(camera.lastAuthenticationResult.contains("✓") ? .green : .red)
                        .font(.caption)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color.black.opacity(0.7))
                        .cornerRadius(20)
                        .padding(.top, camera.isProcessingPhoto ? 5 : 60)
                        .onTapGesture {
                            // Clear the message when tapped
                            camera.lastAuthenticationResult = ""
                        }
                }
                
                Spacer()
            }
            
            // RIGHT: Camera Switch Button
            HStack {
                Spacer()
                VStack {
                    Button(action: {
                        camera.switchCamera()
                    }) {
                        Image(systemName: "arrow.triangle.2.circlepath.camera")
                            .resizable()
                            .frame(width: 30, height: 25)
                            .foregroundColor(.white)
                            .padding()
                            .background(Color.black.opacity(0.5))
                            .clipShape(Circle())
                    }
                    Spacer()
                }
            }
            .padding()

            // BOTTOM: Capture Button
            VStack {
                Spacer()
                
                Button(action: {
                    camera.capturePhoto()
                }) {
                    ZStack {
                        Circle()
                            .fill(Color.yellow)
                            .frame(width: 65, height: 65)
                            .overlay(
                                Circle()
                                    .stroke(Color.black, lineWidth: 2)
                                    .frame(width: 60, height: 60)
                            )
                        
                        // Show progress indicator on capture button when processing
                        if camera.isProcessingPhoto {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .black))
                                .scaleEffect(0.8)
                        }
                    }
                }
                .disabled(camera.isProcessingPhoto)
                .padding(.bottom, 30)
            }
        }
        .onAppear {
            camera.checkPermissions()
            // Add this test to verify authentication is working
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                camera.testAuthentication()
            }
        }
    }
}

struct CameraPreview: UIViewRepresentable {
    @ObservedObject var camera: CameraModel
    
    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: UIScreen.main.bounds)
        
        camera.preview = AVCaptureVideoPreviewLayer(session: camera.session)
        camera.preview.frame = view.frame
        camera.preview.videoGravity = .resizeAspectFill
        view.layer.addSublayer(camera.preview)
        
        return view
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {
        
    }
}

#Preview {
    ContentView()
}
