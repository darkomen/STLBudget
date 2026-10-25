import Foundation
import Combine

struct GCodeObject: Codable, Hashable {
    var name: String
    var copies: Int
}

struct PrintJob: Codable {
    var objects: [GCodeObject]? = nil
    var name: String
    var slicer: String = "—"
    var material: String = "—"
    var profile: String = "—"
    var spoolID: Int?
    var grams: Double?
    var durationSeconds: Int?
    var nozzleC: Double?
    var bedC: Double?
    var layers: Int?
    var thumbnail: Data?
    var notes: [String] = []
}

struct Spool: Identifiable, Codable, Hashable {
    var id: Int
    var material: String
    var name: String
    var vendor: String
    var colorHex: String
    var priceEUR: Double?
    var initialWeightG: Double?
    var remainingWeightG: Double?
    var updatedAt: Date
    var manualPrice: Double? = nil
    var effectivePriceEUR: Double? { manualPrice ?? priceEUR }
    var pricePerGram: Double? {
        guard let price = effectivePriceEUR, let weight = initialWeightG, weight > 0 else { return nil }
        return price / weight
    }
}

struct LocalCatalog: Codable {
    var serverURL: String = "http://klipper.local:81"
    var lastImported: Date?
    var spools: [Spool] = []
}


// Valores iniciales basados en mediciones PETG del 25/10/2026. Editables.
// La amortización de 169,69 € incluye todas las mejoras y el secador, se use o no.
struct CostSettings: Codable, Equatable {
    var printerWatts: Double = 99.6
    var electricityEURkWh: Double = 0.155
    var dryerWatts: Double = 59.1
    // Campo legado: se conserva para leer costs.json de v0.3, pero ya NO se usa.
    var dryerHoursPerJob: Double = 0
    // Conservado únicamente para descodificar ajustes guardados de versiones anteriores.
    // El tiempo de trabajo ahora pertenece a cada presupuesto.
    var activeLaborMinutes: Double = 0
    var laborEURHour: Double = 20
    var machineInvestmentEUR: Double = 169.69
    var machineRemainingHours: Double = 1000
    var maintenanceEURHour: Double = 0.05
    var consumablesEURJob: Double = 0.10
    var packagingEURJob: Double = 0
    var failureReservePercent: Double = 5
    var marginPercent: Double = 15
    func breakdown(seconds: Int?, filament: Double?, dryerDuringPrint: Bool = false, laborMinutes: Double = 0) -> CostBreakdown {
        let hours = Double(seconds ?? 0) / 3600
        let material = filament ?? 0
        let power = hours * printerWatts / 1000 * electricityEURkWh
        let dryer = (dryerDuringPrint ? hours : 0) * dryerWatts / 1000 * electricityEURkWh
        let labor = max(0, laborMinutes) / 60 * laborEURHour
        let depreciation = machineRemainingHours > 0 ? hours * machineInvestmentEUR / machineRemainingHours : 0
        let maintenance = hours * maintenanceEURHour
        let others = consumablesEURJob + packagingEURJob
        let base = material + power + dryer + labor + depreciation + maintenance + others
        return CostBreakdown(filament: material, electricity: power, dryer: dryer, labor: labor, depreciation: depreciation, maintenance: maintenance, others: others, risk: base * failureReservePercent / 100, marginPercent: marginPercent)
    }
}
struct CostBreakdown: Codable, Equatable {
    var filament: Double
    var electricity: Double
    var dryer: Double
    var labor: Double
    var depreciation: Double
    var maintenance: Double
    var others: Double
    var risk: Double
    var marginPercent: Double
    var total: Double { filament + electricity + dryer + labor + depreciation + maintenance + others + risk }
    var salePrice: Double? { marginPercent >= 100 ? nil : total / (1 - marginPercent / 100) }
}
@MainActor final class CostStore: ObservableObject {
    @Published var settings = CostSettings() { didSet { save() } }
    private var url: URL { FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("STLBudget/costs.json") }
    init() { if let data = try? Data(contentsOf: url), let value = try? JSONDecoder().decode(CostSettings.self, from: data) { settings = value } }
    func save() {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(settings) { try? data.write(to: url, options: .atomic) }
    }
}


// v0.4.0: proyectos locales independientes de Klipper.
struct ProjectLine: Identifiable, Codable {
    var id: UUID = UUID()
    var budgetID: UUID
    var color: String
    var quantity: Int
    var completed: Int = 0
}

struct OrderedPart: Identifiable, Codable {
    var id: UUID = UUID()
    var name: String
    var color: String
    var quantity: Int
    var completed: Int = 0
}

struct PlateMapping: Identifiable, Codable {
    var id: UUID = UUID()
    var objectName: String
    var partID: UUID? = nil
    var copies: Int = 1
}

struct ProjectPlate: Identifiable, Codable {
    var id: UUID = UUID()
    var budgetID: UUID
    var runs: Int = 1
    var mappings: [PlateMapping] = []
}


// Referencia de una pieza: un G-code con un único objeto/copia, analizado una vez.
struct PartReference: Identifiable, Codable {
    var id: UUID = UUID()
    var name: String
    var filename: String
    var grams: Double
    var durationSeconds: Int
    var material: String
    var suggestedSpoolID: Int?
}

// Una misma referencia puede encargarse en varios colores y cantidades.
struct PartOrder: Identifiable, Codable {
    var id: UUID = UUID()
    var referenceID: UUID
    var color: String
    var spoolID: Int?
    var quantity: Int
    var completed: Int = 0
}

struct PrintProject: Identifiable, Codable {
    var id: UUID = UUID()
    var name: String
    var customer: String
    var notes: String
    var status: String = "Pendiente"
    var createdAt: Date = Date()
    var lines: [ProjectLine] = [] // Compatibilidad con proyectos de la primera v0.4.0
    var parts: [OrderedPart]? = nil
    var plates: [ProjectPlate]? = nil
    var references: [PartReference]? = nil
    var orders: [PartOrder]? = nil
    var drying: Bool? = nil
    var activeMinutes: Double? = nil
    // Precio acordado opcional y copia de la estimación al emitir el presupuesto.
    var agreedPriceEUR: Double? = nil
    var issuedQuote: IssuedQuote? = nil
}

struct IssuedQuote: Codable {
    var issuedAt: Date
    var totalCost: Double
    var suggestedPrice: Double
    var finalPrice: Double
    var components: CostBreakdown
    var lines: [QuoteLine]
    var projectName: String
    var customer: String
    var conditions: String
    var validDays: Int
    var issuerName: String
    var issuerContact: String
}

struct QuoteLine: Codable {
    var piece: String
    var spool: String
    var quantity: Int
}

struct DocumentSettings: Codable {
    var issuerName = ""
    var issuerContact = ""
    var conditions = "Presupuesto orientativo sujeto a aceptación."
    var validityDays = 30
}

@MainActor final class DocumentStore: ObservableObject {
    @Published var settings = DocumentSettings() { didSet { save() } }
    private var url: URL { FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("STLBudget/documents.json") }
    init() {
        if let data = try? Data(contentsOf: url), let decoded = try? JSONDecoder().decode(DocumentSettings.self, from: data) { settings = decoded }
    }
    private func save() {
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let data = try? JSONEncoder().encode(settings) { try? data.write(to: url, options: .atomic) }
    }
}

@MainActor final class ProjectStore: ObservableObject {
    @Published private(set) var projects: [PrintProject] = []
    @Published var errorMessage: String?
    private var url: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("STLBudget/projects.json")
    }
    init() {
        if let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode([PrintProject].self, from: data) {
            projects = decoded
        }
    }
    private func save() {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(projects).write(to: url, options: .atomic)
        } catch { errorMessage = "No se pudieron guardar los proyectos: \(error.localizedDescription)" }
    }
    func create(name: String, customer: String, notes: String) -> UUID {
        var item = PrintProject(name: name.trimmingCharacters(in: .whitespacesAndNewlines), customer: customer, notes: notes)
        item.activeMinutes = 10
        projects.insert(item, at: 0); save(); return item.id
    }
    func remove(_ id: UUID) { projects.removeAll { $0.id == id }; save() }
    func setStatus(_ id: UUID, _ status: String) {
        guard let index = projects.firstIndex(where: { $0.id == id }) else { return }
        projects[index].status = status; save()
    }
    func addReference(_ projectID: UUID, job: PrintJob, filename: String) {
        guard let i = projects.firstIndex(where: { $0.id == projectID }),
              let grams = job.grams, let seconds = job.durationSeconds else { return }
        var refs = projects[i].references ?? []
        // Diferentes archivos pueden compartir nombre: nunca sobreescribir referencias anteriores.
        refs.append(PartReference(name: (job.objects?.first?.name ?? job.name), filename: filename,
                                  grams: grams, durationSeconds: seconds,
                                  material: job.material, suggestedSpoolID: job.spoolID))
        projects[i].references = refs; save()
    }
    func removeReference(_ projectID: UUID, referenceID: UUID) {
        guard let i = projects.firstIndex(where: { $0.id == projectID }) else { return }
        projects[i].references?.removeAll { $0.id == referenceID }
        projects[i].orders?.removeAll { $0.referenceID == referenceID }
        save()
    }
    func addOrder(_ projectID: UUID, referenceID: UUID, spoolID: Int?, quantity: Int) {
        guard let i = projects.firstIndex(where: { $0.id == projectID }),
              projects[i].references?.contains(where: { $0.id == referenceID }) == true else { return }
        guard let spoolID else { return }
        var orders = projects[i].orders ?? []
        // `color` se conserva en el modelo para abrir proyectos de versiones anteriores.
        // La variante nueva obtiene su color exclusivamente de la bobina seleccionada.
        orders.append(PartOrder(referenceID: referenceID, color: "",
                                spoolID: spoolID, quantity: max(1, quantity)))
        projects[i].orders = orders; save()
    }
    func removeOrder(_ projectID: UUID, orderID: UUID) {
        guard let i = projects.firstIndex(where: { $0.id == projectID }) else { return }
        projects[i].orders?.removeAll { $0.id == orderID }; save()
    }
    func setOrderQuantity(_ projectID: UUID, orderID: UUID, quantity: Int) {
        guard let i = projects.firstIndex(where: { $0.id == projectID }),
              let j = projects[i].orders?.firstIndex(where: { $0.id == orderID }) else { return }
        let newQuantity = min(999, max(1, quantity))
        projects[i].orders![j].quantity = newQuantity
        projects[i].orders![j].completed = min(projects[i].orders![j].completed, newQuantity)
        save()
    }
    func setOrderSpool(_ projectID: UUID, orderID: UUID, spoolID: Int) {
        guard let i = projects.firstIndex(where: { $0.id == projectID }),
              let j = projects[i].orders?.firstIndex(where: { $0.id == orderID }) else { return }
        projects[i].orders![j].spoolID = spoolID; save()
    }
    func setOrderCompleted(_ projectID: UUID, orderID: UUID, count: Int) {
        guard let i = projects.firstIndex(where: { $0.id == projectID }),
              let j = projects[i].orders?.firstIndex(where: { $0.id == orderID }) else { return }
        projects[i].orders![j].completed = min(max(0,count), projects[i].orders![j].quantity); save()
    }
    func setDrying(_ projectID: UUID, enabled: Bool) {
        guard let i = projects.firstIndex(where: { $0.id == projectID }) else { return }
        projects[i].drying = enabled; save()
    }
    func setActiveMinutes(_ projectID: UUID, minutes: Double) {
        guard let i = projects.firstIndex(where: { $0.id == projectID }) else { return }
        projects[i].activeMinutes = max(0, minutes); save()
    }
    func setAgreedPrice(_ projectID: UUID, value: Double?) {
        guard let i = projects.firstIndex(where: { $0.id == projectID }), projects[i].issuedQuote == nil else { return }
        projects[i].agreedPriceEUR = value.map { max(0, $0) }; save()
    }
    func issue(_ projectID: UUID, snapshot: IssuedQuote) {
        guard let i = projects.firstIndex(where: { $0.id == projectID }), projects[i].issuedQuote == nil else { return }
        projects[i].issuedQuote = snapshot; save()
    }
    func duplicate(_ projectID: UUID) -> UUID? {
        guard let source = projects.first(where: { $0.id == projectID }) else { return nil }
        var duplicate = source
        duplicate.id = UUID(); duplicate.name = source.name + " (copia)"
        duplicate.status = "Pendiente"; duplicate.createdAt = Date()
        duplicate.issuedQuote = nil; duplicate.agreedPriceEUR = nil
        duplicate.orders = source.orders?.map { var o = $0; o.id = UUID(); o.completed = 0; return o }
        projects.insert(duplicate, at: 0); save(); return duplicate.id
    }
    func addPart(_ projectID: UUID, name: String, color: String, quantity: Int) {
        guard let i = projects.firstIndex(where: { $0.id == projectID }) else { return }
        var parts = projects[i].parts ?? []
        parts.append(OrderedPart(name: name.trimmingCharacters(in: .whitespacesAndNewlines), color: color.trimmingCharacters(in: .whitespacesAndNewlines), quantity: max(1, quantity)))
        projects[i].parts = parts; save()
    }
    func removePart(_ projectID: UUID, partID: UUID) {
        guard let i = projects.firstIndex(where: { $0.id == projectID }) else { return }
        projects[i].parts?.removeAll { $0.id == partID }
        for j in (projects[i].plates ?? []).indices {
            for k in projects[i].plates![j].mappings.indices where projects[i].plates![j].mappings[k].partID == partID {
                projects[i].plates![j].mappings[k].partID = nil
            }
        }
        save()
    }
    func setPartCompleted(_ projectID: UUID, partID: UUID, count: Int) {
        guard let i = projects.firstIndex(where: { $0.id == projectID }),
              let j = projects[i].parts?.firstIndex(where: { $0.id == partID }) else { return }
        projects[i].parts![j].completed = min(max(0, count), projects[i].parts![j].quantity); save()
    }
    func addPlate(_ projectID: UUID, budgetID: UUID, objects: [GCodeObject]) {
        guard let i = projects.firstIndex(where: { $0.id == projectID }) else { return }
        var plates = projects[i].plates ?? []
        plates.append(ProjectPlate(budgetID: budgetID, mappings: objects.map { PlateMapping(objectName: $0.name, copies: $0.copies) }))
        projects[i].plates = plates; save()
    }
    func removePlate(_ projectID: UUID, plateID: UUID) {
        guard let i = projects.firstIndex(where: { $0.id == projectID }) else { return }
        projects[i].plates?.removeAll { $0.id == plateID }; save()
    }
    func setPlateRuns(_ projectID: UUID, plateID: UUID, runs: Int) {
        guard let i = projects.firstIndex(where: { $0.id == projectID }),
              let j = projects[i].plates?.firstIndex(where: { $0.id == plateID }) else { return }
        projects[i].plates![j].runs = min(999, max(1, runs)); save()
    }
    func mapObject(_ projectID: UUID, plateID: UUID, mappingID: UUID, partID: UUID?) {
        guard let i = projects.firstIndex(where: { $0.id == projectID }),
              let j = projects[i].plates?.firstIndex(where: { $0.id == plateID }),
              let k = projects[i].plates![j].mappings.firstIndex(where: { $0.id == mappingID }) else { return }
        projects[i].plates![j].mappings[k].partID = partID; save()
    }
    func addLine(_ id: UUID, budgetID: UUID, color: String, quantity: Int) {
        guard let index = projects.firstIndex(where: { $0.id == id }) else { return }
        projects[index].lines.append(ProjectLine(budgetID: budgetID, color: color, quantity: max(1, quantity)))
        save()
    }
    func removeLine(_ id: UUID, lineID: UUID) {
        guard let index = projects.firstIndex(where: { $0.id == id }) else { return }
        projects[index].lines.removeAll { $0.id == lineID }; save()
    }
    func setCompleted(_ id: UUID, lineID: UUID, count: Int) {
        guard let i = projects.firstIndex(where: { $0.id == id }),
              let j = projects[i].lines.firstIndex(where: { $0.id == lineID }) else { return }
        projects[i].lines[j].completed = min(max(count, 0), projects[i].lines[j].quantity)
        save()
    }
}
