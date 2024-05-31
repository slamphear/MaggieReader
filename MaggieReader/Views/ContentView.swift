//
//  ContentView.swift
//  MaggieReader
//
//  Created by Steven Lamphear on 5/27/24.
//

import SwiftUI
import SwiftKeychainWrapper

struct ContentView: View {
    @State private var apiToken: String = ""
    @State private var isAPITokenEntered: Bool = false

    var body: some View {
        Group {
            if isAPITokenEntered {
                DocumentListView()
            } else {
                APIKeyEntryView(apiToken: $apiToken, isAPITokenEntered: $isAPITokenEntered)
            }
        }
        .onAppear {
            checkAPIToken()
        }
    }

    func checkAPIToken() {
        if let token = getAPIToken(), !token.isEmpty {
            apiToken = token
            isAPITokenEntered = true
        } else {
            isAPITokenEntered = false
        }
    }
}
