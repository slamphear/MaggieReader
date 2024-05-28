//
//  OpenAIClient.swift
//  MaggieReader
//
//  Created by Steven Lamphear on 5/27/24.
//

import OpenAI
import SwiftKeychainWrapper

// Function to securely store the OpenAI API token
func saveAPIToken(token: String) {
    KeychainWrapper.standard.set(token, forKey: "OpenAIAPIToken")
}

// Function to retrieve the OpenAI API token securely
func getAPIToken() -> String? {
    return KeychainWrapper.standard.string(forKey: "OpenAIAPIToken")
}

// Function to initialize OpenAI client
func getOpenAIClient() -> OpenAI? {
    guard let apiKey = getAPIToken() else {
        print("API Token is missing")
        return nil
    }
    return OpenAI(apiToken: apiKey)
}
