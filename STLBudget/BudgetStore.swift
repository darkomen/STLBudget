import Foundation
import Combine

struct SavedBudget: Identifiable, Codable {
    var id: UUID = UUID()
    var reference: String
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var recipient: String
    var title: String
    var status: String = "Borrador"
    var job: PrintJob
    var spoolDescription: String
    var pricePerGramAtSave: Double?
    var filamentCostAtSave: Double?
    var comments: String = ""
    // Optional: permite leer los presupuestos guardados por v0.2/v0.3.
    var dryerDuringPrint: Bool? = nil
    // Opcional para mantener compatibilidad con presupuestos ya guardados.
    var laborMinutes: Double? = nil
    var costSnapshot: CostBreakdown?
    var gcodeFilename: String?
}

@MainActor final class BudgetStore: ObservableObject {
    @Published private(set) var budgets: [SavedBudget] = []
    @Published var message: String?
    private var directory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("STLBudget", isDirectory: true)
    }
    private var indexURL: URL { directory.appendingPathComponent("budgets.json") }
    init() { load() }
    func load() {
        guard let data = try? Data(contentsOf: indexURL), let items = try? JSONDecoder().decode([SavedBudget].self, from: data) else { return }
        budgets = items.sorted { $0.createdAt > $1.createdAt }
    }
    private func persist() {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try JSONEncoder().encode(budgets).write(to: indexURL, options: .atomic)
        } catch { message = "No se pudo guardar el histórico: \(error.localizedDescription)" }
    }
    func add(job: PrintJob, recipient: String, title: String, status: String, comments: String, spool: Spool?, originalURL: URL?, costs: CostBreakdown? = nil, dryerDuringPrint: Bool = false, laborMinutes: Double = 0) -> UUID {
        let year = Calendar.current.component(.year, from: Date())
        let next = (budgets.compactMap { budget -> Int? in
            let parts = budget.reference.split(separator: "-")
            guard parts.count == 3, parts[1] == String(year) else { return nil }
            return Int(parts[2])
        }.max() ?? 0) + 1
        var item = SavedBudget(reference: String(format: "PRE-%d-%04d", year, next), recipient: recipient.trimmingCharacters(in: .whitespacesAndNewlines), title: title, status: status, job: job, spoolDescription: spool.map { "#\($0.id) · \($0.vendor) \($0.name)" } ?? "Bobina no encontrada", pricePerGramAtSave: spool?.pricePerGram, filamentCostAtSave: (spool?.pricePerGram).flatMap { rate in job.grams.map { rate * $0 } }, comments: comments, dryerDuringPrint: dryerDuringPrint, laborMinutes: laborMinutes, costSnapshot: costs)
        if let originalURL {
            do {
                try FileManager.default.createDirectory(at: directory.appendingPathComponent("GCodes"), withIntermediateDirectories: true)
                let filename = item.id.uuidString + ".gcode"
                let destination = directory.appendingPathComponent("GCodes").appendingPathComponent(filename)
                try FileManager.default.copyItem(at: originalURL, to: destination)
                item.gcodeFilename = filename
            } catch { message = "Presupuesto guardado, pero no se pudo copiar el G-code: \(error.localizedDescription)" }
        }
        budgets.insert(item, at: 0)
        persist()
        return item.id
    }
    func update(_ budget: SavedBudget) {
        guard let idx = budgets.firstIndex(where: { $0.id == budget.id }) else { return }
        var updated = budget; updated.updatedAt = Date()
        budgets[idx] = updated
        persist()
    }
    func remove(_ id: UUID) {
        guard let budget = budgets.first(where: { $0.id == id }) else { return }
        if let file = budget.gcodeFilename { try? FileManager.default.removeItem(at: directory.appendingPathComponent("GCodes").appendingPathComponent(file)) }
        budgets.removeAll { $0.id == id }
        persist()
    }
    func objects(for budget: SavedBudget) -> [GCodeObject] {
        if let detected = budget.job.objects, !detected.isEmpty { return detected }
        if let filename = budget.gcodeFilename {
            let url = directory.appendingPathComponent("GCodes").appendingPathComponent(filename)
            if let parsed = try? GCodeParser.parse(url), let detected = parsed.objects, !detected.isEmpty { return detected }
        }
        return [GCodeObject(name: budget.job.name, copies: 1)]
    }
    func duplicate(_ budget: SavedBudget) -> UUID {
        let original = budget.gcodeFilename.map { directory.appendingPathComponent("GCodes").appendingPathComponent($0) }
        // Preserve the original economic snapshot until the user explicitly recalculates it.
        let id = add(job: budget.job, recipient: budget.recipient, title: budget.title, status: "Borrador", comments: budget.comments, spool: nil, originalURL: original)
        if let idx = budgets.firstIndex(where: { $0.id == id }) {
            budgets[idx].dryerDuringPrint = budget.dryerDuringPrint
            budgets[idx].laborMinutes = budget.laborMinutes
            budgets[idx].costSnapshot = budget.costSnapshot
            budgets[idx].spoolDescription = budget.spoolDescription
            budgets[idx].pricePerGramAtSave = budget.pricePerGramAtSave
            budgets[idx].filamentCostAtSave = budget.filamentCostAtSave
            persist()
        }
        return id
    }
}
