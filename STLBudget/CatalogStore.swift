import Foundation
import Combine

@MainActor final class CatalogStore: ObservableObject {
    @Published var catalog: LocalCatalog = .init()
    @Published var message: String = ""
    @Published var isImporting = false
    private var fileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("STLBudget", isDirectory: true).appendingPathComponent("catalog.json")
    }
    init() { load() }
    func load() {
        guard let data = try? Data(contentsOf: fileURL), let loaded = try? JSONDecoder().decode(LocalCatalog.self, from: data) else { return }
        catalog = loaded
    }
    func save() {
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(catalog)
            try data.write(to: fileURL, options: .atomic)
        } catch { message = "No se pudo guardar el catálogo: \(error.localizedDescription)" }
    }
    func spool(_ id: Int?) -> Spool? {
        guard let id else { return nil }
        return catalog.spools.first(where: { $0.id == id })
    }
    func importSpools() async {
        guard !isImporting else { return }
        isImporting = true
        defer { isImporting = false }
        do {
            let text = catalog.serverURL.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            guard let base = URL(string: text), ["http", "https"].contains(base.scheme?.lowercased() ?? ""), base.host != nil else {
                throw NSError(domain: "STLBudget", code: 2, userInfo: [NSLocalizedDescriptionKey: "Introduce una URL HTTP(S) válida."])
            }
            var request = URLRequest(url: base.appendingPathComponent("api/v1/spool"))
            request.timeoutInterval = 15
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                throw NSError(domain: "STLBudget", code: 3, userInfo: [NSLocalizedDescriptionKey: "Spoolman no devolvió una respuesta correcta."])
            }
            guard let objects = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
                throw NSError(domain: "STLBudget", code: 4, userInfo: [NSLocalizedDescriptionKey: "La API no devolvió una lista de bobinas."])
            }
            let previous = Dictionary(uniqueKeysWithValues: catalog.spools.map { ($0.id, $0) })
            var imported: [Spool] = []
            for item in objects {
                guard let id = item["id"] as? Int else { continue }
                let filament = item["filament"] as? [String: Any] ?? [:]
                let vendor = filament["vendor"] as? [String: Any] ?? [:]
                let type = filament["material"] as? String ?? "Desconocido"
                let name = filament["name"] as? String ?? "Filamento #\(id)"
                let cost = number(item["price"]) ?? number(filament["price"])
                let weight = number(item["initial_weight"]) ?? number(filament["weight"])
                imported.append(Spool(id: id, material: type, name: name, vendor: vendor["name"] as? String ?? "", colorHex: filament["color_hex"] as? String ?? "", priceEUR: cost, initialWeightG: weight, remainingWeightG: number(item["remaining_weight"]), updatedAt: Date(), manualPrice: previous[id]?.manualPrice))
            }
            guard !imported.isEmpty || objects.isEmpty else { throw NSError(domain: "STLBudget", code: 5, userInfo: [NSLocalizedDescriptionKey: "Ninguna bobina tenía un ID válido."]) }
            catalog.spools = imported.sorted { $0.id < $1.id }
            catalog.lastImported = Date()
            save()
            message = "Importación completada: \(imported.count) bobinas. Se ha guardado una copia local."
        } catch { message = "Error de importación: \(error.localizedDescription). El catálogo local anterior sigue disponible." }
    }
    private func number(_ obj: Any?) -> Double? {
        if let n = obj as? NSNumber { return n.doubleValue }
        if let s = obj as? String { return Double(s) }
        return nil
    }
}
