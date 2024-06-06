//
//  OpenAIClient.swift
//  MaggieReader
//
//  Created by Steven Lamphear on 5/27/24.
//

import Foundation
import SwiftKeychainWrapper
import OpenAI

func saveAPIToken(token: String) {
    KeychainWrapper.standard.set(token, forKey: "OpenAIAPIToken")
}

func getAPIToken() -> String? {
    return KeychainWrapper.standard.string(forKey: "OpenAIAPIToken")
}

func getOpenAIClient() -> OpenAI? {
    guard let apiKey = getAPIToken() else {
        print("API Token is missing")
        return nil
    }
    return OpenAI(apiToken: apiKey)
}
