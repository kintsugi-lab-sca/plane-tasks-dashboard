import Foundation
import SwiftUI
import Testing
@testable import MyTasks

/// Decodificación con fixtures del shape real de la API (verificado con curl
/// contra la instancia) y helpers puros de los modelos.
struct ModelTests {
    private var decoder: JSONDecoder {
        let d = JSONDecoder()
        d.keyDecodingStrategy = .convertFromSnakeCase
        return d
    }

    @Test func decodeWorkItemDesdeShapeReal() throws {
        let json = """
        {
          "id": "bd069a34-af4d-40d0-b876-709b2ff2f83b",
          "name": "Revisar dashboard",
          "priority": "high",
          "sequence_id": 209,
          "state": "fc685c26-17c9-4727-9e1a-3797359e3763",
          "assignees": ["da60ae01-2464-40da-857d-5aeb558bd881"],
          "labels": [],
          "project": "add88b2b-5b48-4b33-92d0-802871a4e488",
          "start_date": null,
          "target_date": "2026-04-14",
          "description_html": "<p>Contexto</p>",
          "created_at": "2026-04-08T22:29:12.325847+02:00",
          "is_draft": false,
          "sort_order": 25535.0
        }
        """
        let item = try decoder.decode(WorkItem.self, from: Data(json.utf8))
        #expect(item.sequenceId == 209)
        #expect(item.priority == "high")
        #expect(item.targetDate == "2026-04-14")
        #expect(item.descriptionHtml == "<p>Contexto</p>")
    }

    @Test func decodePageEnvelope() throws {
        let json = """
        {
          "total_count": 1,
          "next_cursor": "100:1:0",
          "next_page_results": false,
          "results": [{"id": "x", "name": "n", "identifier": "ROMAN"}]
        }
        """
        let page = try decoder.decode(Page<Project>.self, from: Data(json.utf8))
        #expect(page.results.count == 1)
        #expect(page.nextPageResults == false)
    }

    @Test func decodeMemberComoUserLite() throws {
        let json = """
        {"id": "6ec41468", "first_name": "Erika", "last_name": "", "email": "e@x.com", "display_name": "erika"}
        """
        let member = try decoder.decode(UserLite.self, from: Data(json.utf8))
        #expect(member.displayName == "erika")
    }

    @Test func decodeComment() throws {
        let json = """
        {
          "id": "a9c7a43e",
          "comment_html": "<p>PR abierto</p>",
          "actor": "da60ae01",
          "created_at": "2026-07-08T21:57:27.946112+02:00"
        }
        """
        let comment = try decoder.decode(MyTasks.Comment.self, from: Data(json.utf8))
        #expect(comment.commentHtml == "<p>PR abierto</p>")
        #expect(comment.actor == "da60ae01")
    }

    @Test func priorityRankOrdenaBien() {
        let ranks = ["urgent", "high", "medium", "low", "none"].map {
            WorkItem(
                id: "i", name: "n", priority: $0, sequenceId: 1, state: "s",
                assignees: [], labels: [], project: "p",
                startDate: nil, targetDate: nil, descriptionHtml: nil
            ).priorityRank
        }
        #expect(ranks == ranks.sorted())
        #expect(Set(ranks).count == 5)
    }

    @Test func stateGroups() {
        let completed = WorkItemState(id: "s", name: "Done", color: "#000000", group: "completed", sequence: 1)
        let started = WorkItemState(id: "s", name: "Doing", color: "#000000", group: "started", sequence: 1)
        #expect(!completed.isActive)
        #expect(started.isActive)
        #expect(started.groupRank < completed.groupRank)
    }

    @Test func colorHex() {
        #expect(Color(hex: "#FF8800") != nil)
        #expect(Color(hex: "FF8800") != nil)
        #expect(Color(hex: "no-color") == nil)
        #expect(Color(hex: nil) == nil)
        #expect(Color(hex: "#FFF") == nil)
    }

    @Test func htmlBlank() {
        #expect(WorkItemDetailView.isBlank(html: "<p></p>"))
        #expect(WorkItemDetailView.isBlank(html: " <p>  \n </p> "))
        #expect(!WorkItemDetailView.isBlank(html: "<p>hola</p>"))
    }

    @Test func shortDateTimeParseaISOConMicrosegundos() {
        #expect(!WorkItemDetailView.shortDateTime("2026-07-08T21:57:27.946112+02:00").isEmpty)
        #expect(!WorkItemDetailView.shortDateTime("2026-07-08T21:57:27+02:00").isEmpty)
        #expect(WorkItemDetailView.shortDateTime("no es fecha") == "")
    }
}
