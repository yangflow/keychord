import SwiftUI

struct AccountsSidebar: View {
    let accounts: [Account]
    @Binding var selection: UUID?
    let onAddNew: () -> Void
    let onDelete: (UUID) -> Void
    let onImport: () -> Void

    var body: some View {
        List(selection: $selection) {
            Section {
                ForEach(accounts) { account in
                    AccountsSidebarRow(account: account)
                        .tag(account.id)
                }
            } header: {
                Text("ACCOUNTS")
                    .font(KC.sectionLabel)
                    .kerning(0.8)
                    .foregroundStyle(.tertiary)
            }
        }
        .listStyle(.sidebar)
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button(action: onAddNew) {
                    Label("Add", systemImage: "plus")
                }
                .help("Add new account")
            }
            ToolbarItem(placement: .automatic) {
                Button {
                    if let id = selection { onDelete(id) }
                } label: {
                    Label("Delete", systemImage: "minus")
                }
                .disabled(selection == nil)
                .help("Delete selected account")
            }
        }
    }
}

private struct AccountsSidebarRow: View {
    let account: Account

    var body: some View {
        HStack(spacing: KC.space10) {
            Circle()
                .fill(accountColor)
                .frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 2) {
                Text(account.label.isEmpty ? "(unnamed)" : account.label)
                    .font(KC.rowTitle)
                    .lineLimit(1)
                    .truncationMode(.tail)
                HStack(spacing: KC.space4) {
                    Text(account.sshAlias.isEmpty ? "no alias" : account.sshAlias)
                        .font(KC.rowCaptionMono)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if account.scope.isScoped {
                        Image(systemName: "folder.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, KC.space4)
    }

    private var accountColor: Color {
        switch account.color {
        case .blue:   return .blue
        case .green:  return .green
        case .orange: return .orange
        case .red:    return .red
        case .purple: return .purple
        case .yellow: return .yellow
        }
    }
}
