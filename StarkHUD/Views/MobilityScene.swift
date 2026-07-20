//
//  MobilityScene.swift
//  StarkHUD — CHASSIS MOBILITY: the iPhone's passive gait lab presented
//  as servo calibration diagnostics. NOMINAL / DRIFT / FAULT.
//

import SwiftUI

// MARK: - Status model

enum ServoStatus {
    case nominal, drift, fault, unknown

    var color: Color {
        switch self {
        case .nominal: return Theme.arc
        case .drift: return Theme.gold
        case .fault: return Theme.hotRod
        case .unknown: return Theme.arcDim
        }
    }

    var label: String {
        switch self {
        case .nominal: return "NOMINAL"
        case .drift: return "DRIFT DETECTED"
        case .fault: return "FAULT"
        case .unknown: return "NO DATA"
        }
    }
}

/// One calibration readout: value, healthy-range normalization, verdict.
private struct ServoSpec: Identifiable {
    let id: String
    let starkLabel: String
    let realName: String
    let symbol: String
    let value: Double?
    let unit: String
    let formatted: String
    /// 0…1 gauge fill (1 = ideal end of the healthy range).
    let norm: Double
    let status: ServoStatus
}

private func makeSpecs(_ m: MobilityReport) -> [ServoSpec] {
    func spec(_ id: String, _ stark: String, _ real: String, _ symbol: String,
              _ value: Double?, _ unit: String, _ precision: Int,
              norm: (Double) -> Double, status: (Double) -> ServoStatus) -> ServoSpec {
        ServoSpec(id: id, starkLabel: stark, realName: real, symbol: symbol,
                  value: value, unit: unit,
                  formatted: value.map { String(format: "%.\(precision)f", $0) } ?? "——",
                  norm: value.map(norm) ?? 0,
                  status: value.map(status) ?? .unknown)
    }

    return [
        spec("asym", "SERVO SYMMETRY", "WALKING ASYMMETRY", "arrow.left.arrow.right",
             m.asymmetry, "%", 1,
             norm: { max(1 - $0 / 15, 0) },
             status: { $0 <= 5 ? .nominal : ($0 <= 10 ? .drift : .fault) }),
        spec("ds", "GROUND CONTACT", "DOUBLE SUPPORT TIME", "shoeprints.fill",
             m.doubleSupport, "%", 1,
             norm: { max(1 - max(($0 - 20) / 20, 0), 0.05) },
             status: { $0 <= 30 ? .nominal : ($0 <= 36 ? .drift : .fault) }),
        spec("stride", "STRIDE CALIBRATION", "STEP LENGTH", "ruler",
             m.stepLengthMeters, "M", 2,
             norm: { min($0 / 0.9, 1) },
             status: { $0 >= 0.6 ? .nominal : ($0 >= 0.45 ? .drift : .fault) }),
        spec("ascent", "ASCENT THRUST", "STAIR ASCENT SPEED", "arrow.up.right",
             m.stairAscentSpeed, "M/S", 2,
             norm: { min($0 / 0.9, 1) },
             status: { $0 >= 0.5 ? .nominal : ($0 >= 0.35 ? .drift : .fault) }),
        spec("descent", "DESCENT CONTROL", "STAIR DESCENT SPEED", "arrow.down.right",
             m.stairDescentSpeed, "M/S", 2,
             norm: { min($0 / 1.0, 1) },
             status: { $0 >= 0.55 ? .nominal : ($0 >= 0.4 ? .drift : .fault) }),
        spec("endurance", "ENDURANCE RATING", "SIX-MINUTE WALK", "gauge.with.needle",
             m.sixMinuteWalkMeters, "M", 0,
             norm: { min($0 / 650, 1) },
             status: { $0 >= 500 ? .nominal : ($0 >= 400 ? .drift : .fault) }),
    ]
}

// MARK: - Scene

struct MobilityScene: View {
    @Environment(MetricStore.self) private var store

    var body: some View {
        if let mobility = store.mobility, mobility.hasAnyData {
            HStack(spacing: 26) {
                GyroStabilityDial(steadiness: mobility.steadiness)
                    .frame(width: 470)

                VStack(spacing: 22) {
                    HStack {
                        Text("SERVO CALIBRATION — PASSIVE CAPTURE VIA POCKET CHASSIS")
                            .hudLabelStyle(size: 16, color: Theme.arcDim)
                        Spacer()
                    }
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 22), count: 3),
                              spacing: 22) {
                        ForEach(makeSpecs(mobility)) { spec in
                            ServoTile(spec: spec)
                        }
                    }
                }
            }
            .frame(maxHeight: .infinity)
        } else {
            HoloPanel(accent: Theme.gold) {
                VStack(spacing: 14) {
                    Image(systemName: "figure.walk.motion")
                        .font(.system(size: 52))
                        .foregroundStyle(Theme.gold)
                    Text("GAIT SENSORS OFFLINE")
                        .hudLabelStyle(size: 24, color: Theme.gold)
                    Text("CARRY THE PHONE WHILE WALKING TO CALIBRATE CHASSIS TELEMETRY")
                        .font(Theme.labelFont(16))
                        .kerning(1.5)
                        .foregroundStyle(Theme.arcDim)
                }
                .padding(30)
            }
            .frame(maxHeight: .infinity)
        }
    }
}

// MARK: - Steadiness dial

private struct GyroStabilityDial: View {
    var steadiness: Double?

    private var status: ServoStatus {
        guard let s = steadiness else { return .unknown }
        return s >= 50 ? .nominal : (s >= 25 ? .drift : .fault)
    }

    var body: some View {
        HoloPanel(accent: status.color) {
            VStack(spacing: 20) {
                Text("GYRO STABILITY")
                    .hudLabelStyle(size: 21, color: status.color)
                Text("WALKING STEADINESS — FALL-RISK COMPOSITE")
                    .font(Theme.labelFont(13))
                    .kerning(1.5)
                    .foregroundStyle(Theme.arcDim)

                ZStack {
                    Circle()
                        .stroke(status.color.opacity(0.14), lineWidth: 22)
                    Circle()
                        .trim(from: 0, to: (steadiness ?? 0) / 100)
                        .stroke(
                            AngularGradient(colors: [status.color.opacity(0.5), status.color],
                                            center: .center),
                            style: StrokeStyle(lineWidth: 22, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .shadow(color: status.color.opacity(0.8), radius: 16)

                    VStack(spacing: 6) {
                        Text(steadiness.map { "\(Int($0))%" } ?? "——")
                            .font(Theme.hudFont(64, weight: .bold))
                            .foregroundStyle(.white)
                        Text(status.label)
                            .hudLabelStyle(size: 17, color: status.color)
                    }
                }
                .frame(width: 280, height: 280)

                Text(statusFooter)
                    .font(Theme.labelFont(14))
                    .kerning(1.2)
                    .foregroundStyle(Theme.arcDim)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var statusFooter: String {
        switch status {
        case .nominal: return "GYROSCOPIC SYSTEMS STABLE — FLIGHT CLEARANCE GRANTED"
        case .drift: return "STABILITY DEGRADED — RECOMMEND CALIBRATION ROUTINE"
        case .fault: return "STABILITY CRITICAL — GROUND THE SUIT"
        case .unknown: return "AWAITING SENSOR SWEEP"
        }
    }
}

// MARK: - Servo tile

private struct ServoTile: View {
    fileprivate var spec: ServoSpec

    var body: some View {
        HoloPanel(accent: spec.status.color) {
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 8) {
                    Image(systemName: spec.symbol)
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(spec.status.color)
                    Text(spec.starkLabel)
                        .hudLabelStyle(size: 15, color: spec.status.color)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }

                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(spec.formatted)
                        .font(Theme.hudFont(38, weight: .bold))
                        .foregroundStyle(.white)
                    Text(spec.unit)
                        .font(Theme.hudFont(14))
                        .foregroundStyle(spec.status.color.opacity(0.8))
                }
                .lineLimit(1)
                .fixedSize()

                ZStack(alignment: .leading) {
                    Capsule().fill(spec.status.color.opacity(0.15))
                    Capsule()
                        .fill(spec.status.color.opacity(0.9))
                        .frame(width: max(220 * spec.norm, 6))
                        .shadow(color: spec.status.color.opacity(0.8), radius: 5)
                }
                .frame(width: 220, height: 8)

                HStack {
                    Text(spec.realName)
                        .font(Theme.labelFont(11))
                        .kerning(1)
                        .foregroundStyle(Theme.arcDim)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Spacer()
                    Text(spec.status.label)
                        .font(Theme.hudFont(12, weight: .bold))
                        .foregroundStyle(spec.status.color)
                        .lineLimit(1)
                        .fixedSize()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
