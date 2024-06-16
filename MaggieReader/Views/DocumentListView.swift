//
//  DocumentListView.swift
//  MaggieReader
//
//  Created by Steven Lamphear on 5/29/24.
//

import SwiftUI

struct DocumentListView: View {
    @State private var items: [String] = UserDefaults.standard.stringArray(forKey: "savedItems") ?? []
    @State private var isPresentingNewEntryView = false
    @State private var isPresentingTokenAlert = false
    @State private var apiToken: String = ""

    var body: some View {
        NavigationView {
            List {
                ForEach(items, id: \.self) { item in
                    NavigationLink(destination: MediaPlayerView(inputText: item, audioURLs: getAudioURLs(for: item))) {
                        Text(item)
                            .lineLimit(1)
                    }
                }
                .onDelete(perform: deleteItems)
            }
            .navigationTitle("Maggie Reader")
            #if canImport(UIKit)
            .navigationBarItems(
                leading: HStack {
                    EditButton()
                    Button(action: {
                        isPresentingTokenAlert = true
                    }) {
                        Text("Update API Key")
                    }
                },
                trailing: Button(action: {
                    isPresentingNewEntryView = true
                }) {
                    Image(systemName: "plus")
                }
            )
            #else
            .toolbar {
                ToolbarItem(placement: .automatic) {
                    Button(action: {
                        isPresentingNewEntryView = true
                    }) {
                        Image(systemName: "plus")
                    }
                }
            }
            #endif
            .sheet(isPresented: $isPresentingNewEntryView) {
                NewEntryView(items: $items, isPresentingNewEntryView: $isPresentingNewEntryView)
            }
            .alert(isPresented: $isPresentingTokenAlert) {
                Alert(
                    title: Text("Enter API Token"),
                    message: Text("Please enter your OpenAI API token:"),
                    primaryButton: .default(Text("Save"), action: {
                        saveAPIToken(token: apiToken)
                    }),
                    secondaryButton: .cancel()
                )
            }
        }
        .onAppear {
            loadAPIToken()
        }
    }

    func getAudioURLs(for item: String) -> [URL] {
        if let data = UserDefaults.standard.data(forKey: item),
           let fileNames = try? JSONDecoder().decode([String].self, from: data) {
            let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            return fileNames.map { documentsDirectory.appendingPathComponent($0) }
        }
        return []
    }

    func deleteItems(at offsets: IndexSet) {
        for index in offsets {
            let item = items[index]
            // Delete audio files
            let urls = getAudioURLs(for: item)
            for url in urls {
                try? FileManager.default.removeItem(at: url)
            }
            UserDefaults.standard.removeObject(forKey: item)
        }
        items.remove(atOffsets: offsets)
        UserDefaults.standard.set(items, forKey: "savedItems")
    }

    func loadAPIToken() {
        if let token = getAPIToken() {
            apiToken = token
        }
    }
}
