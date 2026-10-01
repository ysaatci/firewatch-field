import FireWatchCore
import MapKit
import PhotosUI
import SwiftUI

/// Report something seen from the ground: where, how bad, what, and optionally a photo (FR-7).
/// Works offline: the report waits in the outbox until it can be sent.
struct ReportScreen: View {
    @Environment(AppModel.self) private var model
    @Environment(LocationProvider.self) private var location

    @State private var severity = Severity.moderate
    @State private var note = ""
    @State private var position = MapCameraPosition.automatic
    @State private var pin: Coordinate?
    @State private var photoItem: PhotosPickerItem?
    @State private var photo: Data?
    @State private var confirmation: String?

    var body: some View {
        Form {
            Section {
                Map(position: $position) {
                    UserAnnotation()
                }
                .mapStyle(.hybrid)
                .frame(height: 220)
                .overlay {
                    Image(systemName: "plus")
                        .font(.title.bold())
                        .foregroundStyle(.white)
                        .shadow(radius: 2)
                        .accessibilityHidden(true)
                }
                .onMapCameraChange { context in pin = Coordinate(context.region.center) }
                .onAppear(perform: startAtKnownPosition)
                .listRowInsets(EdgeInsets())
                .accessibilityLabel("Location of the sighting; move the map to adjust")
            } header: {
                Text("Where")
            } footer: {
                Text("Move the map so the cross is on what you saw. It starts at your position.")
            }

            Section("How bad") {
                Picker("Severity", selection: $severity) {
                    ForEach(Severity.allCases, id: \.self) { level in
                        Text(level.label).tag(level)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("severity")
            }

            Section("What you see") {
                TextField("Smoke behind the ridge, flames, people at risk…", text: $note, axis: .vertical)
                    .lineLimit(3...6)
                    .accessibilityIdentifier("note")
            }

            Section("Photo") {
                // The picker's label closure is Sendable, so it gets a copy rather than reading state.
                let hasPhoto = photo != nil
                PhotosPicker(selection: $photoItem, matching: .images) {
                    Label(hasPhoto ? "Replace the photo" : "Add a photo", systemImage: "photo")
                }
                if let photo, let image = UIImage(data: photo) {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 180)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    Button("Remove the photo", role: .destructive) { self.photo = nil }
                }
            }

            Section {
                Button(action: submit) {
                    Label("Send report", systemImage: "paperplane.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(pin == nil || note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityIdentifier("submitReport")
            } footer: {
                if let confirmation {
                    Label(confirmation, systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .accessibilityIdentifier("reportConfirmation")
                }
            }

            if !model.field.queuedReports.isEmpty {
                Section("Waiting to send") {
                    ForEach(model.field.queuedReports) { report in
                        Label {
                            Text(report.note).lineLimit(2)
                        } icon: {
                            Image(systemName: report.severity.symbol).foregroundStyle(report.severity.color)
                        }
                        .accessibilityIdentifier("queuedReport")
                    }
                }
            }
        }
        .navigationTitle("Report")
        .onChange(of: photoItem) { _, item in
            Task {
                guard let item, let data = try? await item.loadTransferable(type: Data.self) else { return }
                photo = PhotoProcessor.prepare(data)
            }
        }
    }

    /// Starts the map at the user, or failing that at the fire, about a kilometre across.
    private func startAtKnownPosition() {
        let fire = model.field.fire.latestPerimeter?.boundingBox?.center
        guard let centre = location.coordinate ?? fire else { return }
        position = .region(
            MKCoordinateRegion(center: centre.clLocation, latitudinalMeters: 1_000, longitudinalMeters: 1_000))
    }

    private func submit() {
        guard let pin else { return }
        let photoFileName = photo.flatMap { try? PhotoStore.save($0) }
        let report = SightingReport(
            createdAt: .now, coordinate: pin, severity: severity,
            note: note.trimmingCharacters(in: .whitespacesAndNewlines), photoFileName: photoFileName)
        Task { await model.submit(report) }
        // It's queued, not yet sent: the badge shows it until the server has it.
        confirmation = String(localized: "Report saved. It is sent as soon as there's signal.")
        note = ""
        photo = nil
        photoItem = nil
    }
}
