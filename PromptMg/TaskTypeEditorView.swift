import SwiftUI

struct TaskTypeEditorView: View {
    @ObservedObject var vm: PromptViewModel
    @Binding var isPresented: Bool

    @State private var newTaskType: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Edit Task Types")
                .font(.headline)
            List {
                ForEach(vm.taskTypeOptions.indices, id: \.self) { idx in
                    HStack {
                        TextField("Name", text: $vm.taskTypeOptions[idx])
                        Button("Delete") {
                            vm.deleteTaskType(at: idx)
                        }
                        .foregroundColor(.red)
                    }
                }
            }
            .frame(maxHeight: 300)
            Divider()
            HStack(spacing: 8) {
                TextField("New Task Type", text: $newTaskType)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                Button("Add") {
                    vm.addTaskType(newTaskType)
                    newTaskType = ""
                }
                .disabled(newTaskType.isEmpty)
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
        .frame(minWidth: 400, minHeight: 400)
    }
}

struct TaskTypeEditorView_Previews: PreviewProvider {
    static var previews: some View {
        TaskTypeEditorView(vm: PromptViewModel(), isPresented: .constant(true))
    }
}
