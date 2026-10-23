import Foundation

/// Calculator rows appear above normal results whenever the query evaluates.
@MainActor
final class CalculatorProvider: CommandProvider {
    let id = "calculator"

    private var history: [String] = []

    init() {
        history = JSONStore.loadArray(String.self, named: "calculator-history.json")
    }

    func rootItems() -> [SearchItem] { [] }

    func items(for term: String, argument: String?) -> [SearchItem] {
        let expression = term.hasPrefix("=") ? String(term.dropFirst()) : term
        guard expression.contains(where: { $0.isNumber }) else { return [] }

        var value: Double
        do {
            value = try ExpressionEvaluator().evaluate(expression)
        } catch {
            return []
        }
        guard value.isFinite else { return [] }

        let formatted = NumberFormatterEngine.format(value)
        var rows: [SearchItem] = []

        rows.append(SearchItem(
            id: "calc:\(expression)",
            title: formatted,
            subtitle: "\(expression) = \(formatted)",
            icon: .symbol("equal.circle"),
            section: "Calculator",
            staticBoost: 400,
            actions: [
                ItemAction(id: "copy", title: "Copy Result", icon: "doc.on.doc", shortcut: "↩") {
                    PasteService.copy(text: formatted)
                },
                ItemAction(id: "paste", title: "Paste Result", icon: "doc.on.clipboard") {
                    PasteService.copy(text: formatted)
                    PasteService.paste()
                },
                ItemAction(id: "history", title: "Save to History", icon: "clock.arrow.circlepath") {
                    CalculatorProvider.appendHistory(expression)
                },
            ]
        ))

        for (label, representation) in NumberFormatterEngine.alternateRepresentations(value) {
            rows.append(SearchItem(
                id: "calc:\(expression):\(label)",
                title: representation,
                subtitle: "\(label) · \(expression)",
                icon: .symbol("number"),
                section: "Calculator",
                staticBoost: 100,
                actions: [
                    ItemAction(id: "copy", title: "Copy \(label)", icon: "doc.on.doc", shortcut: "↩") {
                        PasteService.copy(text: representation)
                    }
                ]
            ))
        }
        return rows
    }

    static func appendHistory(_ expression: String) {
        var items = JSONStore.loadArray(String.self, named: "calculator-history.json")
        items.removeAll { $0 == expression }
        items.insert(expression, at: 0)
        if items.count > 100 { items.removeLast(items.count - 100) }
        JSONStore.saveArray(items, named: "calculator-history.json")
    }

    func historyItems() -> [SearchItem] {
        let items = JSONStore.loadArray(String.self, named: "calculator-history.json")
        return items.map { expression in
            let result = (try? ExpressionEvaluator().evaluate(expression)).map(NumberFormatterEngine.format) ?? ""
            return SearchItem(
                id: "calc-history:\(expression)",
                title: result,
                subtitle: expression,
                icon: .symbol("clock.arrow.circlepath"),
                section: "Calculator History",
                actions: [
                    ItemAction(id: "copy", title: "Copy Result", icon: "doc.on.doc", shortcut: "↩") {
                        PasteService.copy(text: result)
                    }
                ]
            )
        }
    }
}
