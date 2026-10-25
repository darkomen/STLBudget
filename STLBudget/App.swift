import SwiftUI
import UniformTypeIdentifiers
import Charts
import CoreText
import AppKit

@main struct STLBudgetApp: App {
    @StateObject private var store = CatalogStore()
    @StateObject private var budgets = BudgetStore()
    @StateObject private var costs = CostStore()
    @StateObject private var projects = ProjectStore()
    @StateObject private var documents = DocumentStore()
    var body: some Scene {
        WindowGroup {
            MainView().environmentObject(store).environmentObject(budgets).environmentObject(costs).environmentObject(projects).environmentObject(documents).frame(minWidth: 850, minHeight: 570)
        }
        .commands { CommandGroup(replacing: .newItem) { } }
        Settings { SettingsView().environmentObject(store).environmentObject(costs).environmentObject(documents).frame(width: 760, height: 520) }
    }
}

struct MainView: View {
    @EnvironmentObject private var store: CatalogStore
    @State private var job: PrintJob?
    @State private var errorMessage: String?
    @State private var dropTarget = false
    @State private var showSettings = false
    @EnvironmentObject private var budgets: BudgetStore
    @EnvironmentObject private var documents: DocumentStore
    @EnvironmentObject private var projects: ProjectStore
    @EnvironmentObject private var costs: CostStore
    @State private var pendingAction: (() -> Void)?
    @State private var confirmLeaving = false
    @State private var savedEditorFingerprint = ""
    @State private var savedCostSnapshot: CostBreakdown?
    @State private var dryerDuringPrint = false
    @State private var laborMinutes: Double = 0
    @State private var page = "Proyectos"
    @State private var selectedProjectID: UUID?
    @State private var projectName = ""
    @State private var projectCustomer = ""
    @State private var projectNotes = ""
    @State private var showNewProject = false
    @State private var selectedExistingBudget: UUID?
    @State private var newLineColor = ""
    @State private var newLineQuantity = 1
    @State private var partName = ""
    @State private var partColor = ""
    @State private var partQuantity = 1
    @State private var selectedPlateBudget: UUID?
    @State private var pendingProjectBudgetID: UUID?
    @State private var selectedReferenceID: UUID?
    @State private var referenceSpoolID: Int? = nil
    @State private var referenceQuantity = 1
    @State private var projectSection = 0
    @State private var recipient = ""
    @State private var budgetTitle = ""
    @State private var budgetStatus = "Borrador"
    @State private var comments = ""
    @State private var loadedBudgetID: UUID?
    @State private var originalURL: URL?
    @State private var search = ""
    @State private var selectedBudgetID: UUID?
    private var spool: Spool? { store.spool(job?.spoolID) }
    private var fingerprint: String { "\(job?.name ?? "")|\(recipient)|\(budgetTitle)|\(budgetStatus)|\(comments)|\(dryerDuringPrint)|\(laborMinutes)|\(loadedBudgetID?.uuidString ?? "")" }
    private var hasUnsavedChanges: Bool { job != nil && fingerprint != savedEditorFingerprint }
    private var calculation: CostBreakdown? {
        guard let job else { return nil }
        if var snapshot = savedCostSnapshot {
            // Conservar el resto de partidas históricas al editar el tiempo activo.
            if let id = loadedBudgetID,
               let original = budgets.budgets.first(where: { $0.id == id }),
               laborMinutes != (original.laborMinutes ?? 0) {
                let previousMinutes = original.laborMinutes ?? 0
                let hourlyRate = previousMinutes > 0
                    ? snapshot.labor * 60 / previousMinutes
                    : costs.settings.laborEURHour
                let oldBase = snapshot.total - snapshot.risk
                let reserveRate = oldBase > 0
                    ? snapshot.risk / oldBase
                    : costs.settings.failureReservePercent / 100
                snapshot.labor = max(0, laborMinutes) / 60 * hourlyRate
                let newBase = snapshot.filament + snapshot.electricity + snapshot.dryer
                    + snapshot.labor + snapshot.depreciation + snapshot.maintenance + snapshot.others
                snapshot.risk = newBase * reserveRate
            }
            return snapshot
        }
        let filament = (spool?.pricePerGram).flatMap { rate in job.grams.map { $0 * rate } }
        return costs.settings.breakdown(seconds: job.durationSeconds, filament: filament, dryerDuringPrint: dryerDuringPrint, laborMinutes: laborMinutes)
    }
    private func requestNavigation(_ action: @escaping () -> Void) {
        if page != "Histórico" && hasUnsavedChanges {
            pendingAction = action; confirmLeaving = true
        } else { action() }
    }
    var body: some View {
        NavigationSplitView {
            VStack(alignment: .leading, spacing: 15) {
                Label("STLBudget", systemImage: "cube.transparent.fill").font(.title2.bold())
                Divider()
                Button { requestNavigation { page = "Proyectos" } } label: { Label("Proyectos", systemImage: "square.grid.2x2") }.buttonStyle(.plain).font(.headline)
                Button { requestNavigation { resetEditor() } } label: { Label("Nuevo presupuesto", systemImage: "plus.square.on.square") }.buttonStyle(.plain).font(.headline)
                Button { requestNavigation { page = "Histórico" } } label: { Label("Histórico", systemImage: "clock.arrow.circlepath") }.buttonStyle(.plain).font(.headline)
                Spacer()
                Button { showSettings = true } label: { Label("Configuración", systemImage: "gearshape") }
                Text("v0.4.2 · Proyectos y documentos").font(.caption).foregroundStyle(.secondary)
            }.padding(20).frame(minWidth: 210, maxWidth: 250, alignment: .leading)
        } detail: {
            Group {
                if page == "Proyectos" { projectsView }
                else if page == "Histórico" { historyView }
                else { editorView }
            }
        }
        .confirmationDialog("Hay cambios sin guardar", isPresented: $confirmLeaving, titleVisibility: .visible) {
            Button("Guardar y continuar") { saveBudget(); pendingAction?(); pendingAction = nil }
            Button("Salir sin guardar", role: .destructive) { pendingAction?(); pendingAction = nil }
            Button("Cancelar", role: .cancel) { pendingAction = nil }
        } message: { Text("¿Quieres guardar el presupuesto antes de salir?") }
        .sheet(isPresented: $showSettings) { SettingsView().environmentObject(store).environmentObject(costs).frame(width: 800, height: 590) }
    }

    private var projectsView: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Proyectos").font(.title2.bold())
                    Spacer()
                    Button { projectName = ""; projectCustomer = ""; projectNotes = ""; showNewProject = true } label: {
                        Image(systemName: "plus")
                    }.help("Nuevo proyecto")
                }
                List(selection: $selectedProjectID) {
                    ForEach(projects.projects) { project in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(project.name).font(.headline)
                            Text(project.customer.isEmpty ? "Sin cliente" : project.customer).font(.caption).foregroundStyle(.secondary)
                            HStack {
                                Text(project.status).font(.caption2)
                                Spacer()
                                Text("\((project.orders ?? []).reduce(0) { $0 + $1.completed }) / \((project.orders ?? []).reduce(0) { $0 + $1.quantity })")
                                    .font(.caption2.monospacedDigit())
                            }.foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 5)
                        .tag(project.id)
                        .contextMenu {
                            Button("Duplicar proyecto") {
                                if let newID = projects.duplicate(project.id) { selectedProjectID = newID; projectSection = 0 }
                            }
                            Button("Eliminar proyecto", role: .destructive) { projects.remove(project.id); if selectedProjectID == project.id { selectedProjectID = nil } }
                        }
                    }
                }.listStyle(.sidebar)
            }
            .padding(18).frame(minWidth: 255, idealWidth: 285, maxWidth: 320)
            Divider()
            if let id = selectedProjectID, let project = projects.projects.first(where: { $0.id == id }) {
                projectDetail(project)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "shippingbox").font(.system(size: 48)).foregroundStyle(.secondary)
                    Text("Organiza tus pedidos").font(.title2.bold())
                    Text("Crea un pedido, define sus piezas y añade todas las bandejas G-code que necesites.")
                        .foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 370)
                    Button("Nuevo proyecto") { projectName = ""; projectCustomer = ""; projectNotes = ""; showNewProject = true }
                        .buttonStyle(.borderedProminent)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .sheet(isPresented: $showNewProject) {
            VStack(alignment: .leading, spacing: 18) {
                Text("Nuevo proyecto").font(.title2.bold())
                TextField("Nombre del proyecto", text: $projectName)
                TextField("Cliente o destinatario", text: $projectCustomer)
                TextField("Notas (opcional)", text: $projectNotes)
                HStack {
                    Spacer()
                    Button("Cancelar") { showNewProject = false }
                    Button("Crear proyecto") {
                        let id = projects.create(name: projectName, customer: projectCustomer, notes: projectNotes)
                        selectedProjectID = id
                        showNewProject = false
                    }.buttonStyle(.borderedProminent).disabled(projectName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }.padding(24).frame(width: 430)
        }
    }

    // Nuevo flujo: primero importar G-code individual, después definir colores y cantidades.
    private func projectDetail(_ project: PrintProject) -> some View {
        let refs = project.references ?? []
        let orders = project.orders ?? []
        let completed = orders.reduce(0) { $0 + $1.completed }
        let quantity = orders.reduce(0) { $0 + $1.quantity }
        let seconds = orders.reduce(0) { sum, line in
            sum + (refs.first(where: { $0.id == line.referenceID })?.durationSeconds ?? 0) * line.quantity
        }
        let grams = orders.reduce(0.0) { sum, line in
            sum + (refs.first(where: { $0.id == line.referenceID })?.grams ?? 0) * Double(line.quantity)
        }
        let missingPrices = orders.filter { store.spool($0.spoolID)?.pricePerGram == nil }
        let filamentEUR = orders.reduce(0.0) { sum, line in
            let unitGrams = refs.first(where: { $0.id == line.referenceID })?.grams ?? 0
            let perGram = store.spool(line.spoolID)?.pricePerGram ?? 0
            return sum + unitGrams * Double(line.quantity) * perGram
        }
        let liveEstimate = costs.settings.breakdown(seconds: seconds, filament: filamentEUR,
              dryerDuringPrint: project.drying ?? false, laborMinutes: project.activeMinutes ?? 10)
        let estimate = project.issuedQuote?.components ?? liveEstimate
        return ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(project.name).font(.largeTitle.bold())
                        Text(project.customer.isEmpty ? "Sin cliente" : project.customer).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Picker("Estado", selection: Binding(get: { project.status }, set: { projects.setStatus(project.id, $0) })) {
                        ForEach(["Pendiente", "En producción", "Terminado", "Entregado"], id: \.self) { Text($0) }
                    }.frame(width: 170)
                }
                Picker("Sección", selection: $projectSection) {
                    Label("Piezas", systemImage: "shippingbox").tag(0)
                    Label("Detalle de precio", systemImage: "chart.pie").tag(1)
                    Label("Presupuesto", systemImage: "doc.text").tag(2)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                if projectSection == 0 {
                if project.issuedQuote != nil {
                    Label("Presupuesto emitido. Las modificaciones de fabricación no alteran el PDF emitido; duplica el proyecto para preparar una oferta nueva.", systemImage: "lock.shield")
                        .font(.caption).foregroundStyle(.secondary)
                }
                GroupBox {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack { Text("Resumen del pedido").font(.headline); Spacer(); Text("\(completed) / \(quantity) piezas").monospacedDigit() }
                        ProgressView(value: Double(completed), total: Double(max(1,quantity)))
                        HStack { Text("Filamento"); Spacer(); Text(String(format: "%.2f g", grams)) }
                        HStack { Text("Tiempo estimado"); Spacer(); Text(formattedDuration(seconds)) }
                        HStack { Text("Coste estimado"); Spacer(); Text(String(format: "%.2f €", estimate.total)).bold() }
                        HStack { Text("Precio final"); Spacer(); Text(String(format: "%.2f €", project.issuedQuote?.finalPrice ?? project.agreedPriceEUR ?? estimate.salePrice ?? 0)).bold() }
                        Text("Tiempo calculado sumando impresiones individuales. Una bandeja conjunta puede tardar menos; se presupuesta de forma conservadora.")
                            .font(.caption).foregroundStyle(.secondary)
                        if !missingPrices.isEmpty {
                            Label("Falta precio de bobina en \(missingPrices.count) variante(s). El coste del filamento está incompleto.", systemImage: "exclamationmark.triangle")
                                .font(.caption).foregroundStyle(.orange)
                        }
                    }.padding(6)
                }
                HStack {
                    Text("1 · G-codes de referencia").font(.title2.bold())
                    Spacer()
                    Button { importReferences(project.id) } label: { Label("Importar G-codes…", systemImage: "plus") }
                        .buttonStyle(.borderedProminent)
                }
                Text("Importa un G-code por pieza diferente, generado con tu perfil real de OrcaSlicer. Puedes elegir varios archivos a la vez.")
                    .font(.caption).foregroundStyle(.secondary)
                if refs.isEmpty {
                    ContentUnavailableView("Aún no hay piezas", systemImage: "square.stack.3d.up", description: Text("Empieza importando los G-codes individuales. STLBudget extraerá automáticamente gramos y tiempo."))
                }
                ForEach(refs) { reference in
                    HStack(spacing: 12) {
                        Image(systemName: "cube.transparent.fill").foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(reference.name).font(.headline)
                            Text(reference.filename).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer()
                        Text(String(format: "%.2f g", reference.grams)).monospacedDigit().frame(width: 90, alignment: .trailing)
                        Text(formattedDuration(reference.durationSeconds)).monospacedDigit().frame(width: 120, alignment: .trailing)
                        Button(role: .destructive) { projects.removeReference(project.id, referenceID: reference.id) } label: { Image(systemName: "trash") }
                            .help("Eliminar referencia y sus variantes")
                    }.padding(12).background(.quaternary.opacity(0.2), in: RoundedRectangle(cornerRadius: 10))
                }
                Divider()
                HStack { Text("2 · Cantidades y filamentos").font(.title2.bold()); Spacer(); Text("\(quantity) piezas").foregroundStyle(.secondary) }
                Text("Selecciona una pieza importada, la bobina/color y cuántas unidades necesitas. Repite la selección para otros colores.")
                    .font(.caption).foregroundStyle(.secondary)
                ForEach(orders) { line in
                    let reference = refs.first(where: { $0.id == line.referenceID })
                    HStack(spacing: 12) {
                        Image(systemName: "shippingbox").foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(reference?.name ?? "Referencia no disponible").font(.headline)
                            Picker("Bobina", selection: Binding<Int?>(
                                get: { line.spoolID },
                                set: { if let spoolID = $0 { projects.setOrderSpool(project.id, orderID: line.id, spoolID: spoolID) } })) {
                                ForEach(store.catalog.spools) { spool in
                                    Text("#\(spool.id) · \(spool.name)").tag(Optional(spool.id))
                                }
                            }.labelsHidden().font(.caption).frame(maxWidth: 240, alignment: .leading)
                                .disabled(project.issuedQuote != nil)
                        }
                        Spacer()
                        HStack(spacing: 4) {
                            Button { projects.setOrderQuantity(project.id, orderID: line.id, quantity: line.quantity - 1) } label: {
                                Image(systemName: "minus")
                            }.disabled(line.quantity <= 1).help("Reducir unidades encargadas")
                            Text("×\(line.quantity)").monospacedDigit().frame(minWidth: 28)
                            Button { projects.setOrderQuantity(project.id, orderID: line.id, quantity: line.quantity + 1) } label: {
                                Image(systemName: "plus")
                            }.disabled(line.quantity >= 999).help("Aumentar unidades encargadas")
                        }.buttonStyle(.borderless)
                        Divider().frame(height: 19)
                        Button { projects.setOrderCompleted(project.id, orderID: line.id, count: line.completed - 1) } label: { Image(systemName: "minus.circle") }.disabled(line.completed == 0)
                        Text("\(line.completed)/\(line.quantity)").monospacedDigit().frame(width: 55)
                        Button { projects.setOrderCompleted(project.id, orderID: line.id, count: line.completed + 1) } label: { Image(systemName: "plus.circle") }.disabled(line.completed >= line.quantity)
                        Button(role: .destructive) { projects.removeOrder(project.id, orderID: line.id) } label: { Image(systemName: "trash") }
                    }.padding(12).background(.quaternary.opacity(0.18), in: RoundedRectangle(cornerRadius: 10))
                }
                if !refs.isEmpty {
                    GroupBox("Añadir variante") {
                        VStack(alignment: .leading, spacing: 10) {
                            Picker("Pieza", selection: $selectedReferenceID) {
                                Text("Seleccionar pieza…").tag(nil as UUID?)
                                ForEach(refs) { ref in Text(ref.name).tag(Optional(ref.id)) }
                            }
                            HStack {
                                Picker("Bobina", selection: $referenceSpoolID) {
                                    Text("Selecciona una bobina…").tag(nil as Int?)
                                    ForEach(store.catalog.spools) { spool in
                                        Text("#\(spool.id) · \(spool.name)").tag(Optional(spool.id))
                                    }
                                }.frame(maxWidth: 260)
                                Stepper("×\(referenceQuantity)", value: $referenceQuantity, in: 1...999).frame(width: 110)
                                Button("Añadir") {
                                    if let id = selectedReferenceID {
                                        projects.addOrder(project.id, referenceID: id,
                                                           spoolID: referenceSpoolID, quantity: referenceQuantity)
                                        referenceQuantity = 1
                                    }
                                }.disabled(selectedReferenceID == nil || referenceSpoolID == nil)
                            }
                        }.padding(6)
                    }
                }
                Divider()
                Text("3 · Costes del pedido").font(.title2.bold())
                Toggle("Secador durante toda la impresión", isOn: Binding(get: { project.drying ?? false }, set: { projects.setDrying(project.id, enabled: $0) }))
                HStack {
                    Text("Trabajo manual (minutos)")
                    TextField("0", value: Binding(get: { project.activeMinutes ?? 10 }, set: { projects.setActiveMinutes(project.id, minutes: $0) }), format: .number)
                        .textFieldStyle(.roundedBorder).frame(width: 90)
                    Spacer()
                }
                Text("Los gastos fijos de consumibles y embalaje se suman una vez por pedido. Las horas se estiman por pieza individual y se multiplican por las cantidades.")
                    .font(.caption).foregroundStyle(.secondary)
                if !project.lines.isEmpty || !(project.parts ?? []).isEmpty || !(project.plates ?? []).isEmpty {
                    GroupBox("Datos de versiones anteriores") {
                        Text("Se han conservado las líneas y bandejas antiguas para no perder información. No se incluyen en el nuevo cálculo; recrea sus variantes a partir de los G-codes individuales.")
                            .font(.caption).foregroundStyle(.secondary).padding(6)
                    }
                }
                if !project.notes.isEmpty { GroupBox("Notas") { Text(project.notes).frame(maxWidth: .infinity, alignment: .leading).padding(6) } }
                } else if projectSection == 1 {
                    projectPricing(estimate: estimate, seconds: seconds, grams: grams, missingPrices: missingPrices.count)
                    projectCommercial(project: project, estimate: estimate)
                } else {
                    projectDocuments(project: project, references: refs, orders: orders,
                                     estimate: estimate, seconds: seconds, grams: grams, missingPrices: missingPrices.count)
                }
            }.padding(24).frame(maxWidth: 1000, alignment: .leading)
        }
        .alert("Importación de G-codes", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("Aceptar", role: .cancel) { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
    }

    private struct CostSlice: Identifiable {
        let title: String
        let amount: Double
        let color: Color
        var id: String { title }
    }

    private func slices(_ value: CostBreakdown) -> [CostSlice] {
        [
            CostSlice(title: "Filamento", amount: value.filament, color: .orange),
            CostSlice(title: "Electricidad impresora", amount: value.electricity, color: .blue),
            CostSlice(title: "Electricidad secador", amount: value.dryer, color: .cyan),
            CostSlice(title: "Amortización", amount: value.depreciation, color: .purple),
            CostSlice(title: "Mantenimiento", amount: value.maintenance, color: .indigo),
            CostSlice(title: "Mano de obra", amount: value.labor, color: .green),
            CostSlice(title: "Consumibles y embalaje", amount: value.others, color: .brown),
            CostSlice(title: "Reserva por fallos", amount: value.risk, color: .gray)
        ]
    }

    private func projectPricing(estimate: CostBreakdown, seconds: Int, grams: Double, missingPrices: Int) -> some View {
        let entries = slices(estimate)
        return VStack(alignment: .leading, spacing: 20) {
            Text("Detalle de precio").font(.title2.bold())
            HStack(spacing: 12) {
                GroupBox("Coste estimado") {
                    Text(estimate.total, format: .currency(code: "EUR"))
                        .font(.system(size: 30, weight: .semibold, design: .rounded))
                        .monospacedDigit().frame(maxWidth: .infinity, alignment: .leading).padding(8)
                }
                GroupBox("Precio sugerido sin impuestos") {
                    Text(estimate.salePrice ?? 0, format: .currency(code: "EUR"))
                        .font(.system(size: 30, weight: .semibold, design: .rounded))
                        .monospacedDigit().frame(maxWidth: .infinity, alignment: .leading).padding(8)
                }
            }
            if missingPrices > 0 {
                Label("Hay \(missingPrices) variante(s) sin precio de bobina; el importe del material está incompleto.", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }
            GroupBox("Distribución de costes") {
                HStack(alignment: .center, spacing: 28) {
                    Chart(entries.filter { $0.amount > 0.0000001 }) { item in
                        SectorMark(angle: .value("Importe", item.amount), innerRadius: .ratio(0.60), angularInset: 1.5)
                            .foregroundStyle(item.color)
                            .cornerRadius(3)
                    }
                    .frame(width: 235, height: 235)
                    .chartLegend(.hidden)
                    VStack(alignment: .leading, spacing: 9) {
                        ForEach(entries) { item in
                            HStack(spacing: 8) {
                                Circle().fill(item.color).frame(width: 9, height: 9)
                                Text(item.title)
                                Spacer(minLength: 12)
                                Text(String(format: "%.4f €", item.amount)).monospacedDigit()
                                Text(estimate.total > 0 ? String(format: "%.1f %%", item.amount / estimate.total * 100) : "—")
                                    .foregroundStyle(.secondary).frame(width: 66, alignment: .trailing)
                            }.font(.callout)
                        }
                    }
                }.padding(12).frame(maxWidth: .infinity)
            }
            GroupBox("Datos del cálculo") {
                VStack(spacing: 10) {
                    LabeledContent("Unidades de filamento", value: String(format: "%.2f g", grams))
                    LabeledContent("Tiempo estimado", value: formattedDuration(seconds))
                    LabeledContent("Potencia impresora", value: String(format: "%.1f W", costs.settings.printerWatts))
                    LabeledContent("Potencia secador", value: String(format: "%.1f W", costs.settings.dryerWatts))
                    LabeledContent("Tarifa eléctrica", value: String(format: "%.3f €/kWh", costs.settings.electricityEURkWh))
                    LabeledContent("Margen bruto", value: String(format: "%.1f %%", estimate.marginPercent))
                }.padding(10)
            }
            Text("Cálculos estimados con los G-codes individuales. Los precios pueden variar si se modifican las tarifas o las bobinas.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func projectCommercial(project: PrintProject, estimate: CostBreakdown) -> some View {
        let suggested = estimate.salePrice ?? 0
        let finalPrice = project.issuedQuote?.finalPrice ?? project.agreedPriceEUR ?? suggested
        let cost = project.issuedQuote?.totalCost ?? estimate.total
        return GroupBox("Rentabilidad del proyecto") {
            VStack(alignment: .leading, spacing: 10) {
                LabeledContent("Precio sugerido", value: String(format: "%.2f €", suggested))
                HStack {
                    Text("Precio final acordado (€)")
                    Spacer()
                    TextField("Automático", value: Binding(
                        get: { project.agreedPriceEUR ?? suggested },
                        set: { projects.setAgreedPrice(project.id, value: $0) }), format: .number.precision(.fractionLength(2)))
                        .textFieldStyle(.roundedBorder).frame(width: 120)
                        .disabled(project.issuedQuote != nil)
                }
                LabeledContent("Beneficio previsto", value: String(format: "%.2f €", finalPrice - cost))
                if project.issuedQuote != nil {
                    Label("Presupuesto emitido: importes y líneas congelados.", systemImage: "lock.fill")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Text("El precio final puede ajustarse antes de emitir el presupuesto.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }.padding(8)
        }
    }

    private func projectDocuments(project: PrintProject, references: [PartReference], orders: [PartOrder],
                                  estimate: CostBreakdown, seconds: Int, grams: Double, missingPrices: Int) -> some View {
        let quantity = project.issuedQuote?.lines.reduce(0) { $0 + $1.quantity } ?? orders.reduce(0) { $0 + $1.quantity }
        return VStack(alignment: .leading, spacing: 18) {
            Text("Presupuesto").font(.title2.bold())
            GroupBox("Documento para el cliente") {
                VStack(alignment: .leading, spacing: 12) {
                    LabeledContent("Proyecto", value: project.name)
                    LabeledContent("Destinatario", value: project.customer.isEmpty ? "Sin especificar" : project.customer)
                    LabeledContent("Piezas", value: "\(quantity)")
                    LabeledContent("Precio acordado sin impuestos", value: String(format: "%.2f €", project.issuedQuote?.finalPrice ?? project.agreedPriceEUR ?? estimate.salePrice ?? 0))
                    Text("Incluye las piezas, bobinas y cantidades, sin revelar costes internos, márgenes ni amortización.")
                        .font(.caption).foregroundStyle(.secondary)
                    HStack {
                        Spacer()
                        Button { exportProjectPDF(project: project, references: references, orders: orders,
                                                  estimate: estimate, seconds: seconds, grams: grams,
                                                  internalReport: false) } label: {
                            Label("Exportar presupuesto PDF…", systemImage: "square.and.arrow.up")
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(orders.isEmpty || missingPrices > 0 || estimate.salePrice == nil)
                    }
                }.padding(10)
            }
            GroupBox("Informe interno") {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Incluye el detalle de filamento, electricidad, secador, amortización, mantenimiento, mano de obra y reserva por fallos.")
                        .foregroundStyle(.secondary)
                    HStack {
                        Spacer()
                        Button { exportProjectPDF(project: project, references: references, orders: orders,
                                                  estimate: estimate, seconds: seconds, grams: grams,
                                                  internalReport: true) } label: {
                            Label("Exportar informe interno PDF…", systemImage: "chart.pie")
                        }.disabled(orders.isEmpty)
                    }
                }.padding(10)
            }
            if missingPrices > 0 {
                Label("Completa los precios de las bobinas antes de emitir el presupuesto para el cliente.", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
            }
            if let issued = project.issuedQuote {
                Label("Emitido el \(issued.issuedAt.formatted(date: .abbreviated, time: .shortened)). Las líneas y los importes del PDF quedan congelados.", systemImage: "lock.shield")
                    .foregroundStyle(.secondary)
            } else {
                Button { issueQuote(project: project, references: references, orders: orders, estimate: estimate) } label: {
                    Label("Emitir y congelar presupuesto", systemImage: "lock.doc")
                }.disabled(orders.isEmpty || missingPrices > 0 || estimate.salePrice == nil)
                Text("Al emitir, se guarda una copia fija de cantidades, precio y desglose. Puedes duplicar el proyecto si necesitas preparar otra oferta.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Text("Los PDF exportados antes de emitir reflejan la estimación actual.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func issueQuote(project: PrintProject, references: [PartReference], orders: [PartOrder], estimate: CostBreakdown) {
        guard let suggested = estimate.salePrice else { return }
        let lines = orders.map { line -> QuoteLine in
            QuoteLine(piece: references.first(where: { $0.id == line.referenceID })?.name ?? "Pieza",
                      spool: store.spool(line.spoolID)?.name ?? "Sin bobina", quantity: line.quantity)
        }
        let settings = documents.settings
        projects.issue(project.id, snapshot: IssuedQuote(
            issuedAt: Date(), totalCost: estimate.total, suggestedPrice: suggested,
            finalPrice: project.agreedPriceEUR ?? suggested, components: estimate, lines: lines,
            projectName: project.name, customer: project.customer,
            conditions: settings.conditions, validDays: settings.validityDays,
            issuerName: settings.issuerName, issuerContact: settings.issuerContact))
    }

    private func exportProjectPDF(project: PrintProject, references: [PartReference], orders: [PartOrder],
                                  estimate: CostBreakdown, seconds: Int, grams: Double, internalReport: Bool) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = "\(project.name.replacingOccurrences(of: "/", with: "-"))_\(internalReport ? "costes" : "presupuesto").pdf"
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try ProjectPDFWriter.write(to: url, project: project, references: references, orders: orders,
                                       spools: store.catalog.spools, estimate: estimate,
                                       seconds: seconds, grams: grams, internalReport: internalReport,
                                       documents: documents.settings)
        } catch { errorMessage = "No se pudo exportar el PDF: \(error.localizedDescription)" }
    }

    private func importReferences(_ projectID: UUID) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "gcode") ?? .plainText]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.message = "Selecciona G-codes individuales: una sola pieza por archivo"
        guard panel.runModal() == .OK else { return }
        var failures: [String] = []
        for url in panel.urls {
            do {
                let job = try GCodeParser.parse(url)
                guard let grams = job.grams, grams > 0,
                      let seconds = job.durationSeconds, seconds > 0 else {
                    failures.append("\(url.lastPathComponent): faltan gramos o tiempo en el G-code")
                    continue
                }
                let objects = job.objects ?? []
                guard objects.count <= 1 && (objects.first?.copies ?? 1) == 1 else {
                    failures.append("\(url.lastPathComponent): contiene varias piezas. Expórtalas individualmente desde OrcaSlicer")
                    continue
                }
                projects.addReference(projectID, job: job, filename: url.lastPathComponent)
            } catch { failures.append("\(url.lastPathComponent): \(error.localizedDescription)") }
        }
        if !failures.isEmpty { errorMessage = failures.joined(separator: "\n") }
    }

    private func importForProject(_ id: UUID) {
        pendingProjectBudgetID = id
        chooseFile()
        // Si el usuario cancela, no debe quedar una asociación pendiente.
        if page != "Nuevo presupuesto" { pendingProjectBudgetID = nil }
    }

    private var editorView: some View {
        ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(loadedBudgetID == nil ? "Nuevo presupuesto" : "Editar presupuesto").font(.largeTitle.bold())
                            Text(loadedBudgetID == nil ? "Importa un G-code de OrcaSlicer para obtener sus datos." : (budgets.budgets.first(where: { $0.id == loadedBudgetID })?.reference ?? "Presupuesto guardado")).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button { requestNavigation { chooseFile() } } label: { Label("Abrir G-code…", systemImage: "folder") }.buttonStyle(.borderedProminent)
                    }
                    if let job {
                        GroupBox("Datos del presupuesto") {
                            VStack(alignment: .leading, spacing: 10) {
                                TextField("Nombre de la pieza", text: $budgetTitle)
                                TextField("Dirigido a (persona o empresa)", text: $recipient)
                                HStack { Text("Estado"); Picker("Estado", selection: $budgetStatus) { ForEach(["Borrador", "Enviado", "Aceptado", "Rechazado", "Completado"], id: \.self) { Text($0) } }.labelsHidden().frame(width: 160); Spacer() }
                                HStack {
                                    Text("Tiempo de trabajo personal (min)")
                                    TextField("0", value: $laborMinutes, format: .number.precision(.fractionLength(0...1)))
                                        .frame(width: 100).textFieldStyle(.roundedBorder)
                                    Text("min").foregroundStyle(.secondary)
                                    Spacer()
                                }
                                Text("Introduce 0 si no has dedicado tiempo de diseño, preparación ni acabado. Solo se cobra tiempo activo, no las horas de impresión.")
                                    .font(.caption).foregroundStyle(.secondary)
                                Toggle("Secado durante la impresión", isOn: $dryerDuringPrint)
                                    .disabled(loadedBudgetID != nil && savedCostSnapshot != nil)
                                    .help("El secador funciona durante todo el tiempo estimado por el G-code. Su consumo se suma al de la impresora.")
                                if loadedBudgetID != nil && savedCostSnapshot != nil { Text("Se conserva el resto de costes históricos. Al editar tus minutos se actualizan la mano de obra y la reserva por fallos; si el tiempo anterior era cero, se usa la tarifa actual de Configuración.").font(.caption).foregroundStyle(.secondary) }
                                TextField("Notas del presupuesto (opcional)", text: $comments)
                                HStack {
                                    Spacer()
                                    Button(loadedBudgetID == nil ? "Guardar presupuesto" : "Guardar cambios") { saveBudget() }.buttonStyle(.borderedProminent)
                                }
                            }.padding(8)
                        }
                        HStack(alignment: .top, spacing: 22) {
                            Group {
                                if let data = job.thumbnail, let image = NSImage(data: data) {
                                    Image(nsImage: image).resizable().scaledToFit()
                                } else { Image(systemName: "cube").resizable().scaledToFit().padding(65).foregroundStyle(.secondary) }
                            }.frame(width: 220, height: 220).background(.quaternary.opacity(0.4)).clipShape(RoundedRectangle(cornerRadius: 14))
                            VStack(alignment: .leading, spacing: 10) {
                                Text(job.name).font(.title2.bold()).lineLimit(2)
                                Text(job.slicer).font(.caption).foregroundStyle(.secondary)
                                LabeledContent("Material", value: job.material)
                                LabeledContent("Perfil", value: job.profile)
                                LabeledContent("ID Spoolman", value: job.spoolID.map(String.init) ?? "No disponible")
                                LabeledContent("Tiempo estimado", value: formattedDuration(job.durationSeconds))
                                LabeledContent("Consumo", value: job.grams.map { String(format: "%.2f g", $0) } ?? "No disponible")
                                LabeledContent("Temperatura", value: job.nozzleC.map { "\(Int($0)) °C" } ?? "—")
                                LabeledContent("Capas", value: job.layers.map(String.init) ?? "—")
                            }
                        }
                        GroupBox("Estimación económica") {
                            VStack(alignment: .leading, spacing: 9) {
                                if let id = loadedBudgetID, let saved = budgets.budgets.first(where: { $0.id == id }) {
                                    LabeledContent("Bobina guardada", value: saved.spoolDescription)
                                    Text("Los costes de este presupuesto son una instantánea histórica.").font(.caption).foregroundStyle(.secondary)
                                } else if let spool {
                                    LabeledContent("Bobina", value: "#\(spool.id) · \(spool.vendor) \(spool.name)")
                                } else { Text("Bobina no encontrada en el catálogo local; coste de filamento no incluido.").foregroundStyle(.orange) }
                                if let calculation {
                                    costLine("Filamento", calculation.filament)
                                    costLine("Electricidad impresora", calculation.electricity)
                                    costLine("Secador", calculation.dryer)
                                    costLine("Mano de obra activa", calculation.labor)
                                    costLine("Amortización", calculation.depreciation)
                                    costLine("Mantenimiento", calculation.maintenance)
                                    costLine("Consumibles y embalaje", calculation.others)
                                    costLine("Reserva por fallos", calculation.risk)
                                    Divider()
                                    costLine("Coste total estimado", calculation.total)
                                    if let sale = calculation.salePrice { costLine("Precio sugerido (sin impuestos)", sale) }
                                    Text("Margen sobre precio de venta: \(calculation.marginPercent.formatted()) %. Importes estimados antes de impuestos.").font(.caption).foregroundStyle(.secondary)
                                }
                            }.padding(7).frame(maxWidth: .infinity, alignment: .leading)
                        }
                        if !job.notes.isEmpty { ForEach(job.notes, id: \.self) { Text("⚠︎ " + $0).foregroundStyle(.orange) } }
                    } else {
                        VStack(spacing: 12) {
                            Image(systemName: "square.and.arrow.down.on.square").font(.system(size: 50)).foregroundStyle(.secondary)
                            Text("Arrastra aquí un archivo .gcode").font(.title3.bold())
                            Text("También puedes abrirlo con el botón superior.").foregroundStyle(.secondary)
                        }.frame(maxWidth: .infinity, minHeight: 280)
                            .background(RoundedRectangle(cornerRadius: 16).strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [8])).foregroundStyle(dropTarget ? .blue : .gray.opacity(0.45)))
                    }
                }.padding(27).frame(maxWidth: 950, alignment: .leading)
            }
            .onDrop(of: [UTType.fileURL.identifier], isTargeted: $dropTarget) { providers in
                guard let provider = providers.first else { return false }
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    if let url { DispatchQueue.main.async { open(url) } }
                }
                return true
            }
            .alert("No se pudo abrir el G-code", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("Aceptar", role: .cancel) { errorMessage = nil }
            } message: { Text(errorMessage ?? "") }

    }
    private func costLine(_ title: String, _ amount: Double) -> some View {
        LabeledContent(title, value: String(format: "%.4f €", amount))
    }
    private func saveBudget() {
        guard let job else { return }
        if let id = loadedBudgetID, var existing = budgets.budgets.first(where: { $0.id == id }) {
            existing.recipient = recipient; existing.title = budgetTitle; existing.status = budgetStatus; existing.comments = comments
            existing.dryerDuringPrint = dryerDuringPrint
            existing.laborMinutes = laborMinutes
            // Actualizar la instantánea solo cuando cambió el tiempo personal.
            if existing.costSnapshot == nil || laborMinutes != (budgets.budgets.first(where: { $0.id == id })?.laborMinutes ?? 0) {
                existing.costSnapshot = calculation
            }
            budgets.update(existing)
        } else {
            loadedBudgetID = budgets.add(job: job, recipient: recipient, title: budgetTitle.isEmpty ? job.name : budgetTitle, status: budgetStatus, comments: comments, spool: spool, originalURL: originalURL, costs: calculation, dryerDuringPrint: dryerDuringPrint, laborMinutes: laborMinutes)
        }
        if let projectID = pendingProjectBudgetID,
           let id = loadedBudgetID,
           let saved = budgets.budgets.first(where: { $0.id == id }) {
            projects.addPlate(projectID, budgetID: id, objects: budgets.objects(for: saved))
            selectedProjectID = projectID
            pendingProjectBudgetID = nil
            page = "Proyectos"
        } else { page = "Histórico" }
        savedEditorFingerprint = fingerprint
        selectedBudgetID = loadedBudgetID
    }
    private func resetEditor() {
        pendingProjectBudgetID = nil; job = nil; originalURL = nil; loadedBudgetID = nil; recipient = ""; budgetTitle = ""; budgetStatus = "Borrador"; comments = ""; dryerDuringPrint = false; laborMinutes = 0; savedCostSnapshot = nil; page = "Nuevo presupuesto"; savedEditorFingerprint = fingerprint
    }
    private func edit(_ item: SavedBudget) {
        job = item.job; loadedBudgetID = item.id; originalURL = nil
        recipient = item.recipient; budgetTitle = item.title; budgetStatus = item.status; comments = item.comments; dryerDuringPrint = item.dryerDuringPrint ?? false; laborMinutes = item.laborMinutes ?? 0
        savedCostSnapshot = item.costSnapshot
        page = "Nuevo presupuesto"; savedEditorFingerprint = fingerprint
    }
    private var historyView: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack { Text("Histórico de presupuestos").font(.largeTitle.bold()); Spacer(); Button("Nuevo presupuesto") { resetEditor() }.buttonStyle(.borderedProminent) }
            TextField("Buscar por pieza, destinatario o referencia", text: $search).textFieldStyle(.roundedBorder)
            if budgets.budgets.isEmpty {
                VStack { Image(systemName: "tray").font(.largeTitle); Text("Todavía no hay presupuestos"); Text("Carga un G-code y guarda tu primer presupuesto.") }.foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(budgets.budgets.filter { search.isEmpty || ($0.title + " " + $0.recipient + " " + $0.reference).localizedCaseInsensitiveContains(search) }) { item in
                        HStack(spacing: 14) {
                            Group {
                                if let data = item.job.thumbnail, let image = NSImage(data: data) {
                                    Image(nsImage: image).resizable().scaledToFit()
                                } else { Image(systemName: "cube").resizable().scaledToFit().padding(15).foregroundStyle(.secondary) }
                            }.frame(width: 72, height: 72).background(.quaternary.opacity(0.25)).clipShape(RoundedRectangle(cornerRadius: 9))
                            VStack(alignment: .leading, spacing: 6) {
                                HStack { Text(item.reference).font(.caption).foregroundStyle(.secondary); Spacer(); Text(item.status).font(.caption) }
                                Text(item.title).font(.headline)
                                HStack {
                                    Text(item.recipient.isEmpty ? "Sin destinatario" : item.recipient)
                                    Text("·")
                                    Text(item.createdAt, style: .date)
                                    Spacer()
                                    Text(String(format: "Coste %.2f €", item.costSnapshot?.total ?? item.filamentCostAtSave ?? 0))
                                }.font(.caption).foregroundStyle(.secondary)
                            }
                            Button { budgets.remove(item.id) } label: { Image(systemName: "trash") }.help("Eliminar presupuesto").buttonStyle(.borderless)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { edit(item) }
                        .contextMenu { Button("Abrir / editar") { edit(item) }; Button("Duplicar") { let id = budgets.duplicate(item); if let duplicated = budgets.budgets.first(where: { $0.id == id }) { edit(duplicated) } }; Button("Eliminar", role: .destructive) { budgets.remove(item.id) } }
                        .padding(.vertical, 5)
                    }
                }
            }
            if let message = budgets.message { Text(message).foregroundStyle(.orange).font(.caption) }
        }.padding(24)
    }
    private func chooseFile() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [UTType(filenameExtension: "gcode") ?? .plainText]; panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url { open(url) }
    }
    private func open(_ url: URL) {
        guard url.pathExtension.lowercased() == "gcode" else { errorMessage = "Selecciona un fichero con extensión .gcode"; return }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do { job = try GCodeParser.parse(url); originalURL = url; loadedBudgetID = nil; savedCostSnapshot = nil; dryerDuringPrint = false; laborMinutes = 0; budgetTitle = job?.name ?? ""; recipient = ""; comments = ""; budgetStatus = "Borrador"; page = "Nuevo presupuesto"; savedEditorFingerprint = "" }
        catch { errorMessage = error.localizedDescription }
    }
    private func formattedDuration(_ seconds: Int?) -> String {
        guard let s = seconds else { return "No disponible" }
        return "\(s / 3600) h \((s % 3600) / 60) min \(s % 60) s"
    }
}

struct SettingsView: View {
    @EnvironmentObject private var store: CatalogStore
    @EnvironmentObject private var costs: CostStore
    @EnvironmentObject private var documents: DocumentStore
    @Environment(\.dismiss) private var dismiss
    @State private var selected = "Filamentos"
    var body: some View {
        HStack(spacing: 0) {
            List(selection: $selected) {
                Label("Filamentos", systemImage: "shippingbox").tag("Filamentos")
                Label("Impresoras", systemImage: "printer").tag("Impresoras")
                Label("Electricidad", systemImage: "bolt").tag("Electricidad")
                Label("Costes", systemImage: "eurosign.circle").tag("Costes")
                Label("Documentos", systemImage: "doc.plaintext").tag("Documentos")
            }.listStyle(.sidebar).frame(width: 180)
            Divider()
            VStack(alignment: .leading, spacing: 13) {
                HStack { Text(selected).font(.title2.bold()); Spacer(); Button("Cerrar") { dismiss() } }
                if selected == "Filamentos" {
                    Text("Catálogo local · sin conexión automática").foregroundStyle(.secondary)
                    HStack {
                        TextField("Dirección de Spoolman", text: $store.catalog.serverURL).textFieldStyle(.roundedBorder)
                            .onSubmit { store.save() }
                        Button("Guardar URL") { store.save() }
                        Button { store.save(); Task { await store.importSpools() } } label: {
                            if store.isImporting { ProgressView().controlSize(.small) } else { Label("Importar", systemImage: "arrow.down.circle") }
                        }.disabled(store.isImporting).buttonStyle(.borderedProminent)
                    }
                    HStack {
                        Text("\(store.catalog.spools.count) bobinas")
                        Spacer()
                        if let date = store.catalog.lastImported { Text("Última importación: \(date.formatted(date: .abbreviated, time: .shortened))") }
                    }.font(.caption).foregroundStyle(.secondary)
                    if !store.message.isEmpty { Text(store.message).font(.caption).foregroundStyle(store.message.hasPrefix("Error") ? .red : .secondary) }
                    List {
                        ForEach($store.catalog.spools) { $spool in
                            VStack(alignment: .leading, spacing: 4) {
                                Text("#\(spool.id)  \(spool.vendor) \(spool.name)").fontWeight(.semibold)
                                HStack {
                                    Text(spool.material).foregroundStyle(.secondary)
                                    Spacer()
                                    Text("Peso: \(spool.initialWeightG.map { String(format: "%.0f g", $0) } ?? "—")")
                                    Text("Importado: \(spool.priceEUR.map { String(format: "%.2f €", $0) } ?? "—")")
                                }.font(.caption)
                                HStack {
                                    Text("Precio manual (€):").font(.caption)
                                    TextField("Automático", value: $spool.manualPrice, format: .number.precision(.fractionLength(2)))
                                        .frame(width: 115).textFieldStyle(.roundedBorder).onSubmit { store.save() }
                                    Button("Guardar") { store.save() }.font(.caption)
                                }
                            }.padding(.vertical, 4)
                        }
                    }.overlay { if store.catalog.spools.isEmpty { VStack(spacing: 8) { Image(systemName: "shippingbox").font(.largeTitle); Text("Sin filamentos").font(.headline); Text("Conecta con Spoolman una vez e importa tu catálogo.").font(.caption) }.foregroundStyle(.secondary) } }
                } else if selected == "Electricidad" || selected == "Impresoras" || selected == "Costes" {
                    Form {
                        if selected == "Impresoras" {
                            Text("Ender 3 V2 · Media PETG medida: 99,6 W (25/10/2026)").font(.caption)
                            costField("Potencia media impresora (W)", value: $costs.settings.printerWatts)
                            costField("Inversión pendiente de amortizar (€)", value: $costs.settings.machineInvestmentEUR)
                            costField("Horas productivas futuras estimadas", value: $costs.settings.machineRemainingHours)
                            costField("Mantenimiento (€/h)", value: $costs.settings.maintenanceEURHour)
                        } else if selected == "Electricidad" {
                            costField("Precio efectivo electricidad (€/kWh)", value: $costs.settings.electricityEURkWh)
                            costField("Potencia media impresora (W)", value: $costs.settings.printerWatts)
                            costField("Potencia secador (W)", value: $costs.settings.dryerWatts)
                            Text("Secador PETG: 59,1 W medidos. Solo se suma su electricidad cuando activas «Secado durante la impresión». Su inversión ya está incluida en la amortización general.").font(.caption).foregroundStyle(.secondary)
                            Text("Factura Octopus Relax (sep. 2026): 0,122 €/kWh sin impuestos; aprox. 0,15516 €/kWh con impuesto eléctrico e IVA. No incluyas los costes fijos de la vivienda.").font(.caption).foregroundStyle(.secondary)
                        } else {
                            Text("El tiempo dedicado se introduce individualmente en cada presupuesto. Aquí solo se configura tu tarifa por hora.").font(.caption).foregroundStyle(.secondary)
                            costField("Tarifa mano de obra cualificada (€/h)", value: $costs.settings.laborEURHour)
                            costField("Consumibles por trabajo (€)", value: $costs.settings.consumablesEURJob)
                            costField("Embalaje por trabajo (€)", value: $costs.settings.packagingEURJob)
                            costField("Reserva por fallos (%)", value: $costs.settings.failureReservePercent)
                            costField("Margen bruto sobre venta (%)", value: $costs.settings.marginPercent)
                        }
                    }.formStyle(.grouped)
                    Text("Los cambios se guardan automáticamente. Los presupuestos históricos conservan sus importes guardados.").font(.caption).foregroundStyle(.secondary)
                } else if selected == "Documentos" {
                    Form {
                        Section("Datos para tus presupuestos PDF") {
                            TextField("Nombre / emisor", text: $documents.settings.issuerName)
                            TextField("Contacto (opcional)", text: $documents.settings.issuerContact)
                            Stepper("Validez: \(documents.settings.validityDays) días", value: $documents.settings.validityDays, in: 1...180)
                        }
                        Section("Condiciones") {
                            TextEditor(text: $documents.settings.conditions).frame(minHeight: 90)
                        }
                    }.formStyle(.grouped)
                    Text("Opcional. Estos datos aparecerán en el PDF del cliente. El gráfico económico y los costes privados se reservan al informe interno.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }.padding(18)
        }
    }
    private func costField(_ label: String, value: Binding<Double>) -> some View {
        HStack {
            Text(label)
            Spacer()
            TextField("0", value: value, format: .number).frame(width: 120).textFieldStyle(.roundedBorder)
        }
    }
}

// Exportación local sin servicios externos. Core Text compone texto vectorial en PDF.
private enum ProjectPDFWriter {
    enum PDFError: LocalizedError {
        case cannotCreate
        var errorDescription: String? { "No se pudo crear el contexto PDF." }
    }
    static func write(to url: URL, project: PrintProject, references: [PartReference], orders: [PartOrder],
                      spools: [Spool], estimate: CostBreakdown, seconds: Int, grams: Double,
                      internalReport: Bool, documents: DocumentSettings) throws {
        var bounds = CGRect(x: 0, y: 0, width: 595, height: 842) // A4, puntos
        guard let consumer = CGDataConsumer(url: url as CFURL),
              let ctx = CGContext(consumer: consumer, mediaBox: &bounds, nil) else { throw PDFError.cannotCreate }
        let frozen = project.issuedQuote
        let reportEstimate = frozen?.components ?? estimate
        let finalPrice = frozen?.finalPrice ?? project.agreedPriceEUR ?? estimate.salePrice ?? 0
        let pdfLines: [QuoteLine] = frozen?.lines ?? orders.map { order in
            let ref = references.first { $0.id == order.referenceID }
            let spool = spools.first { $0.id == order.spoolID }
            return QuoteLine(piece: ref?.name ?? "Pieza", spool: spool?.name ?? "Sin bobina", quantity: order.quantity)
        }
        let ink = CGColor(gray: 0.16, alpha: 1)
        let muted = CGColor(gray: 0.45, alpha: 1)
        let accent = CGColor(srgbRed: 0.16, green: 0.38, blue: 0.72, alpha: 1)
        let pale = CGColor(srgbRed: 0.94, green: 0.96, blue: 0.985, alpha: 1)
        var y: CGFloat = 790
        var page = 0
        func startPage() {
            ctx.beginPDFPage(nil); page += 1; y = 790
            ctx.setFillColor(accent)
            ctx.fill(CGRect(x: 42, y: 814, width: 511, height: 5))
            ctx.setFillColor(pale)
            ctx.fill(CGRect(x: 42, y: 730, width: 511, height: 75))
        }
        func line(_ value: String, size: CGFloat = 11, bold: Bool = false,
                  indent: CGFloat = 46, color: CGColor? = nil, advance: CGFloat = 19) {
            if y < 72 { ctx.endPDFPage(); startPage() }
            let font = CTFontCreateWithName((bold ? "Helvetica-Bold" : "Helvetica") as CFString, size, nil)
            let attrs: [NSAttributedString.Key: Any] = [
                NSAttributedString.Key(kCTFontAttributeName as String): font,
                NSAttributedString.Key(kCTForegroundColorAttributeName as String): color ?? ink
            ]
            let text = NSAttributedString(string: value, attributes: attrs)
            let ct = CTLineCreateWithAttributedString(text)
            ctx.textPosition = CGPoint(x: indent, y: y)
            CTLineDraw(ct, ctx)
            y -= advance
        }
        func separator() {
            if y < 72 { ctx.endPDFPage(); startPage() }
            ctx.setStrokeColor(CGColor(gray: 0.87, alpha: 1))
            ctx.setLineWidth(0.7)
            ctx.move(to: CGPoint(x: 46, y: y))
            ctx.addLine(to: CGPoint(x: 549, y: y))
            ctx.strokePath()
            y -= 18
        }
        func money(_ v: Double) -> String { String(format: "%.2f EUR", v) }
        startPage()
        line((frozen?.issuerName ?? documents.issuerName).isEmpty ? "STLBudget" : (frozen?.issuerName ?? documents.issuerName), size: 12, bold: true, color: accent, advance: 19)
        let contact = frozen?.issuerContact ?? documents.issuerContact
        if !contact.isEmpty { line(contact, size: 9, color: muted, advance: 18) }
        y = min(y, 764)
        line(internalReport ? "INFORME INTERNO DE COSTES" : "PRESUPUESTO", size: 23, bold: true, advance: 35)
        line("Proyecto: \(frozen?.projectName ?? project.name)", size: 13, bold: true, advance: 24)
        let customer = frozen?.customer ?? project.customer
        line("Destinatario: \(customer.isEmpty ? "Sin especificar" : customer)")
        line("Fecha: \((frozen?.issuedAt ?? Date()).formatted(date: .numeric, time: .omitted))", color: muted)
        separator()
        line("PIEZAS DEL PEDIDO", size: 12, bold: true, advance: 26)
        for item in pdfLines {
            line("\(item.quantity)x  \(item.piece)  -  \(item.spool)", size: 10.5, advance: 19)
        }
        separator()
        let units = pdfLines.reduce(0) { $0 + $1.quantity }
        line("Unidades: \(units)")
        if internalReport {
            line(String(format: "Filamento total: %.2f g", grams))
            line(String(format: "Horas estimadas: %.2f h", Double(seconds) / 3600))
            separator()
            line("DESGLOSE ECONOMICO", size: 12, bold: true, advance: 25)
            let rows: [(String, Double)] = [
                ("Filamento", reportEstimate.filament),
                ("Electricidad impresora", reportEstimate.electricity),
                ("Electricidad secador", reportEstimate.dryer),
                ("Amortizacion", reportEstimate.depreciation),
                ("Mantenimiento", reportEstimate.maintenance),
                ("Mano de obra", reportEstimate.labor),
                ("Consumibles y embalaje", reportEstimate.others),
                ("Reserva por fallos", reportEstimate.risk)
            ]
            for (title, amount) in rows { line(String(format: "%@: %.4f EUR", title, amount), size: 10.5) }
            separator()
            // Gráfico circular vectorial en el informe interno, calculado con los importes congelados si existen.
            let colors: [CGColor] = [
                CGColor(srgbRed: 0.95, green: 0.49, blue: 0.16, alpha: 1),
                CGColor(srgbRed: 0.15, green: 0.54, blue: 0.91, alpha: 1),
                CGColor(srgbRed: 0.10, green: 0.70, blue: 0.82, alpha: 1),
                CGColor(srgbRed: 0.72, green: 0.27, blue: 0.85, alpha: 1),
                CGColor(srgbRed: 0.37, green: 0.37, blue: 0.88, alpha: 1),
                CGColor(srgbRed: 0.20, green: 0.70, blue: 0.42, alpha: 1),
                CGColor(srgbRed: 0.66, green: 0.47, blue: 0.35, alpha: 1),
                CGColor(srgbRed: 0.57, green: 0.57, blue: 0.60, alpha: 1)
            ]
            if reportEstimate.total > 0 {
                let center = CGPoint(x: 140, y: y - 93)
                let radius: CGFloat = 78
                var angle: CGFloat = .pi / 2
                for (index, row) in rows.enumerated() where row.1 > 0 {
                    let sweep = CGFloat(row.1 / reportEstimate.total) * .pi * 2
                    ctx.beginPath(); ctx.move(to: center)
                    ctx.addArc(center: center, radius: radius, startAngle: angle, endAngle: angle + sweep, clockwise: false)
                    ctx.closePath(); ctx.setFillColor(colors[index]); ctx.fillPath()
                    angle += sweep
                }
                ctx.setFillColor(CGColor(gray: 1, alpha: 1))
                ctx.fillEllipse(in: CGRect(x: center.x - 40, y: center.y - 40, width: 80, height: 80))
                y -= 185
                separator()
            }
            line("Coste estimado: \(money(reportEstimate.total))", size: 13, bold: true, advance: 24)
            line(String(format: "Margen bruto: %.1f %%", reportEstimate.marginPercent))
        }
        line("PRECIO FINAL: \(money(finalPrice))", size: 16, bold: true, advance: 30)
        line("Importes estimados sin impuestos.", size: 9.5, color: muted)
        if internalReport {
            line("Documento interno: no enviar al cliente.", size: 9.5, color: muted)
        } else {
            line("Validez: \(frozen?.validDays ?? documents.validityDays) días.", size: 9.5, color: muted)
            let terms = frozen?.conditions ?? documents.conditions
            if !terms.isEmpty { line(String(terms.prefix(100)), size: 9.5, color: muted) }
        }
        ctx.endPDFPage()
        ctx.closePDF()
    }
}
