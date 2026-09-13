import AppKit
import CoreGraphics
import ModelOEternalConfigurationCore
import SwiftUI

struct ContentView: View {
  private enum Section: String, CaseIterable, Identifiable {
    case lighting = "Lighting"
    case sensitivity = "Sensitivity"
    case buttons = "Buttons"
    case advanced = "Advanced"
    case device = "Device"
    var id: Self { self }
    var icon: String {
      switch self {
      case .lighting: "lightbulb"
      case .sensitivity: "scope"
      case .buttons: "computermouse"
      case .advanced: "slider.horizontal.3"
      case .device: "info.circle"
      }
    }
  }

  @State private var selected: Section? = .lighting
  @State private var lighting = LightingSettings(
    effect: .glorious, color: .init(red: 124, green: 58, blue: 237), brightness: 4, speed: 2)
  @State private var sensitivity = SensitivitySettings(
    stages: (1...8).map {
      .init(id: $0, dpi: $0 * 400, color: .init(red: 124, green: 58, blue: 237), isEnabled: $0 <= 4)
    }, activeStage: 1, pollingRate: .hz1000)
  @State private var buttons = ButtonSettings(
    actions: ["left-click", "right-click", "middle-click", "back", "forward", "dpi-cycle"]
      .compactMap(ButtonAction.init))
  @State private var advanced = AdvancedSettings(
    debounceMilliseconds: 0, liftOffDistance: .threeMillimeters)
  @State private var firmware = "Unknown"
  @State private var isConnected = false
  @State private var isWorking = false
  @State private var message = "Connect your Model O Eternal."
  @State private var hasInputAccess = CGPreflightListenEventAccess()
  @State private var permissionMessage: String?
  private let mouse = ModelOEternalDevice()

  var body: some View {
    NavigationSplitView {
      List(Section.allCases, selection: $selected) { item in
        Label(item.rawValue, systemImage: item.icon).tag(item)
      }
      .navigationTitle("Model O Eternal")
      .navigationSplitViewColumnWidth(min: 180, ideal: 200)
    } detail: {
      if hasInputAccess { detail } else { accessRequest }
    }
    .frame(minWidth: 760, minHeight: 540)
    .onAppear { if hasInputAccess { refresh() } }
  }

  private var detail: some View {
    VStack(alignment: .leading, spacing: 0) {
      Group {
        switch selected ?? .lighting {
        case .lighting: lightingPage
        case .sensitivity: sensitivityPage
        case .buttons: buttonsPage
        case .advanced: advancedPage
        case .device: devicePage
        }
      }
      Spacer(minLength: 16)
      Divider()
      HStack {
        Circle().fill(isConnected ? Color.green : Color.red).frame(width: 8, height: 8)
        Text(message).foregroundStyle(.secondary).lineLimit(2)
        Spacer()
        Button("Refresh", action: refresh).disabled(isWorking)
        if selected != .device {
          Button("Apply", action: apply).buttonStyle(.borderedProminent).disabled(
            !isConnected || isWorking)
        }
      }
      .padding(.top, 14)
    }
    .padding(24)
  }

  private var lightingPage: some View {
    Form {
      pageTitle("Lighting", "Set the built-in LED effect.")
      Picker("Effect", selection: $lighting.effect) {
        ForEach(LightingEffect.allCases) { Text($0.name).tag($0) }
      }
      if lighting.effect.usesColor {
        ColorPicker("Color", selection: lightingColor, supportsOpacity: false)
      }
      if lighting.effect.usesBrightness {
        Picker("Brightness", selection: $lighting.brightness) {
          ForEach(UInt8(1)...UInt8(4), id: \.self) { Text("Level \($0)").tag($0) }
        }.pickerStyle(.segmented)
      }
      if lighting.effect.usesSpeed {
        Picker("Speed", selection: $lighting.speed) {
          Text("Slow").tag(UInt8(1))
          Text("Medium").tag(UInt8(2))
          Text("Fast").tag(UInt8(3))
        }.pickerStyle(.segmented)
      }
    }.formStyle(.grouped)
  }

  private var sensitivityPage: some View {
    VStack(alignment: .leading, spacing: 16) {
      pageTitle("Sensitivity", "Set DPI stages and the USB polling rate.")
      Picker("Polling rate", selection: $sensitivity.pollingRate) {
        ForEach(PollingRate.allCases) { Text("\($0.hertz) Hz").tag($0) }
      }.pickerStyle(.segmented)
      Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
        GridRow {
          Text("On")
          Text("Stage")
          Text("DPI")
          Text("Color")
          Text("Active")
        }.foregroundStyle(.secondary)
        ForEach(sensitivity.stages.indices, id: \.self) { index in
          GridRow {
            Toggle("Enabled", isOn: $sensitivity.stages[index].isEnabled).labelsHidden()
            Text("\(index + 1)")
            Stepper(value: $sensitivity.stages[index].dpi, in: 50...12_000, step: 50) {
              Text("\(sensitivity.stages[index].dpi)").frame(width: 54, alignment: .trailing)
            }
            ColorPicker(
              "Stage \(index + 1) color", selection: stageColor(index), supportsOpacity: false
            ).labelsHidden()
            Button {
              sensitivity.activeStage = index + 1
              sensitivity.stages[index].isEnabled = true
            } label: {
              Image(
                systemName: sensitivity.activeStage == index + 1
                  ? "largecircle.fill.circle" : "circle")
            }.buttonStyle(.plain).accessibilityLabel("Make stage \(index + 1) active")
          }
        }
      }
    }
  }

  private var buttonsPage: some View {
    VStack(alignment: .leading, spacing: 16) {
      pageTitle("Buttons", "Assign one action to each physical button.")
      Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 14) {
        ForEach(ButtonControl.allCases) { control in
          GridRow {
            Text(control.name).frame(width: 110, alignment: .leading)
            Picker(control.name, selection: $buttons.actions[control.rawValue]) {
              ForEach(ButtonAction.supported) { Text("\($0.category) — \($0.name)").tag($0) }
            }.labelsHidden().frame(maxWidth: 300)
          }
        }
      }
    }
  }

  private var advancedPage: some View {
    Form {
      pageTitle("Advanced", "These values were verified on this device firmware.")
      Picker("Debounce", selection: $advanced.debounceMilliseconds) {
        if advanced.debounceMilliseconds == 0 {
          Text("Factory default").tag(0).disabled(true)
        }
        ForEach([4, 6, 8, 10, 12, 14, 16], id: \.self) { Text("\($0) ms").tag($0) }
      }
      Picker("Lift-off distance", selection: $advanced.liftOffDistance) {
        ForEach(LiftOffDistance.allCases) { Text("\($0.millimeters) mm").tag($0) }
      }
    }.formStyle(.grouped)
  }

  private var devicePage: some View {
    VStack(alignment: .leading, spacing: 18) {
      pageTitle("Device", "Connection and firmware information.")
      LabeledContent("Connection", value: isConnected ? "Connected" : "Not connected")
      LabeledContent("Model", value: "Glorious Model O Eternal")
      LabeledContent("USB identifier", value: "3794:a000")
      LabeledContent("Firmware", value: firmware)
      Divider()
      Text("Factory reset").font(.headline)
      Text(
        "Hold the left, right, and scroll buttons for 5 seconds. The LEDs flash green. This removes custom settings from the mouse."
      )
      .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
    }
  }

  private var accessRequest: some View {
    VStack(alignment: .leading, spacing: 14) {
      Label("Input Monitoring is required", systemImage: "lock.shield").font(
        .title2.weight(.semibold))
      Text(
        "The mouse puts its configuration controls on a keyboard-class USB interface. macOS requires this permission."
      )
      Text("The app does not record or process keystrokes.").foregroundStyle(.secondary)
      if let permissionMessage {
        Text(permissionMessage).foregroundStyle(.secondary)
      }
      HStack {
        Button("Check access", action: checkAccess)
        Button("Open Input Monitoring", action: requestAccess).buttonStyle(.borderedProminent)
      }
    }.padding(32).frame(maxWidth: 520, alignment: .leading)
  }

  private func pageTitle(_ title: String, _ subtitle: String) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(title).font(.title2.weight(.semibold))
      Text(subtitle).foregroundStyle(.secondary)
    }.padding(.bottom, 8)
  }

  private var lightingColor: Binding<Color> {
    colorBinding(get: { lighting.color }, set: { lighting.color = $0 })
  }
  private func stageColor(_ index: Int) -> Binding<Color> {
    colorBinding(
      get: { sensitivity.stages[index].color }, set: { sensitivity.stages[index].color = $0 })
  }
  private func colorBinding(
    get: @escaping () -> ModelOEternalConfigurationCore.RGBColor,
    set: @escaping (ModelOEternalConfigurationCore.RGBColor) -> Void
  )
    -> Binding<Color>
  {
    Binding(
      get: {
        let value = get()
        return Color(
          red: Double(value.red) / 255, green: Double(value.green) / 255,
          blue: Double(value.blue) / 255)
      },
      set: { value in
        guard let color = NSColor(value).usingColorSpace(.sRGB) else { return }
        set(
          .init(
            red: .init(clamping: Int((color.redComponent * 255).rounded())),
            green: .init(clamping: Int((color.greenComponent * 255).rounded())),
            blue: .init(clamping: Int((color.blueComponent * 255).rounded()))))
      })
  }

  private func refresh() {
    isWorking = true
    defer { isWorking = false }
    do {
      let state = try mouse.readState()
      lighting = state.lighting
      sensitivity = state.sensitivity
      buttons = state.buttons
      advanced = state.advanced
      firmware = state.firmwareVersion
      isConnected = true
      message = "Model O Eternal connected."
    } catch {
      isConnected = false
      message = error.localizedDescription
    }
  }

  private func requestAccess() {
    _ = CGRequestListenEventAccess()
    checkAccess()
    guard !hasInputAccess else { return }
    permissionMessage =
      "Enable Model O Eternal Configuration in the list. Then return here and select Check access."
    guard
      let url = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")
    else { return }
    NSWorkspace.shared.open(url)
  }

  private func checkAccess() {
    hasInputAccess = CGPreflightListenEventAccess()
    if hasInputAccess {
      permissionMessage = nil
      refresh()
    }
  }

  private func apply() {
    isWorking = true
    defer { isWorking = false }
    do {
      switch selected ?? .lighting {
      case .lighting: try mouse.apply(lighting)
      case .sensitivity: try mouse.apply(sensitivity)
      case .buttons: try mouse.apply(buttons)
      case .advanced:
        let current = try mouse.readAdvanced()
        if current.debounceMilliseconds != advanced.debounceMilliseconds {
          try mouse.applyDebounce(milliseconds: advanced.debounceMilliseconds)
        }
        if current.liftOffDistance != advanced.liftOffDistance {
          try mouse.apply(advanced.liftOffDistance)
        }
      case .device: return
      }
      isConnected = true
      message = "\((selected ?? .lighting).rawValue) settings saved."
    } catch {
      message = error.localizedDescription
      isConnected = mouse.isConnected()
    }
  }
}
