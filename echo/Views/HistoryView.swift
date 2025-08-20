import SwiftUI

struct HistoryView: View {
  @ObservedObject private var historyManager = HistoryManager.shared
  @State private var searchText = ""
  @State private var selectedTranscription: TranscriptionHistory?
  @State private var showingDeleteAllAlert = false
  @State private var currentPage = 0
  @State private var isLoadingMore = false
  @State private var searchResults: [TranscriptionHistory] = []
  @State private var isSearching = false

  private let itemsPerPage = 50
  
  private var truncatedSearchText: String {
    if searchText.count <= 30 {
      return searchText
    }
    return String(searchText.prefix(30)) + "..."
  }

  var body: some View {
    VStack(spacing: 0) {

      HSplitView {
        // Left sidebar
        VStack(spacing: 12) {
          // Search input with spacing
          VStack(spacing: 0) {
            Spacer()
              .frame(height: 12)
            
            HStack {
              Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
              
              TextField("Search...", text: $searchText)
                .textFieldStyle(.plain)
                .onKeyPress(.escape) {
                  searchText = ""
                  return .handled
                }
                .onChange(of: searchText) {
                  currentPage = 0
                  performSearch()
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
            .padding(.horizontal)
          }
          
          if historyManager.allTranscriptions.isEmpty {
            emptyStateView
          } else if let error = historyManager.searchError, !searchText.isEmpty {
            searchErrorView(error: error)
          } else if !searchText.isEmpty && searchResults.isEmpty && !isSearching {
            noSearchResultsView
          } else {
            historyListWithoutSearch
          }
        }
        .frame(minWidth: 350, maxWidth: 500)

        // Right detail view
        VStack {
          if let selected = selectedTranscription {
            detailView(for: selected)
          } else {
            emptyDetailView
          }
        }
        .frame(minWidth: 400)
        .background(Color.white)
      }
    }
    .onAppear {
      // Ensure we present the latest data when the window opens
      historyManager.refresh()
    }
    .alert("Delete All Transcriptions", isPresented: $showingDeleteAllAlert) {
      Button("Cancel", role: .cancel) {}
      Button("Delete All", role: .destructive) {
        deleteAllTranscriptions()
      }
    } message: {
      Text("This will permanently delete all transcription history. This action cannot be undone.")
    }
  }


  private var emptyStateView: some View {
    VStack(spacing: 16) {
      Image(systemName: "text.bubble")
        .font(.system(size: 48))
        .foregroundColor(.secondary)

      Text("No Transcriptions Yet")
        .font(.title2)
        .fontWeight(.semibold)

      Text("Your transcription history will appear here after you start recording.")
        .foregroundColor(.secondary)
        .multilineTextAlignment(.center)
        .padding(.horizontal)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  private var noSearchResultsView: some View {
    VStack(spacing: 16) {
      Image(systemName: "magnifyingglass")
        .font(.system(size: 48))
        .foregroundColor(.secondary)

      Text("No Results Found")
        .font(.title2)
        .fontWeight(.semibold)

      Text("No transcriptions match your search for \"\(truncatedSearchText)\"")
        .foregroundColor(.secondary)
        .multilineTextAlignment(.center)
        .padding(.horizontal)
      
      Button("Clear Search") {
        searchText = ""
      }
      .buttonStyle(.bordered)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  private func searchErrorView(error: String) -> some View {
    VStack(spacing: 16) {
      Image(systemName: "exclamationmark.triangle")
        .font(.system(size: 48))
        .foregroundColor(.orange)

      Text("Search Error")
        .font(.title2)
        .fontWeight(.semibold)

      Text("FTS5 search is not available. Please check your SQLite installation.")
        .foregroundColor(.secondary)
        .multilineTextAlignment(.center)
        .padding(.horizontal)
      
      Button("Clear Search") {
        searchText = ""
      }
      .buttonStyle(.bordered)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  private var emptyDetailView: some View {
    VStack(spacing: 16) {
      Image(systemName: "doc.text")
        .font(.system(size: 48))
        .foregroundColor(.secondary)

      Text("Select a transcription to view details")
        .font(.title2)
        .foregroundColor(.secondary)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  private var historyListWithoutSearch: some View {
    ScrollView {
      LazyVStack(spacing: 0) {
        ForEach(paginatedTranscriptions) { transcription in
          HistoryRowView(
            transcription: transcription,
            isSelected: selectedTranscription?.id == transcription.id,
            isFirstItem: transcription.id == paginatedTranscriptions.first?.id
          )
          .onTapGesture {
            selectedTranscription = transcription
          }
          .contextMenu {
            Button("Copy Text") {
              copyToClipboard(transcription.transcribedText)
            }

            Button("Delete", role: .destructive) {
              deleteTranscription(transcription)
            }
          }
        }

        if hasMorePages {
          loadingTriggerView
        } else if !filteredAndSortedTranscriptions.isEmpty {
          noMoreItemsView
        }
      }
      // .padding(.horizontal, 8)
    }
  }

  private var loadingTriggerView: some View {
    VStack {
      if isLoadingMore {
        HStack {
          ProgressView()
            .scaleEffect(0.8)
          Text("Loading more...")
            .font(.caption)
            .foregroundColor(.secondary)
        }
        .padding()
      } else {
        Color.clear
          .frame(height: 1)
      }
    }
    .onAppear {
      loadMoreItems()
    }
  }
  
  private var noMoreItemsView: some View {
    Text("No more transcriptions")
      .font(.caption)
      .foregroundColor(.secondary)
      .padding()
  }

  private var filteredAndSortedTranscriptions: [TranscriptionHistory] {
    if !searchText.isEmpty {
      return searchResults
    } else {
      // Return all transcriptions sorted by date (newest first)
      return historyManager.allTranscriptions.sorted { lhs, rhs in
        lhs.timestamp > rhs.timestamp
      }
    }
  }

  private var paginatedTranscriptions: [TranscriptionHistory] {
    let endIndex = min((currentPage + 1) * itemsPerPage, filteredAndSortedTranscriptions.count)
    return Array(filteredAndSortedTranscriptions.prefix(endIndex))
  }

  private var hasMorePages: Bool {
    filteredAndSortedTranscriptions.count > (currentPage + 1) * itemsPerPage
  }

  private func detailView(for transcription: TranscriptionHistory) -> some View {
    VStack(spacing: 0) {
      ScrollView {
        VStack(alignment: .leading, spacing: 16) {
          HStack {
            Text(transcription.formattedTimestamp)
              .font(.title2)
              .fontWeight(.semibold)
            
            Spacer()
            
            HStack(spacing: 8) {
              Button(action: {
                copyToClipboard(transcription.transcribedText)
              }) {
                HStack(spacing: 4) {
                  Image(systemName: "doc.on.doc")
                  Text("Copy")
                    .padding(.vertical, 4)
                }
              }
              .buttonStyle(.bordered)
              
              Button(role: .destructive, action: {
                deleteTranscription(transcription)
                selectedTranscription = nil
              }) {
                HStack(spacing: 4) {
                  Image(systemName: "trash")
                  Text("Delete")
                    .padding(.vertical, 4)
                  
                }
              }
              .buttonStyle(.bordered)
            }
          }

          VStack(alignment: .leading, spacing: 8) {
            metadataGrid(for: transcription)
          }
          .frame(maxWidth: .infinity, alignment: .leading)

          Divider()
            .padding(.vertical, 8)

          VStack(alignment: .leading, spacing: 12) {
            Text(transcription.transcribedText)
              .textSelection(.enabled)
          }
          .frame(maxWidth: .infinity, alignment: .leading)

          // Add extra space at bottom to prevent content from being hidden behind audio controls
          Spacer()
            .frame(height: 60)
        }
        .padding()
      }
      
      // Fixed audio controls at bottom
      AudioControlsView(transcription: transcription)
    }
  }

  private func metadataGrid(for transcription: TranscriptionHistory) -> some View {
    Grid(alignment: .topLeading, horizontalSpacing: 16, verticalSpacing: 8) {
      GridRow {
        Text("Duration:")
          .foregroundColor(.secondary)
        Text(transcription.formattedDuration)
      }

      GridRow {
        Text("Word Count:")
          .foregroundColor(.secondary)
        Text("\(transcription.wordCount)")
      }

      GridRow {
        Text("Model:")
          .foregroundColor(.secondary)
        Text(transcription.modelUsed)
      }

      if let app = transcription.applicationContext {
        GridRow {
          Text("Application:")
            .foregroundColor(.secondary)
          Text(app)
        }
      }

      if let language = transcription.languageDetected {
        GridRow {
          Text("Language:")
            .foregroundColor(.secondary)
          Text(language)
        }
      }

      GridRow {
        Text("Processing Time:")
          .foregroundColor(.secondary)
        Text(String(format: "%.2fs", transcription.totalTranscriptionTime))
      }
    }
  }

  private func deleteTranscription(_ transcription: TranscriptionHistory) {
    historyManager.deleteTranscription(id: transcription.id)
  }

  private func deleteAllTranscriptions() {
    historyManager.deleteAllTranscriptions()
    selectedTranscription = nil
    currentPage = 0
  }

  private func copyToClipboard(_ text: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)
  }
  
  private func loadMoreItems() {
    guard !isLoadingMore && hasMorePages else { return }
    
    isLoadingMore = true
    
    // Add a small delay to prevent rapid successive loads
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
      currentPage += 1
      isLoadingMore = false
    }
  }
  
  private func performSearch() {
    guard !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      searchResults = []
      isSearching = false
      return
    }
    
    isSearching = true
    
    Task {
      let results = await historyManager.searchWithSnippets(query: searchText)
      
      await MainActor.run {
        self.searchResults = results.map { (transcription, snippet) in
          TranscriptionHistory(
            id: transcription.id,
            timestamp: transcription.timestamp,
            transcribedText: transcription.transcribedText,
            duration: transcription.duration,
            audioFileReference: transcription.audioFileReference,
            languageDetected: transcription.languageDetected,
            modelUsed: transcription.modelUsed,
            wordCount: transcription.wordCount,
            applicationContext: transcription.applicationContext,
            uploadTime: transcription.uploadTime,
            groqProcessingTime: transcription.groqProcessingTime,
            totalTranscriptionTime: transcription.totalTranscriptionTime,
            confidence: transcription.confidence,
            searchSnippet: snippet
          )
        }
        self.isSearching = false
      }
    }
  }
}

struct HistoryRowView: View {
  let transcription: TranscriptionHistory
  let isSelected: Bool
  let isFirstItem: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(transcription.displayText)
        .lineLimit(3)
        .multilineTextAlignment(.leading)

      HStack {
        Text(transcription.relativeTimestamp)
          .font(.caption)
          .foregroundColor(.secondary)
        Spacer()

        Text("\(transcription.wordCount) words")
          .font(.caption)
          .foregroundColor(.secondary)
      }
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 10)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(
      RoundedRectangle(cornerRadius: 0)
        .fill(
          isSelected
            ? Color.accentColor.opacity(0.15) : Color(NSColor.controlBackgroundColor).opacity(0.3)
        )
    )
    .overlay(
      VStack(spacing: 0) {
        // Top border for first item
        if isFirstItem {
          Rectangle()
            .frame(height: 1)
            .foregroundColor(Color.gray.opacity(0.2))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        
        Spacer()
        
        // Bottom border for all items
        Rectangle()
          .frame(height: 1)
          .foregroundColor(Color.gray.opacity(0.2))
          .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
      }
    )
    // .padding(.vertical, 2)
  }
}

#Preview {
  HistoryView()
    .frame(width: 800, height: 600)
}
