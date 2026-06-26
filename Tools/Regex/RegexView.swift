// Tools/Regex/RegexView.swift
// Stub — will be implemented in Task 3.
import SwiftUI

struct RegexView: View {
    @Environment(HistoryStore.self) private var historyStore
    @State private var viewModel: RegexViewModel?

    var body: some View {
        Group {
            if let vm = viewModel {
                RegexContentView(viewModel: vm)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear {
            if viewModel == nil {
                viewModel = RegexViewModel(
                    onSaveHistory: { [historyStore] entry in historyStore.save(entry) }
                )
            }
        }
    }
}

private struct RegexContentView: View {
    @Bindable var viewModel: RegexViewModel

    var body: some View {
        Text("Regex Tester — coming in Task 3")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
