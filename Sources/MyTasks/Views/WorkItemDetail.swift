import SwiftUI

/// Detalle de una tarea en popover: descripción y comentarios.
struct WorkItemDetailView: View {
    @Environment(AppState.self) private var app
    @Environment(\.colorScheme) private var systemColorScheme
    let item: WorkItem

    @State private var comments: [Comment]?

    private var fs: CGFloat { CGFloat(app.settings.fontScale) }
    private var isDark: Bool { (app.theme.colorScheme ?? systemColorScheme) == .dark }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                header
                Text(item.name)
                    .font(.system(size: 14 * fs, weight: .semibold))
                    .textSelection(.enabled)
                description
                Divider()
                commentsSection
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: 440 * fs)
        .frame(minHeight: 180, maxHeight: 540)
        // El popover vive en su propia ventana: sin esto sale con el material
        // claro del sistema mientras el texto hereda el tema (ilegible).
        .foregroundStyle(app.theme.primaryStyle)
        .fontDesign(app.theme.monospaced ? .monospaced : .default)
        .environment(\.colorScheme, app.theme.colorScheme ?? systemColorScheme)
        .presentationBackground(app.theme.background ?? Color(nsColor: .windowBackgroundColor))
        .task { comments = await app.comments(for: item) }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Text("\(app.selectedProject?.identifier ?? "")-\(item.sequenceId)")
                .font(.system(size: 11 * fs, design: .monospaced))
                .foregroundStyle(app.theme.secondaryStyle)
            if item.priority != "none" {
                Text(item.priority)
                    .font(.system(size: 10 * fs))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(Color.primary.opacity(0.08), in: Capsule())
            }
            Spacer()
            Button {
                if let project = app.selectedProject, let url = app.webURL(for: item, in: project) {
                    NSWorkspace.shared.open(url)
                }
            } label: {
                Image(systemName: "arrow.up.right.square")
            }
            .buttonStyle(.plain)
            .help("Abrir en Plane")
        }
    }

    @ViewBuilder
    private var description: some View {
        if let html = item.descriptionHtml, !Self.isBlank(html: html) {
            Text(Self.attributed(html: html, dark: isDark, fontSize: 12 * fs))
                .textSelection(.enabled)
        } else {
            Text("Sin descripción")
                .font(.system(size: 12 * fs))
                .foregroundStyle(.tertiary)
        }
    }

    @ViewBuilder
    private var commentsSection: some View {
        if let comments {
            if comments.isEmpty {
                Text("Sin comentarios")
                    .font(.system(size: 11 * fs))
                    .foregroundStyle(.tertiary)
            } else {
                Text("Comentarios (\(comments.count))")
                    .font(.system(size: 11 * fs, weight: .bold))
                    .foregroundStyle(app.theme.secondaryStyle)
                ForEach(comments) { comment in
                    commentView(comment)
                }
            }
        } else {
            ProgressView()
                .controlSize(.small)
                .frame(maxWidth: .infinity)
        }
    }

    private func commentView(_ comment: Comment) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(comment.actor.flatMap { app.member(id: $0)?.displayName } ?? "—")
                    .font(.system(size: 10 * fs, weight: .semibold))
                Text(Self.shortDateTime(comment.createdAt))
                    .font(.system(size: 10 * fs))
                    .foregroundStyle(.tertiary)
            }
            if let html = comment.commentHtml, !Self.isBlank(html: html) {
                Text(Self.attributed(html: html, dark: isDark, fontSize: 11 * fs))
                    .textSelection(.enabled)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 6))
    }

    // MARK: - Helpers

    /// Convierte el HTML de Plane a AttributedString con tipografía del sistema.
    /// NSAttributedString(html:) debe ejecutarse en el main thread.
    static func attributed(html: String, dark: Bool, fontSize: CGFloat) -> AttributedString {
        let css = """
        <style>
          body { font-family: -apple-system, sans-serif; font-size: \(Int(fontSize))px;
                 color: \(dark ? "#E8E8E8" : "#1A1A1A"); }
          code { font-family: ui-monospace, monospace; font-size: \(Int(fontSize) - 1)px; }
          a { color: \(dark ? "#6FB6FF" : "#0A66C2"); }
        </style>
        """
        guard let data = (css + html).data(using: .utf8),
              let ns = try? NSAttributedString(
                  data: data,
                  options: [
                      .documentType: NSAttributedString.DocumentType.html,
                      .characterEncoding: String.Encoding.utf8.rawValue,
                  ],
                  documentAttributes: nil
              )
        else { return AttributedString(html) }
        return AttributedString(ns)
    }

    /// true si el HTML no contiene texto visible (p. ej. "<p></p>").
    nonisolated static func isBlank(html: String) -> Bool {
        html.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty
    }

    /// "8 jul 2026, 21:57" desde el ISO con microsegundos de Plane.
    nonisolated static func shortDateTime(_ iso: String) -> String {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = fractional.date(from: iso) ?? ISO8601DateFormatter().date(from: iso) else {
            return ""
        }
        return date.formatted(date: .abbreviated, time: .shortened)
    }
}
