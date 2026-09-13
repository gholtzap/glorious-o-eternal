import AppKit
import CoreGraphics
import ModelOEternalConfigurationCore
import SwiftUI

struct ContentView: View {
  @State private var settings = LightingSettings(
    effect: .glorious,
    color: RGBColor(red: 124, green: 58, blue: 237),
    brightness: 4,
    speed: 2
  )
  @State private var selectedColor = Color(red: 124 / 255, green: 58 / 255, blue: 237 / 255)
  @State private var isConnected = false
  @State private var isWorking = false
  @State private var message = "Connect your Model O Eternal."
  @State private var hasInputAccess = CGPreflightListenEventAccess()
  @State private var permissionMessage: String?
  @State private var lastAppliedSettings: LightingSettings?
  @State private var applyTask: Task<Void, Never>?

  private let mouse = ModelOEternalDevice()

  var body: some View {
    VStack(alignment: .leading, spacing: 20) {
      header

      Divider()

      if hasInputAccess {
        controls
      } else {
        accessRequest
      }
    }
    .padding(24)
    .frame(width: 460)
    .onAppear {
      if hasInputAccess { refresh() }
    }
  }

  private var controls: some View {
    VStack(alignment: .leading, spacing: 20) {
      Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 14) {
        GridRow {
          Text("Effect")
          Picker("Effect", selection: $settings.effect) {
            ForEach(LightingEffect.allCases) { effect in
              Text(effect.name).tag(effect)
            }
          }
          .labelsHidden()
          .frame(width: 220)
        }

        if settings.effect.usesColor {
          GridRow {
            Text("Color")
            ColorPicker("Color", selection: $selectedColor, supportsOpacity: false)
              .labelsHidden()
          }
        }

        if settings.effect.usesBrightness {
          GridRow {
            Text("Brightness")
            Picker("Brightness", selection: $settings.brightness) {
              ForEach(UInt8(1)...UInt8(4), id: \.self) { level in
                Text("Level \(level)").tag(level)
              }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(width: 220)
          }
        }

        if settings.effect.usesSpeed {
          GridRow {
            Text("Speed")
            Picker("Speed", selection: $settings.speed) {
              Text("Slow").tag(UInt8(1))
              Text("Medium").tag(UInt8(2))
              Text("Fast").tag(UInt8(3))
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(width: 220)
          }
        }
      }
      .disabled(!isConnected || isWorking)
      .onChange(of: settings) { _, _ in scheduleApply() }
      .onChange(of: selectedColor) { _, _ in scheduleApply() }

      HStack {
        Text(message)
          .foregroundStyle(isConnected ? Color.secondary : Color.red)
          .lineLimit(2)

        Spacer()

        Button("Refresh", action: refresh)
          .disabled(isWorking)
      }
    }
    .onDisappear { applyTask?.cancel() }
  }

  private var accessRequest: some View {
    VStack(alignment: .leading, spacing: 14) {
      Label("Input Monitoring is required", systemImage: "lock.shield")
        .font(.headline)

      Text(
        "The mouse places its lighting controls on a keyboard-class USB interface. macOS requires this permission before an app can open that interface."
      )
      .fixedSize(horizontal: false, vertical: true)

      Text(
        "Model O Eternal Configuration does not record or process keystrokes. It reads and writes only the mouse configuration reports."
      )
      .foregroundStyle(.secondary)
      .fixedSize(horizontal: false, vertical: true)

      if let permissionMessage {
        Text(permissionMessage)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }

      HStack {
        Spacer()
        Button("Check access", action: checkAccess)
        Button("Continue", action: requestAccess)
          .buttonStyle(.borderedProminent)
      }
    }
  }

  private var header: some View {
    HStack(spacing: 14) {
      Image(systemName: "lightbulb.led.fill")
        .font(.system(size: 30))
        .foregroundStyle(isConnected ? Color.accentColor : .secondary)
        .accessibilityHidden(true)

      VStack(alignment: .leading, spacing: 3) {
        Text("Model O Eternal Configuration")
          .font(.title2.weight(.semibold))
        Text("Lighting control for Glorious Model O Eternal")
          .foregroundStyle(.secondary)
      }
    }
  }

  private func refresh() {
    isWorking = true
    defer { isWorking = false }

    do {
      settings = try mouse.readSettings()
      lastAppliedSettings = settings
      selectedColor = Color(
        red: Double(settings.color.red) / 255,
        green: Double(settings.color.green) / 255,
        blue: Double(settings.color.blue) / 255
      )
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
    if !hasInputAccess {
      permissionMessage =
        "Allow access in System Settings, then reopen Model O Eternal Configuration."
    }
  }

  private func checkAccess() {
    hasInputAccess = CGPreflightListenEventAccess()
    if hasInputAccess {
      permissionMessage = nil
      refresh()
    }
  }

  private func apply() {
    guard let color = NSColor(selectedColor).usingColorSpace(.sRGB) else {
      message = "The selected color could not be converted to sRGB."
      return
    }

    settings.color = RGBColor(
      red: UInt8(clamping: Int((color.redComponent * 255).rounded())),
      green: UInt8(clamping: Int((color.greenComponent * 255).rounded())),
      blue: UInt8(clamping: Int((color.blueComponent * 255).rounded()))
    )
    guard lastAppliedSettings?.hasSameEffectiveValues(as: settings) != true else { return }

    isWorking = true
    defer { isWorking = false }

    do {
      try mouse.apply(settings)
      lastAppliedSettings = settings
      isConnected = true
      message = "Lighting settings saved to the mouse."
    } catch {
      message = error.localizedDescription
      isConnected = mouse.isConnected()
    }
  }

  private func scheduleApply() {
    guard isConnected else { return }
    applyTask?.cancel()
    applyTask = Task { @MainActor in
      try? await Task.sleep(for: .milliseconds(250))
      guard !Task.isCancelled else { return }
      apply()
    }
  }
}
