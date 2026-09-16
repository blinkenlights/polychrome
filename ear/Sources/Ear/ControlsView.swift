import CoreAudio
import EarKit
import SwiftUI

struct ControlsView: View {
    @Bindable var model: AppModel

    var body: some View {
        Form {
            Section("Geometrie") {
                TextField("octopus", text: $model.octopusURL)
                    .onSubmit { Task { await model.reloadLayout() } }
                HStack {
                    if model.layoutFromOctopus {
                        Label("von octopus", systemImage: "checkmark.circle").foregroundStyle(.green)
                    } else {
                        Label("Fallback-Ring", systemImage: "exclamationmark.triangle").foregroundStyle(.orange)
                    }
                    Spacer()
                    Button("Neu laden") { Task { await model.reloadLayout() } }
                }
                if let error = model.layoutError {
                    Text(error).font(.caption).foregroundStyle(.orange)
                }
            }

            Section("Eingang") {
                Picker("Gerät", selection: $model.selectedInputID) {
                    Text("Keiner, nur Testton").tag(AudioObjectID?.none)
                    ForEach(model.inputs) { device in
                        Text("\(device.name) (\(device.inputChannels))").tag(AudioObjectID?.some(device.id))
                    }
                }
                .onChange(of: model.selectedInputID) { Task { await model.rebuild() } }

                if let description = model.rigDescription {
                    Text(description).foregroundStyle(.secondary)
                }
                if model.selectedInputID != nil {
                    Text(bufferStatus).foregroundStyle(.secondary).monospacedDigit()
                }
                if let error = model.engineError {
                    Text(error).foregroundStyle(.red)
                }
                if let warning = model.feedbackWarning {
                    Text(warning).foregroundStyle(.orange)
                }
                Button("Geräte aktualisieren") { model.refreshDevices() }
            }

            Section("Hörer") {
                LabeledContent("Blick", value: headingText)
                Slider(value: $model.listener.heading, in: 0...360, step: 1)
                LabeledContent(
                    "Ort",
                    value: String(format: "%.1f m O, %.1f m N", model.listener.position.x, model.listener.position.y)
                )
                Button("Zurück auf die Plattform") { model.resetListener() }
            }

            Section("Kopf") {
                Toggle("Kopfbewegung", isOn: $model.sway)
                Text("Dreht den Kopf langsam um ±7°. Ohne diese Bewegung hört man vorne oft als hinten.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Toggle("Headtracking (AirPods)", isOn: $model.headTracking)
                    .disabled(!model.headTrackingAvailable)
                if model.headTracking {
                    Text("\(model.headState.text) · \(Int(model.headTurn))°")
                        .font(.caption)
                        .foregroundStyle(model.headState == .tracking ? Color.secondary : Color.orange)
                    Toggle("Richtung umkehren", isOn: $model.headTrackingInverted)
                    Button("Geradeaus neu setzen") { model.recenterHead() }
                } else if !model.headTrackingAvailable {
                    Text("Keine Kopfhörer mit Bewegungssensor verbunden.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Raum") {
                LabeledContent("Hall") { Slider(value: $model.reverb, in: 0...1) }
                LabeledContent("Abstand") { Slider(value: $model.rolloff, in: 0...2) }
                LabeledContent("Pegel") { Slider(value: $model.gain, in: 0...2) }
            }

            Section("Test") {
                Button("Ping reihum, ab Norden im Uhrzeigersinn") { model.pingAround() }
                Text("Einzelne Panels antippen geht auch. Der Ping kommt aus der App selbst, ohne scsynth. Wenn er nicht dort erklingt, wo das Panel leuchtet, stimmt die Orientierung nicht.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var bufferStatus: String {
        let state = model.primed ? "läuft" : "füllt sich"
        return "Puffer \(state) · Aussetzer \(model.underruns) · Sprünge \(model.overruns)"
    }

    private var headingText: String {
        let names = ["N", "NO", "O", "SO", "S", "SW", "W", "NW"]
        let index = Int((model.listener.heading / 45).rounded()) % 8
        return String(format: "%.0f° (%@)", model.listener.heading, names[index])
    }
}
