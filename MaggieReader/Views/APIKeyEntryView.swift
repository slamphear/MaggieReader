//
//  APIKeyEntryView.swift
//  MaggieReader
//
//  Created by Steven Lamphear on 5/29/24.
//

import SwiftUI

struct APIKeyEntryView: View {
    @Binding var apiToken: String
    @Binding var isAPITokenEntered: Bool

    var body: some View {
        VStack {
            Text("Enter your OpenAI API token")
                .font(.headline)
                .padding()

            TextField("API Token", text: $apiToken)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .padding()

            Button("Save") {
                saveAPIToken(token: apiToken)
                isAPITokenEntered = true
            }
            .padding()
        }
        .padding()
    }
}
