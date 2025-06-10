import SwiftUI

struct InstructionEditorView: View {
    @ObservedObject var vm: PromptViewModel
    @Binding var isPresented: Bool
    @State private var newName: String = ""
    @State private var newContent: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Edit Custom Instructions")
                .font(.headline)

            List {
                ForEach($vm.instructions) { $inst in
                    VStack(alignment: .leading, spacing: 6) {
                        TextField("Name", text: $inst.name)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                        
                        TextEditor(text: $inst.content)
                            .frame(height: 100)
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.gray.opacity(0.5)))

                        HStack {
                            Button("Delete") {
                                vm.deleteInstruction(id: $inst.wrappedValue.id)
                            }
                            .foregroundColor(.red)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .frame(maxHeight: 300)

            Divider()

            VStack(alignment: .leading, spacing: 6) {
                Text("Add New Instruction").font(.headline)
                TextField("Name", text: $newName)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                TextEditor(text: $newContent)
                    .frame(height: 100)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.gray.opacity(0.5)))
                Button("Add") {
                    vm.addInstruction(name: newName, content: newContent)
                    newName = ""
                    newContent = ""
                }
                .disabled(newName.isEmpty || newContent.isEmpty)
            }

            Spacer()

            HStack {
                Spacer()
                Button("Close") {
                    isPresented = false
                }
                .keyboardShortcut(.cancelAction)
                Spacer()
            }
        }
        .padding()
        .frame(minWidth: 500, minHeight: 600)
    }
}

struct InstructionEditorView_Previews: PreviewProvider {
    static var previews: some View {
        let vm = PromptViewModel()
        InstructionEditorView(vm: vm, isPresented: .constant(true))
    }
}
