//
//  PhotoAuthentification.swift
//  AuthenticCamera
//
//  Created by andreas Graffin on 29/06/2025.
//

import Foundation
import CryptoKit
import Security
import UIKit
import ImageIO
import MobileCoreServices

class PhotoAuthentication {
    static let shared = PhotoAuthentication()
    
    private let keyTag = "com.yourapp.photo.authentication.key"
    private let authenticationVersion = "1.0"
    
    private init() {
        // Ensure we have a signing key on initialization
        _ = getOrCreateSigningKey()
    }
    
    // MARK: - Key Management
    
    private func getOrCreateSigningKey() -> SecKey? {
        // First try to retrieve existing key
        if let existingKey = getSigningKey() {
            return existingKey
        }
        
        // Create new key if none exists
        return createSigningKey()
    }
    
    private func getSigningKey() -> SecKey? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: keyTag.data(using: .utf8)!,
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecReturnRef as String: true
        ]
        
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        if status == errSecSuccess {
            return (result as! SecKey)
        }
        
        return nil
    }
    
    private func createSigningKey() -> SecKey? {
        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeySizeInBits as String: 256,
            kSecAttrTokenID as String: kSecAttrTokenIDSecureEnclave,
            kSecPrivateKeyAttrs as String: [
                kSecAttrIsPermanent as String: true,
                kSecAttrApplicationTag as String: keyTag.data(using: .utf8)!,
                kSecAttrAccessControl as String: SecAccessControlCreateWithFlags(
                    kCFAllocatorDefault,
                    kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
                    .privateKeyUsage,
                    nil
                )!
            ]
        ]
        
        var error: Unmanaged<CFError>?
        guard let privateKey = SecKeyCreateRandomKey(attributes as CFDictionary, &error) else {
            print("Failed to create signing key: \(error!.takeRetainedValue())")
            return nil
        }
        
        return privateKey
    }
    
    // MARK: - Device Identification
    
    private func getDeviceIdentifier() -> String {
        // Create a consistent device identifier
        // Note: This is a simplified version - you might want to use more sophisticated device fingerprinting
        let deviceModel = UIDevice.current.model
        let systemVersion = UIDevice.current.systemVersion
        
        // Use a combination of device info and keychain-stored UUID
        if let storedUUID = getStoredDeviceUUID() {
            return storedUUID
        } else {
            let newUUID = UUID().uuidString
            storeDeviceUUID(newUUID)
            return newUUID
        }
    }
    
    private func getStoredDeviceUUID() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.yourapp.device.uuid",
            kSecReturnData as String: true
        ]
        
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        if status == errSecSuccess,
           let data = result as? Data,
           let uuid = String(data: data, encoding: .utf8) {
            return uuid
        }
        
        return nil
    }
    
    private func storeDeviceUUID(_ uuid: String) {
        let data = uuid.data(using: .utf8)!
        let attributes: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.yourapp.device.uuid",
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        ]
        
        SecItemAdd(attributes as CFDictionary, nil)
    }
    
    // MARK: - Photo Authentication
    
    struct AuthenticationData {
        let imageHash: String
        let timestamp: Date
        let deviceId: String
        let signature: String
        let version: String
        let cameraPosition: String
        let location: String? // Optional GPS coordinates
    }
    
    func authenticatePhoto(imageData: Data, cameraPosition: String, location: String? = nil) -> AuthenticationData? {
        // 1. Generate hash of the original image data
        let imageHash = SHA256.hash(data: imageData)
        let hashString = imageHash.compactMap { String(format: "%02x", $0) }.joined()
        
        // 2. Get current timestamp
        let timestamp = Date()
        
        // 3. Get device identifier
        let deviceId = getDeviceIdentifier()
        
        // 4. Create payload to sign
        let payload = createSignaturePayload(
            hash: hashString,
            timestamp: timestamp,
            deviceId: deviceId,
            cameraPosition: cameraPosition,
            location: location
        )
        
        // 5. Sign the payload
        guard let signature = signPayload(payload) else {
            print("Failed to sign photo authentication data")
            return nil
        }
        
        return AuthenticationData(
            imageHash: hashString,
            timestamp: timestamp,
            deviceId: deviceId,
            signature: signature,
            version: authenticationVersion,
            cameraPosition: cameraPosition,
            location: location
        )
    }
    
    private func createSignaturePayload(hash: String, timestamp: Date, deviceId: String, cameraPosition: String, location: String?) -> String {
        let timestampString = ISO8601DateFormatter().string(from: timestamp)
        var payload = "\(hash)|\(timestampString)|\(deviceId)|\(cameraPosition)|\(authenticationVersion)"
        if let location = location {
            payload += "|\(location)"
        }
        return payload
    }
    
    private func signPayload(_ payload: String) -> String? {
        guard let privateKey = getOrCreateSigningKey(),
              let payloadData = payload.data(using: .utf8) else {
            return nil
        }
        
        let algorithm = SecKeyAlgorithm.ecdsaSignatureMessageX962SHA256
        
        var error: Unmanaged<CFError>?
        guard let signature = SecKeyCreateSignature(
            privateKey,
            algorithm,
            payloadData as CFData,
            &error
        ) else {
            print("Failed to create signature: \(error!.takeRetainedValue())")
            return nil
        }
        
        let signatureData = signature as Data
        return signatureData.base64EncodedString()
    }
    
    // MARK: - Metadata Embedding
    
    func embedAuthenticationInImage(originalImageData: Data, authData: AuthenticationData) -> Data? {
        guard let imageSource = CGImageSourceCreateWithData(originalImageData as CFData, nil),
              let imageType = CGImageSourceGetType(imageSource) else {
            print("Failed to create image source")
            return nil
        }
        
        // Create mutable data for the new image
        let mutableData = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(mutableData, imageType, 1, nil) else {
            print("Failed to create image destination")
            return nil
        }
        
        // Get existing metadata
        var metadata = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [String: Any] ?? [:]
        
        // Add our authentication data to custom metadata
        var customMetadata: [String: Any] = [:]
        customMetadata["AuthHash"] = authData.imageHash
        customMetadata["AuthTimestamp"] = ISO8601DateFormatter().string(from: authData.timestamp)
        customMetadata["AuthDeviceId"] = authData.deviceId
        customMetadata["AuthSignature"] = authData.signature
        customMetadata["AuthVersion"] = authData.version
        customMetadata["AuthCameraPosition"] = authData.cameraPosition
        
        if let location = authData.location {
            customMetadata["AuthLocation"] = location
        }
        
        // Add to metadata under a custom key
        metadata["PhotoAuthentication"] = customMetadata
        
        // Add the image with updated metadata
        CGImageDestinationAddImageFromSource(destination, imageSource, 0, metadata as CFDictionary)
        
        // Finalize the image
        guard CGImageDestinationFinalize(destination) else {
            print("Failed to finalize image with metadata")
            return nil
        }
        
        return mutableData as Data
    }
    
    // MARK: - Verification
    
    func verifyPhoto(imageData: Data) -> (isValid: Bool, authData: AuthenticationData?) {
        // Extract authentication data from metadata
        guard let authData = extractAuthenticationData(from: imageData) else {
            return (false, nil)
        }
        
        // Verify the hash matches current image
        let currentHash = SHA256.hash(data: imageData)
        let currentHashString = currentHash.compactMap { String(format: "%02x", $0) }.joined()
        
        if currentHashString != authData.imageHash {
            print("Hash mismatch - image has been tampered with")
            return (false, authData)
        }
        
        // Verify signature
        let payload = createSignaturePayload(
            hash: authData.imageHash,
            timestamp: authData.timestamp,
            deviceId: authData.deviceId,
            cameraPosition: authData.cameraPosition,
            location: authData.location
        )
        
        let isSignatureValid = verifySignature(payload: payload, signature: authData.signature)
        
        return (isSignatureValid, authData)
    }
    
    private func extractAuthenticationData(from imageData: Data) -> AuthenticationData? {
        guard let imageSource = CGImageSourceCreateWithData(imageData as CFData, nil),
              let metadata = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [String: Any],
              let authMetadata = metadata["PhotoAuthentication"] as? [String: Any] else {
            return nil
        }
        
        guard let hash = authMetadata["AuthHash"] as? String,
              let timestampString = authMetadata["AuthTimestamp"] as? String,
              let timestamp = ISO8601DateFormatter().date(from: timestampString),
              let deviceId = authMetadata["AuthDeviceId"] as? String,
              let signature = authMetadata["AuthSignature"] as? String,
              let version = authMetadata["AuthVersion"] as? String,
              let cameraPosition = authMetadata["AuthCameraPosition"] as? String else {
            return nil
        }
        
        let location = authMetadata["AuthLocation"] as? String
        
        return AuthenticationData(
            imageHash: hash,
            timestamp: timestamp,
            deviceId: deviceId,
            signature: signature,
            version: version,
            cameraPosition: cameraPosition,
            location: location
        )
    }
    
    private func verifySignature(payload: String, signature: String) -> Bool {
        guard let privateKey = getSigningKey(),
              let publicKey = SecKeyCopyPublicKey(privateKey),
              let payloadData = payload.data(using: .utf8),
              let signatureData = Data(base64Encoded: signature) else {
            return false
        }
        
        let algorithm = SecKeyAlgorithm.ecdsaSignatureMessageX962SHA256
        
        var error: Unmanaged<CFError>?
        let result = SecKeyVerifySignature(
            publicKey,
            algorithm,
            payloadData as CFData,
            signatureData as CFData,
            &error
        )
        
        if let error = error {
            print("Signature verification error: \(error.takeRetainedValue())")
        }
        
        return result
    }
}
