import SwiftUI
import UniformTypeIdentifiers
import AppKit   // for NSOpenPanel
import Combine // Import Combine for debouncing

// MARK: - Data Models

/// Flat file info (for LOC and finalPrompt).
struct FileData: Identifiable {
    let id = UUID()
    let url: URL
    var contents: String
    let linesOfCode: Int
}

/// One custom‐instruction template.
struct CustomInstruction: Identifiable, Equatable {
    let id = UUID()
    var name: String
    var content: String
}

/// Node in a folder‐file tree. If `children == nil`, it's a file; otherwise, a folder.
struct FileNode: Identifiable {
    let id = UUID()
    let name: String
    let url: URL
    var children: [FileNode]?  // `nil` for files
}

/// Holds the results of the task difficulty calculation.
struct TaskDifficultyInfo {
    let score: Double
    let difficulty: String
    let fileCount: Int
    let totalLOC: Int

    /// Generates the formatted string for the hover-over tooltip.
    var tooltipText: String {
        let scoreFormatted = String(format: "%.2f", score)
        return """
        Based on \(fileCount) files and \(totalLOC) LOC:
        Score = \(scoreFormatted)
        Score ≤ 25: Easy
        25 < Score ≤ 50: Medium
        Score > 50: Hard
        """
    }
}

// MARK: - ViewModel

class PromptViewModel: ObservableObject {
    // Flat list of files for finalPrompt.
    @Published var files: [FileData] = []
    // Which file nodes are checked.
    @Published var selectedFileIDs: Set<UUID> = []
    // Hierarchical tree (root = selected folder).
    @Published var fileTree: [FileNode] = []

    // Task type and options
    @Published var taskType: String = "Feature"
    @Published var taskTypeOptions: [String] = [
        "Feature",
        "Bug fix",
        "Code refactoring",
        "Architect",
        "Engineer",
        "Atomic Task List"
    ]

    // Custom instructions templates
    @Published var instructions: [CustomInstruction] = [
        CustomInstruction(
            name: "Default",
            content:
            """
            Instructions for the output format:
            - Output code without descriptions, unless it is important.
            - Minimize prose, comments and empty lines.
            - Only show the relevant code that needs to be modified. Use comments to represent the parts that are not modified.
            - Make it easy to copy and paste.
            - Consider other possibilities to achieve the result, do not be limited by the prompt.
            """
        ),
        CustomInstruction(
            name: "Python 3.10",
            content:
            """
            Use Python 3.10 syntax.

            Prefer list comprehensions and f-strings.

            Instructions for the output format:
            - Output code without descriptions, unless it is important.
            - Minimize prose, comments and empty lines.
            - Only show the relevant code that needs to be modified. Use comments to represent the parts that are not modified.
            - Make it easy to copy and paste.
            - Consider other possibilities to achieve the result, do not be limited by the prompt.
            """
        ),
        CustomInstruction(
            name: "MySQL 8.0",
            content:
            """
            Use MySQL 8.0 syntax.

            Prefer CTEs and window functions.

            Instructions for the output format:
            - Output code without descriptions, unless it is important.
            - Minimize prose, comments and empty lines.
            - Only show the relevant code that needs to be modified. Use comments to represent the parts that are not modified.
            - Make it easy to copy and paste.
            - Consider other possibilities to achieve the result, do not be limited by the prompt.
            """
        ),
        CustomInstruction(
            name: "Next.js app router",
            content:
            """
            Use Next.js app router syntax.

            Use tailwindcss and TypeScript. Prefer functional components.

            Instructions for the output format:
            - Output code without descriptions, unless it is important.
            - Minimize prose, comments and empty lines.
            - Only show the relevant code that needs to be modified. Use comments to represent the parts that are not modified.
            - Make it easy to copy and paste.
            - Consider other possibilities to achieve the result, do not be limited by the prompt.
            """
        )
    ]
    @Published var selectedInstructionID: UUID? = nil

    // Raw prompt text
    @Published var taskInstruction: String = "Create a prompt manager app"

    // Stored properties for computed values
    @Published var finalPrompt: String = "Select a folder and files to begin."
    @Published var taskDifficulty: TaskDifficultyInfo = .init(score: 0, difficulty: "N/A", fileCount: 0, totalLOC: 0)

    // Combine properties for debouncing
    private var cancellables = Set<AnyCancellable>()

    init() {
        // Select the first custom instruction by default
        if let first = instructions.first {
            selectedInstructionID = first.id
        }

        // Recompute final prompt when anything changes, with a debounce
        let taskTypePublisher = $taskType
            .dropFirst()
            .map { _ in () }
            .eraseToAnyPublisher()
        let taskInstructionPublisher = $taskInstruction
            .dropFirst()
            .map { _ in () }
            .eraseToAnyPublisher()
        let selectedInstructionIDPublisher = $selectedInstructionID
            .dropFirst()
            .map { _ in () }
            .eraseToAnyPublisher()
        let selectedFileIDsPublisher = $selectedFileIDs
            .dropFirst()
            .map { _ in () }
            .eraseToAnyPublisher()

        Publishers.MergeMany([
            taskTypePublisher,
            taskInstructionPublisher,
            selectedInstructionIDPublisher,
            selectedFileIDsPublisher
        ])
        .debounce(for: .milliseconds(300), scheduler: DispatchQueue.main)
        .sink { [weak self] _ in
            self?.recompute()
        }
        .store(in: &cancellables)

        recompute() // Perform initial computation
    }
    
    var tokenCount: Int {
        // Using a rough estimate of 4 characters per token
        return finalPrompt.count / 4
    }

    var formattedTokenCount: String {
        let numberFormatter = NumberFormatter()
        numberFormatter.numberStyle = .decimal
        return numberFormatter.string(from: NSNumber(value: tokenCount)) ?? "\(tokenCount)"
    }
    
    private func recompute() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            // Logic from `selectedFiles`
            func allNodes(from tree: [FileNode]) -> [FileNode] {
                var nodes = [FileNode]()
                for node in tree {
                    nodes.append(node)
                    if let children = node.children {
                        nodes.append(contentsOf: allNodes(from: children))
                    }
                }
                return nodes
            }
            let nodes = allNodes(from: self.fileTree)
            let selectedNodes = nodes.filter { self.selectedFileIDs.contains($0.id) && $0.children == nil }
            let selectedURLs = Set(selectedNodes.map { $0.url })
            let selectedFiles = self.files.filter { selectedURLs.contains($0.url) }

            // Logic from `taskDifficulty`
            let fileCount = selectedFiles.count
            let totalLOC = selectedFiles.reduce(0) { $0 + $1.linesOfCode }
            let score = (Double(fileCount) * 5.0) + (Double(totalLOC) / 50.0)
            let difficulty: String
            if score <= 25 {
                difficulty = "Easy"
            } else if score <= 50 {
                difficulty = "Medium"
            } else {
                difficulty = "Hard"
            }
            let newDifficultyInfo = TaskDifficultyInfo(score: score, difficulty: difficulty, fileCount: fileCount, totalLOC: totalLOC)

            // Logic from `customInstructions`
            let customInstructions: String
            if let id = self.selectedInstructionID,
               let inst = self.instructions.first(where: { $0.id == id })
            {
                customInstructions = inst.content
            } else {
                customInstructions = ""
            }

            // Logic from `finalPrompt`
            let filesBlock: String
            if selectedFiles.isEmpty {
                filesBlock = "No files selected."
            } else {
                filesBlock = selectedFiles.map { file in
                    """
                    File: \(file.url.path)
                    ```
                    \(file.contents)
                    ```
                    """
                }.joined(separator: "\n\n")
            }
            let treeRepresentation = self.generateFileTreeString(from: self.fileTree)
            let newFinalPrompt: String
            switch self.taskType {
            case "Architect":
                newFinalPrompt = """
                <files>
                \(filesBlock)
                </files>
                <task-type>
                You are a senior software architect specializing in code design and implementation planning. Your role is to:
                1. Analyze the requested changes and break them down into clear, actionable steps
                2. Create a detailed implementation plan that includes:
                   - Files that need to be modified
                   - Specific code sections requiring changes
                   - New functions, methods, or classes to be added
                   - Dependencies or imports to be updated
                   - Data structure modifications
                   - Interface changes
                   - Configuration updates
                For each change:
                - Describe the exact location in the code where changes are needed
                - Explain the logic and reasoning behind each modification
                - Provide example signatures, parameters, and return types
                - Note any potential side effects or impacts on other parts of the codebase
                - Highlight critical architectural decisions that need to be made
                You may include short code snippets to illustrate specific patterns, signatures, or structures, but do not implement the full solution.
                Focus solely on the technical implementation plan - exclude testing, validation, and deployment considerations unless they directly impact the architecture.
                </task-type>
                <task-instruction>
                \(self.taskInstruction)
                </task-instruction>
                <custom-instruction>
                \(customInstructions)
                </custom-instruction>
                """
            case "Engineer":
                newFinalPrompt = """
                <files>
                \(filesBlock)
                </files>
                <task-type>
                You are a senior software engineer whose role is to provide clear, actionable code changes. For each edit required:
                1. Specify locations and changes:
                   - File path/name
                   - Function/class being modified
                   - The type of change (add/modify/remove)
                2. Show complete code for:
                   - Any modified functions (entire function)
                   - New functions or methods
                   - Changed class definitions
                   - Modified configuration blocks
                   Only show code units that actually change.
                Format all responses as:
                File: path/filename.ext
                Change: Brief description of what's changing
                ```language
                [Complete code block for this change]
                ```
                You only need to specify the file and path for the first change in a file, and split the rest into separate codeblocks.
                </task-type>
                <task-instruction>
                \(self.taskInstruction)
                </task-instruction>
                <custom-instruction>
                \(customInstructions)
                </custom-instruction>
                """
            case "Atomic Task List":
                newFinalPrompt = """
                <files>
                \(filesBlock)
                </files>
                <task-type>
                You are a senior dev.
                Goal: implement PRD below in <task-instruction>.
                Repo tree: ```\(treeRepresentation)```
                Return: numbered checklist (≤40 items) + file-scoped diff blocks.
                Break PRD into 30-40 atomic edits (new module, unit test, CI yaml tweak). Take PRD, output a checklist with file-level diffs where possible.
                </task-type>
                <task-instruction>
                \(self.taskInstruction)
                </task-instruction>
                <custom-instruction>
                \(customInstructions)
                </custom-instruction>
                """
            default:
                newFinalPrompt = """
                <files>
                \(filesBlock)
                </files>
                <task-type>
                You are tasked to implement a \(self.taskType.lowercased()). Instructions are as follows:
                </task-type>
                <task-instruction>
                \(self.taskInstruction)
                </task-instruction>
                <custom-instruction>
                \(customInstructions)
                </custom-instruction>
                """
            }
            
            DispatchQueue.main.async {
                self.finalPrompt = newFinalPrompt
                self.taskDifficulty = newDifficultyInfo
            }
        }
    }

    var customInstructions: String {
        if let id = selectedInstructionID,
           let inst = instructions.first(where: { $0.id == id }) {
            return inst.content
        }
        return ""
    }

    func addFile(_ url: URL) {
        DispatchQueue.global(qos: .userInitiated).async {
            if let contents = try? String(contentsOf: url, encoding: .utf8) {
                let newFile = FileData(url: url, contents: contents, linesOfCode: contents.split(separator: "\n").count)
                DispatchQueue.main.async {
                    self.files.append(newFile)
                }
            }
        }
    }

    /// Recursively build a FileNode for `url`. If directory, children != nil.
    private func buildNode(for url: URL) -> FileNode {
        var isDir: ObjCBool = false
        FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
        if isDir.boolValue {
            // Folder: list immediate contents
            let contents = (try? FileManager.default.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )) ?? []
            let childNodes = contents
                .sorted { $0.lastPathComponent.lowercased() < $1.lastPathComponent.lowercased() }
                .map { buildNode(for: $0) }
            return FileNode(name: url.lastPathComponent, url: url, children: childNodes)
        } else {
            // File: leaf
            return FileNode(name: url.lastPathComponent, url: url, children: nil)
        }
    }
    private func generateFileTreeString(from nodes: [FileNode], prefix: String = "") -> String {
        var treeString = ""
        for (index, node) in nodes.enumerated() {
            let isLastNode = index == nodes.count - 1
            let connector = isLastNode ? "└── " : "├── "
            treeString += prefix + connector + node.name + "\n"
            if let children = node.children {
                let newPrefix = prefix + (isLastNode ? "    " : "│   ")
                treeString += generateFileTreeString(from: children, prefix: newPrefix)
            }
        }
        return treeString
    }
    /// Called by "Add Folder…" button. Populates flat `files` and hierarchical `fileTree`.
    func addFolder(at folderURL: URL) {
        DispatchQueue.global(qos: .userInitiated).async {
            // 1) Build flat file list for finalPrompt
            var newFiles: [FileData] = []
            if let enumerator = FileManager.default.enumerator(
                at: folderURL,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles],
                errorHandler: nil
            ) {
                for case let fileURL as URL in enumerator {
                    var isDir: ObjCBool = false
                    if FileManager.default.fileExists(atPath: fileURL.path, isDirectory: &isDir),
                       !isDir.boolValue
                    {
                        if let contents = try? String(contentsOf: fileURL, encoding: .utf8) {
                            let newFile = FileData(
                                url: fileURL,
                                contents: contents,
                                linesOfCode: contents.split(separator: "\n").count
                            )
                            newFiles.append(newFile)
                        }
                    }
                }
            }

            // 2) Build hierarchical tree (root = folderURL)
            let rootNode = self.buildNode(for: folderURL)

            DispatchQueue.main.async {
                self.files = newFiles
                self.selectedFileIDs.removeAll()
                self.fileTree = [rootNode]
            }
        }
    }
    func addInstruction(name: String, content: String) {
        let newInstruction = CustomInstruction(name: name, content: content)
        instructions.append(newInstruction)
    }
    func updateInstruction(id: UUID, newName: String, newContent: String) {
        if let index = instructions.firstIndex(where: { $0.id == id }) {
            instructions[index].name = newName
            instructions[index].content = newContent
        }
    }
    func deleteInstruction(id: UUID) {
        let oldID = selectedInstructionID
        instructions.removeAll { $0.id == id }
        if oldID == id {
            selectedInstructionID = instructions.first?.id
        }
    }
    func addTaskType(_ type: String) {
        guard !type.isEmpty, !taskTypeOptions.contains(type) else { return }
        taskTypeOptions.append(type)
    }
    func deleteTaskType(at index: Int) {
        guard taskTypeOptions.indices.contains(index) else { return }
        let deletedType = taskTypeOptions.remove(at: index)
        if taskType == deletedType {
            taskType = taskTypeOptions.first ?? "Feature"
        }
    }
}

    // … you may keep other helper methods here …

// MARK: - ContentView

struct ContentView: View {
    @StateObject private var vm = PromptViewModel()
    @State private var isShowingInstructionEditor = false
    @State private var isShowingTaskTypeEditor = false
    @State private var showCopiedNotification = false
    @State private var taskInstructionBuffer: String = ""

    var body: some View {
        VStack(spacing: 0) {
            // ═══ Row 1: Top Toolbar ═══════════════════════════════════════════════════════
            HStack(alignment: .top, spacing: 16) {
                // Column A: Task Type + Folder Icon
                VStack(alignment: .leading, spacing: 4) {
                    Text("Task Type").font(.subheadline).bold()
                    HStack(spacing: 4) {
                        Picker("", selection: $vm.taskType) {
                            ForEach(vm.taskTypeOptions, id: \.self) {
                                Text($0)
                            }
                        }
                        .pickerStyle(MenuPickerStyle())
                        .frame(minWidth: 140)
// Upcoming Feature - edit Task Type
//                        Button {
//                            isShowingTaskTypeEditor = true
//                        }
//                        label: {
//                            Image(systemName: "folder")
//                                .imageScale(.medium)
//                                .padding(.trailing, 2)
//                        }
//                        .buttonStyle(PlainButtonStyle())
                    }
                }
                .frame(minWidth: 200, alignment: .leading)

                // Column B: Custom Instructions + Folder Icon
                VStack(alignment: .leading, spacing: 4) {
                    Text("Custom Instructions").font(.subheadline).bold()
                    HStack(spacing: 4) {
                        Picker("", selection: $vm.selectedInstructionID) {
                            ForEach(vm.instructions) { inst in
                                Text(inst.name).tag(inst.id as UUID?)
                            }
                        }
                        .pickerStyle(MenuPickerStyle())
                        .frame(minWidth: 140)
// Upcoming Feature - edit instructions
//                        Button {
//                            isShowingInstructionEditor = true
//                        } label: {
//                            Image(systemName: "folder")
//                                .imageScale(.medium)
//                                .padding(.trailing, 2)
//                        }
//                        .buttonStyle(PlainButtonStyle())
                    }
                }
                .frame(minWidth: 200, alignment: .leading)

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color(NSColor.windowBackgroundColor))

            // ═══ Row 2: Code Context (Left) ↔ Task Instruction (Right) ══════════════════════
            HStack(alignment: .top, spacing: 16) {
                // Left Pane: Code Context
                VStack(alignment: .leading, spacing: 8) {
                    Text("Code Context").font(.subheadline).bold()

                    // "Add Folder…" button
                    Button("Add Folder…") {
                        let panel = NSOpenPanel()
                        panel.canChooseDirectories = true
                        panel.canChooseFiles = false
                        panel.allowsMultipleSelection = false
                        panel.prompt = "Select Folder"
                        panel.title = "Add Folder to Context"

                        if panel.runModal() == .OK, let folderURL = panel.url {
                            vm.addFolder(at: folderURL)
                        }
                    }
                    .padding(.bottom, 4)

                    // Hierarchical tree of folders+files
                    ScrollView {
                        OutlineGroup(vm.fileTree, children: \.children) { node in
                            HStack {
                                if node.children == nil {
                                    Toggle(isOn: Binding(
                                        get: { vm.selectedFileIDs.contains(node.id) },
                                        set: { flag in
                                            if flag {
                                                vm.selectedFileIDs.insert(node.id)
                                            } else {
                                                vm.selectedFileIDs.remove(node.id)
                                            }
                                        }
                                    )) {
                                        Text(node.name)
                                    }
                                    Spacer()
                                    if let fileData = vm.files.first(where: { $0.url == node.url }) {
                                        Text("\(fileData.linesOfCode) LOC")
                                    }
                                } else {
                                                                Text(node.name).bold()
                                }
                            }
                        }
                    }
                    .frame(maxHeight: 300)
                }
                .frame(minWidth: 300)
                .padding()
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)

                // Right Pane: Task Instruction
                VStack(alignment: .leading, spacing: 4) {
                    Text("Task Instruction").font(.subheadline).bold()
                    TextEditor(text: $vm.taskInstruction)
                        .frame(minWidth: 300, minHeight: 120)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.gray.opacity(0.5))
                        )
                }
                .frame(minWidth: 360)
                .padding()
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)

            // ═══ Row 3: Final Prompt ═══════════════════════════════════════════════════════
            VStack(alignment: .leading, spacing: 4) {
                Text("Final Prompt").font(.subheadline).bold()
                ZStack(alignment: .bottom) {
                    ZStack(alignment: .topTrailing) {
                        TextEditor(text: .constant(vm.finalPrompt))
                            .font(.system(.body, design: .monospaced))
                            .frame(minHeight: 300)
                        
                        HStack(spacing: 12) {
                            Text("Task Difficulty: \(vm.taskDifficulty.difficulty)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .help(vm.taskDifficulty.tooltipText)
                            Text("[\(vm.formattedTokenCount)]/1m tokens")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Button {
                                let pasteboard = NSPasteboard.general
                                pasteboard.clearContents()
                                pasteboard.setString(vm.finalPrompt, forType: .string)
                                withAnimation {
                                    showCopiedNotification = true
                                }
                            } label: {
                                Image(systemName: "doc.on.doc")
                            }

// Upcoming Feature for sending via API
//                        Button {
//                            // Send final prompt
//                        } label: {
//                            Image(systemName: "paperplane")
//                        }
//                        Button {
//                            // Settings
//                        } label: {
//                            Image(systemName: "gearshape")
//                        }
                        }
                    }
                    .padding(8)
                }
            }
            .padding(.horizontal, 16)
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
            .padding(.bottom, 16)
        }
        .sheet(isPresented: $isShowingInstructionEditor) {
            InstructionEditorView(vm: vm, isPresented: $isShowingInstructionEditor)
        }
        .sheet(isPresented: $isShowingTaskTypeEditor) {
            TaskTypeEditorView(vm: vm, isPresented: $isShowingTaskTypeEditor)
        }
    }
}