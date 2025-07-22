import AVFoundation
import SwiftUI
import Photos
import CoreLocation

class CameraModel: NSObject, ObservableObject, AVCapturePhotoCaptureDelegate, CLLocationManagerDelegate {
    @Published var session = AVCaptureSession()
    @Published var alert = false
    @Published var output = AVCapturePhotoOutput()
    @Published var preview: AVCaptureVideoPreviewLayer!
    @Published var isProcessingPhoto = false
    @Published var lastAuthenticationResult: String = ""
    
    private var isUsingFrontCamera = false
    var videoInput: AVCaptureDeviceInput?
    
    // Location manager for GPS coordinates (optional)
    private let locationManager = CLLocationManager()
    private var currentLocation: CLLocation?

    override init() {
        super.init()
        setupLocationManager()
    }
    
    private func setupLocationManager() {
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.requestWhenInUseAuthorization()
    }
    
    // MARK: - Location Manager Delegate
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        currentLocation = locations.last
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("Location error: \(error.localizedDescription)")
    }

    func checkPermissions() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            setUp()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { status in
                if status {
                    DispatchQueue.main.async {
                        self.setUp()
                    }
                }
            }
        case .denied:
            self.alert.toggle()
        default:
            return
        }
    }
    
    func setUp() {
        do {
            self.session.beginConfiguration()
            
            // Get back camera
            guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
                return
            }
            
            // Create input
            let input = try AVCaptureDeviceInput(device: device)
            
            // Check if we can add input and output
            if self.session.canAddInput(input) {
                self.session.addInput(input)
                self.videoInput = input
            }
            
            if self.session.canAddOutput(self.output) {
                self.session.addOutput(self.output)
            }
            
            self.session.commitConfiguration()
            
            // Start the session
            DispatchQueue.global(qos: .background).async {
                self.session.startRunning()
            }
            
            // Start location updates if authorized
            if CLLocationManager.locationServicesEnabled() {
                locationManager.startUpdatingLocation()
            }
        } catch {
            print("Camera setup error: \(error.localizedDescription)")
        }
    }

    func setupSession() {
        session.beginConfiguration()
        // Remove existing inputs
        if let input = videoInput {
            session.removeInput(input)
        }
        // Choose new camera
        let deviceType: AVCaptureDevice.Position = isUsingFrontCamera ? .front : .back
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: deviceType),
              let newInput = try? AVCaptureDeviceInput(device: device) else {
            print("Failed to get camera input")
            session.commitConfiguration()
            return
        }
        if session.canAddInput(newInput) {
            session.addInput(newInput)
            videoInput = newInput
        }
        session.commitConfiguration()
    }

    func switchCamera() {
        isUsingFrontCamera.toggle()
        setupSession()
    }
    // Add this method to your CameraModel class
    func testAuthentication() {
        print("🧪 Testing PhotoAuthentication...")
        
        // Create some dummy image data for testing
        let testImage = UIImage(systemName: "camera")!
        guard let testImageData = testImage.pngData() else {
            print("❌ Failed to create test image data")
            DispatchQueue.main.async {
                self.lastAuthenticationResult = "Test failed - no image data"
            }
            return
        }
        
        print("✅ Created test image data: \(testImageData.count) bytes")
        
        // Test authentication
        guard let authData = PhotoAuthentication.shared.authenticatePhoto(
            imageData: testImageData,
            cameraPosition: "back",
            location: "40.7128,-74.0060"
        ) else {
            print("❌ Authentication failed")
            DispatchQueue.main.async {
                self.lastAuthenticationResult = "Authentication test failed ✗"
            }
            return
        }
        
        print("✅ Authentication successful!")
        print("   Hash: \(String(authData.imageHash.prefix(16)))...")
        print("   Timestamp: \(authData.timestamp)")
        print("   Device ID: \(String(authData.deviceId.prefix(8)))...")
        
        // Test verification
        if let authenticatedData = PhotoAuthentication.shared.embedAuthenticationInImage(
            originalImageData: testImageData,
            authData: authData
        ) {
            let verification = PhotoAuthentication.shared.verifyPhoto(imageData: authenticatedData)
            print("✅ Verification result: \(verification.isValid ? "VALID" : "INVALID")")
            
            DispatchQueue.main.async {
                self.lastAuthenticationResult = "Authentication system working ✓"
            }
        } else {
            DispatchQueue.main.async {
                self.lastAuthenticationResult = "Metadata embedding failed ✗"
            }
        }
    }
    func capturePhoto() {
        // Check if session is running
        guard session.isRunning else {
            print("Camera session is not running")
            return
        }
        
        // Check if we have an active video connection
        guard let videoConnection = output.connection(with: .video) else {
            print("No video connection available")
            return
        }
        
        // Ensure the connection is enabled
        if !videoConnection.isEnabled {
            print("Video connection is not enabled")
            return
        }
        
        // Update UI to show processing
        DispatchQueue.main.async {
            self.isProcessingPhoto = true
        }
        
        DispatchQueue.global(qos: .background).async {
            let settings = AVCapturePhotoSettings()
            settings.flashMode = .auto
            self.output.capturePhoto(with: settings, delegate: self)
        }
    }

    // AVCapturePhotoCaptureDelegate method
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        if let error = error {
            print("Photo capture error: \(error.localizedDescription)")
            DispatchQueue.main.async {
                self.isProcessingPhoto = false
                self.lastAuthenticationResult = "Capture failed: \(error.localizedDescription)"
            }
            return
        }
        
        // Handle the captured photo
        guard let imageData = photo.fileDataRepresentation() else {
            print("Could not get image data")
            DispatchQueue.main.async {
                self.isProcessingPhoto = false
                self.lastAuthenticationResult = "Failed to process image data"
            }
            return
        }
        
        // Authenticate the photo
        authenticateAndSavePhoto(imageData: imageData)
    }
    
    private func authenticateAndSavePhoto(imageData: Data) {
        let cameraPosition = isUsingFrontCamera ? "front" : "back"
        
        // Create location string if available
        let locationString: String? = {
            if let location = currentLocation {
                return "\(location.coordinate.latitude),\(location.coordinate.longitude)"
            }
            return nil
        }()
        
        // Authenticate the photo
        guard let authData = PhotoAuthentication.shared.authenticatePhoto(
            imageData: imageData,
            cameraPosition: cameraPosition,
            location: locationString
        ) else {
            print("Failed to authenticate photo")
            DispatchQueue.main.async {
                self.isProcessingPhoto = false
                self.lastAuthenticationResult = "Authentication failed"
            }
            return
        }
        
        // Embed authentication data in the image
        guard let authenticatedImageData = PhotoAuthentication.shared.embedAuthenticationInImage(
            originalImageData: imageData,
            authData: authData
        ) else {
            print("Failed to embed authentication data")
            DispatchQueue.main.async {
                self.isProcessingPhoto = false
                self.lastAuthenticationResult = "Failed to embed authentication"
            }
            return
        }
        
        // Save authenticated photo to photo library
        PHPhotoLibrary.requestAuthorization { status in
            if status == .authorized {
                PHPhotoLibrary.shared().performChanges({
                    let request = PHAssetCreationRequest.forAsset()
                    request.addResource(with: .photo, data: authenticatedImageData, options: nil)
                }) { success, error in
                    DispatchQueue.main.async {
                        self.isProcessingPhoto = false
                        if success {
                            print("Authenticated photo saved successfully")
                            self.lastAuthenticationResult = "Photo authenticated and saved ✓"
                            
                            // Optional: Verify the photo immediately after saving
                            let verification = PhotoAuthentication.shared.verifyPhoto(imageData: authenticatedImageData)
                            print("Immediate verification: \(verification.isValid ? "VALID" : "INVALID")")
                        } else if let error = error {
                            print("Error saving photo: \(error.localizedDescription)")
                            self.lastAuthenticationResult = "Save failed: \(error.localizedDescription)"
                        }
                    }
                }
            } else {
                DispatchQueue.main.async {
                    self.isProcessingPhoto = false
                    self.lastAuthenticationResult = "Photo library access denied"
                }
            }
        }
    }
    
    // MARK: - Verification Methods
    
    func verifySelectedPhoto(imageData: Data) -> (isValid: Bool, details: String) {
        let verification = PhotoAuthentication.shared.verifyPhoto(imageData: imageData)
        
        var details = "Verification: \(verification.isValid ? "VALID ✓" : "INVALID ✗")\n"
        
        if let authData = verification.authData {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .medium
            
            details += """
            
            Authentication Details:
            • Timestamp: \(formatter.string(from: authData.timestamp))
            • Camera: \(authData.cameraPosition.capitalized)
            • Device ID: \(String(authData.deviceId.prefix(8)))...
            • Version: \(authData.version)
            """
            
            if let location = authData.location {
                details += "\n• Location: \(location)"
            }
        } else {
            details += "\nNo authentication data found in image"
        }
        
        return (verification.isValid, details)
    }
}
