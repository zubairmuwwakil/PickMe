import CardCopilotStore
import MapKit
import SwiftUI

struct ArrivalPlacesView: View {
    @State var model: ArrivalPlacesModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var searchText = ""
    @State private var submittedQuery = ""
    @State private var searchRequest = UUID()
    @State private var selected: ArrivalPlaceChoice?
    @FocusState private var searchIsFocused: Bool
    let onSetup: () -> Void

    var body: some View {
        List {
            if model.runtimeStatus.hasSystemBlocker {
                Section {
                    Label("Arrival alerts need attention", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                    Text("You can save places now. Check arrival setup to receive advice when you get there.")
                        .font(.subheadline).foregroundStyle(.secondary)
                    Button("Open arrival setup", action: onSetup)
                }
            }

            Section {
                TextField("Store name, street or city", text: $searchText)
                    .focused($searchIsFocused)
                    .submitLabel(.search)
                    .onSubmit(submitSearch)
                Button(action: submitSearch) {
                    Label("Search for a merchant", systemImage: "magnifyingglass")
                }
                .disabled(searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            } header: {
                Text("Add a merchant")
            } footer: {
                Text("Include a city or street to find the right branch. Search works without location permission.")
            }

            if model.isSearching {
                Section { ProgressView("Searching places…") }
            } else if model.hasSearched {
                Section("Results for \(submittedQuery)") {
                    if model.searchResults.isEmpty {
                        Text("No physical locations found. Try a store name with a city or street; an internet connection is needed to find branches.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(model.searchResults) { merchant in
                        merchantRow(merchant, detail: merchant.locationDescription ?? "Check this branch in Maps")
                    }
                }
            }

            Section {
                if model.preferences.isEmpty {
                    Text("Add a merchant above, or choose a store from the lists below.")
                        .foregroundStyle(.secondary)
                }
                ForEach(model.preferences) { preference in
                    let merchant = model.merchant(for: preference)
                    merchantRow(merchant, detail: preferenceDetail(preference), preference: preference)
                }
            } header: {
                Text("Your alert choices")
            } footer: {
                Text("Saved choices stay here even when their locations are outside current coverage. Tap any merchant to change its alerts.")
            }

            Section {
                if model.monitoredPlaces.isEmpty || !model.runtimeStatus.locationAlways {
                    Text(model.runtimeStatus.locationAlways
                         ? "No places are registered yet. Refresh nearby monitoring to try again."
                         : "Enable Always Location in arrival setup to start monitoring.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(model.monitoredPlaces) { place in
                        DisclosureGroup {
                            Button("View area in Maps") {
                                openArrivalPlaceInMaps(name: "Shopping area", latitude: place.latitude,
                                                      longitude: place.longitude)
                            }
                            if place.merchants.isEmpty {
                                Text("Place details are no longer cached. Refresh nearby monitoring to update this area.")
                                    .foregroundStyle(.secondary)
                            }
                            ForEach(place.merchants) { merchant in
                                merchantRow(merchant, detail: status(for: merchant))
                            }
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(place.merchants.first.map { "Near \($0.name)" } ?? "Shopping area")
                                Text("\(place.merchants.count) saved or discovered stores")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                Button("Refresh nearby monitoring") { model.refreshNearby() }
                    .disabled(!model.runtimeStatus.locationAlways)
            } header: {
                Text("Monitoring now · \(model.runtimeStatus.locationAlways ? model.monitoredPlaces.count : 0)/20 areas")
            } footer: {
                Text("These areas are registered with iOS. One area can cover several stores, including stores whose alerts are off. Nearby places share 20 slots and update as you move. Monitoring does not guarantee an alert on every visit.")
            }

            if !model.otherSavedMerchants.isEmpty {
                Section("Other saved merchants") {
                    ForEach(model.otherSavedMerchants) { merchant in
                        merchantRow(merchant, detail: status(for: merchant))
                    }
                }
            }

            if model.mutedMerchantCount > 0 {
                Section {
                    Text("\(model.mutedMerchantCount) locations muted from notifications")
                    Button("Unmute all locations") { Task { await model.unmuteAll() } }
                } header: {
                    Text("Notification mutes")
                } footer: {
                    Text("This clears notification mutes. Merchants you set to Alerts off above will stay off.")
                }
            }
            if !model.arrivalExplanations.records.isEmpty {
                Section {
                    Button("Clear arrival explanations") { model.clearArrivalExplanations() }
                } footer: {
                    Text("The latest arrival check for each place expires after seven days. Clearing explanations leaves purchases and alert choices unchanged.")
                }
            }
        }
        .navigationTitle("Monitored places")
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.refresh() }
        .task(id: searchRequest) { await model.search(submittedQuery) }
        .onChange(of: searchText) { _, text in
            if text.isEmpty {
                submittedQuery = ""
                searchRequest = UUID()
            }
        }
        .refreshable { await model.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: AmbientLocationService.monitoringDidChange)) { _ in
            Task { await model.refresh() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await model.refresh() } }
        }
        .sheet(item: $selected) { choice in
            ArrivalPlaceSettingsView(model: model, choice: choice)
        }
        .alert("Could not update places", isPresented: Binding(
            get: { model.error != nil && selected == nil }, set: { if !$0 { model.error = nil } })) {
                Button("OK") { model.error = nil }
        } message: {
            Text(model.error ?? "Please try again.")
        }
    }

    private func submitSearch() {
        searchIsFocused = false
        submittedQuery = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        searchRequest = UUID()
    }

    private func merchantRow(_ merchant: NearbyPlace, detail: String,
                             preference: ArrivalAlertPreference? = nil) -> some View {
        HStack(spacing: 12) {
            Button {
                selected = ArrivalPlaceChoice(merchant: merchant, preference: preference ?? model.preference(for: merchant))
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(merchant.name).foregroundStyle(.primary)
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if merchant.hasMonitorableLocation {
                Button {
                    openArrivalPlaceInMaps(name: merchant.name, latitude: merchant.latitude, longitude: merchant.longitude)
                } label: {
                    Image(systemName: "map")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Show \(merchant.name) in Maps")
            }
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .padding(.vertical, 3)
    }

    private func preferenceDetail(_ preference: ArrivalAlertPreference) -> String {
        let merchant = model.merchant(for: preference)
        let location = preference.locationDescription.map { "\n\($0)" } ?? ""
        if preference.scope == .disabled { return "Alerts off\(location)" }
        if preference.scope == .chain {
            let covered = model.runtimeStatus.locationAlways && model.monitoredPlaces.contains { place in
                place.merchants.contains { merchantActivityKey(name: $0.name, locationIdentifier: $0.id) == preference.merchantKey }
            }
            return "Any nearby branch · \(covered ? "Area monitored now" : "Saved for when nearby")"
        }
        if !merchant.hasMonitorableLocation { return "Automatic · PickMe chooses nearby places" }
        return "\(preference.scope.arrivalTitle) · \(status(for: merchant))\(location)"
    }

    private func status(for merchant: NearbyPlace) -> String {
        if let preference = model.preference(for: merchant) {
            if preference.scope == .disabled { return "Alerts off" }
            if preference.scope == .exactLocation,
               !preference.matchesLocation(identifier: merchant.id, latitude: merchant.latitude, longitude: merchant.longitude) {
                return "Another branch selected · alerts off here"
            }
        }
        if model.isMuted(merchant) { return "Muted from a notification" }
        if !model.runtimeStatus.locationAlways { return "Saved · arrival alerts not enabled" }
        if model.isMonitoring(merchant) {
            return model.runtimeStatus.hasSystemBlocker ? "Area monitored · delivery needs attention" : "Monitoring now"
        }
        return "Saved · outside current coverage"
    }
}

private struct ArrivalPlaceChoice: Identifiable {
    var id: String { merchant.id }
    let merchant: NearbyPlace
    let preference: ArrivalAlertPreference?
}

private struct ArrivalPlaceSettingsView: View {
    let model: ArrivalPlacesModel
    let choice: ArrivalPlaceChoice
    @Environment(\.dismiss) private var dismiss
    @State private var scope: ArrivalAlertScope = .exactLocation
    @State private var isSaving = false

    private var merchantKey: String? {
        choice.preference?.merchantKey
            ?? merchantActivityKey(name: choice.merchant.name, locationIdentifier: choice.merchant.id)
    }

    var body: some View {
        NavigationStack {
            Form {
                if let error = model.error {
                    Section { Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.orange) }
                }
                Section {
                    Text(choice.merchant.name).font(.headline)
                    if let address = choice.merchant.locationDescription { Text(address) }
                    if choice.merchant.hasMonitorableLocation {
                        Button("Check this location in Maps") {
                            openArrivalPlaceInMaps(name: choice.merchant.name, latitude: choice.merchant.latitude,
                                                  longitude: choice.merchant.longitude)
                        }
                    }
                }
                ArrivalExplanationSection(model: model, merchant: choice.merchant)
                Section {
                    Picker("Arrival alerts", selection: $scope) {
                        if choice.merchant.hasMonitorableLocation {
                            Text("Only this location").tag(ArrivalAlertScope.exactLocation)
                        }
                        if let merchantKey, supportsChainArrivalAlerts(merchantKey: merchantKey) {
                            Text("Any nearby branch").tag(ArrivalAlertScope.chain)
                        }
                        Text("Choose automatically").tag(ArrivalAlertScope.automatic)
                        Text("Alerts off for this merchant").tag(ArrivalAlertScope.disabled)
                    }
                    .pickerStyle(.inline)
                } footer: {
                    Text(scopeExplanation)
                }
                if model.isMuted(choice.merchant), scope != .disabled {
                    Section {
                        Text("Saving will also unmute this location.")
                    }
                }
                Section {
                    Text("Places share up to 20 monitored areas. Saving a choice does not reserve a slot; nearby coverage updates as you move.")
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Merchant alerts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        isSaving = true
                        Task {
                            if await model.save(scope, merchant: choice.merchant, merchantKey: merchantKey) { dismiss() }
                            isSaving = false
                        }
                    }
                    .disabled(isSaving)
                }
            }
            .interactiveDismissDisabled(isSaving)
            .onAppear {
                model.error = nil
                if let existing = choice.preference {
                    scope = existing.scope == .exactLocation && !choice.merchant.hasMonitorableLocation
                        ? .automatic : existing.scope
                } else {
                    scope = choice.merchant.hasMonitorableLocation ? .exactLocation : .automatic
                }
            }
        }
    }

    private var scopeExplanation: String {
        switch scope {
        case .exactLocation:
            return "Use arrival alerts at this branch only. This replaces any previous branch choice for this merchant."
        case .chain:
            return "Allow arrival alerts at branches PickMe discovers nearby. It does not monitor every branch at once."
        case .automatic:
            return "Let PickMe use nearby places and your visits to choose arrival advice."
        case .disabled:
            return "Turn off arrival advice for this merchant, including its other branches. You can change this here anytime."
        }
    }
}

private extension ArrivalAlertScope {
    var arrivalTitle: String {
        switch self {
        case .chain: return "Any nearby branch"
        case .exactLocation: return "Only this location"
        case .automatic: return "Automatic"
        case .disabled: return "Alerts off"
        }
    }
}

private func openArrivalPlaceInMaps(name: String, latitude: Double, longitude: Double) {
    let item = MKMapItem(placemark: MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude)))
    item.name = name
    item.openInMaps()
}
