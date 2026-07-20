//
//  StarkModels.swift
//  Shared telemetry vocabulary for the Stark HUD system.
//

import Foundation

// MARK: - Metric kinds

/// Every metric the system understands. The iPhone companion fills in whatever
/// HealthKit actually has; the HUD renders whatever arrives.
enum MetricKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case heartRate
    case restingHeartRate
    case heartRateVariability
    case bloodOxygen
    case respiratoryRate
    case vo2Max
    case steps
    case activeEnergy
    case exerciseMinutes
    case standHours
    case distanceWalkingRunning
    case flightsClimbed
    case sleepHours
    case mindfulMinutes
    case bodyMass
    case walkingSpeed

    var id: String { rawValue }

    /// Human name, as Health.app would say it.
    var displayName: String {
        switch self {
        case .heartRate: return "Heart Rate"
        case .restingHeartRate: return "Resting Heart Rate"
        case .heartRateVariability: return "Heart Rate Variability"
        case .bloodOxygen: return "Blood Oxygen"
        case .respiratoryRate: return "Respiratory Rate"
        case .vo2Max: return "VO₂ Max"
        case .steps: return "Steps"
        case .activeEnergy: return "Active Energy"
        case .exerciseMinutes: return "Exercise Minutes"
        case .standHours: return "Stand Hours"
        case .distanceWalkingRunning: return "Walking + Running"
        case .flightsClimbed: return "Flights Climbed"
        case .sleepHours: return "Sleep"
        case .mindfulMinutes: return "Mindful Minutes"
        case .bodyMass: return "Body Mass"
        case .walkingSpeed: return "Walking Speed"
        }
    }

    /// Workshop name, as JARVIS would say it.
    var starkLabel: String {
        switch self {
        case .heartRate: return "ARC PULSE"
        case .restingHeartRate: return "IDLE CORE FREQ"
        case .heartRateVariability: return "CORE STABILITY"
        case .bloodOxygen: return "O₂ SATURATION"
        case .respiratoryRate: return "INTAKE CYCLES"
        case .vo2Max: return "THRUST CAPACITY"
        case .steps: return "LOCOMOTION UNITS"
        case .activeEnergy: return "POWER DRAW"
        case .exerciseMinutes: return "COMBAT READINESS"
        case .standHours: return "UPRIGHT CYCLES"
        case .distanceWalkingRunning: return "GROUND TRAVERSED"
        case .flightsClimbed: return "ALTITUDE GAIN"
        case .sleepHours: return "RECHARGE CYCLE"
        case .mindfulMinutes: return "NEURAL CALIBRATION"
        case .bodyMass: return "CHASSIS MASS"
        case .walkingSpeed: return "CRUISE VELOCITY"
        }
    }

    var unitLabel: String {
        switch self {
        case .heartRate, .restingHeartRate: return "BPM"
        case .heartRateVariability: return "MS"
        case .bloodOxygen: return "%"
        case .respiratoryRate: return "BR/MIN"
        case .vo2Max: return "ML/KG·MIN"
        case .steps: return "STEPS"
        case .activeEnergy: return "KCAL"
        case .exerciseMinutes: return "MIN"
        case .standHours: return "HRS"
        case .distanceWalkingRunning: return "KM"
        case .flightsClimbed: return "FLIGHTS"
        case .sleepHours: return "HRS"
        case .mindfulMinutes: return "MIN"
        case .bodyMass: return "KG"
        case .walkingSpeed: return "KM/H"
        }
    }

    var symbolName: String {
        switch self {
        case .heartRate: return "heart.fill"
        case .restingHeartRate: return "heart.circle"
        case .heartRateVariability: return "waveform.path.ecg"
        case .bloodOxygen: return "lungs.fill"
        case .respiratoryRate: return "wind"
        case .vo2Max: return "gauge.with.dots.needle.67percent"
        case .steps: return "figure.walk"
        case .activeEnergy: return "flame.fill"
        case .exerciseMinutes: return "figure.run"
        case .standHours: return "figure.stand"
        case .distanceWalkingRunning: return "point.topleft.down.to.point.bottomright.curvepath.fill"
        case .flightsClimbed: return "figure.stairs"
        case .sleepHours: return "moon.zzz.fill"
        case .mindfulMinutes: return "brain.head.profile"
        case .bodyMass: return "scalemass.fill"
        case .walkingSpeed: return "speedometer"
        }
    }

    /// Digits after the decimal point when rendering a value.
    var displayPrecision: Int {
        switch self {
        case .heartRate, .restingHeartRate, .heartRateVariability, .respiratoryRate,
             .steps, .activeEnergy, .exerciseMinutes, .standHours, .flightsClimbed,
             .mindfulMinutes, .bloodOxygen:
            return 0
        case .distanceWalkingRunning, .sleepHours, .vo2Max, .bodyMass, .walkingSpeed:
            return 1
        }
    }

    /// Cumulative metrics reset daily (steps); discrete metrics are point-in-time (heart rate).
    var isCumulative: Bool {
        switch self {
        case .steps, .activeEnergy, .exerciseMinutes, .standHours,
             .distanceWalkingRunning, .flightsClimbed, .sleepHours, .mindfulMinutes:
            return true
        default:
            return false
        }
    }

    func formatted(_ value: Double) -> String {
        String(format: "%.\(displayPrecision)f", value)
    }
}

// MARK: - Samples & payload

struct MetricSample: Codable, Sendable, Identifiable, Equatable {
    var kind: MetricKind
    var value: Double
    var date: Date

    var id: String { kind.rawValue }
}

/// One telemetry frame sent from the iPhone to the Apple TV.
struct TelemetryPayload: Codable, Sendable {
    var samples: [MetricSample]
    /// Recent beats-per-minute readings, oldest first, for the EKG-style trace.
    var heartRateSeries: [Double]
    var sourceName: String
    var sentAt: Date

    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    func encoded() throws -> Data { try Self.encoder.encode(self) }

    static func decode(_ data: Data) throws -> TelemetryPayload {
        try decoder.decode(TelemetryPayload.self, from: data)
    }
}

// MARK: - Link constants

enum StarkLink {
    /// Multipeer Connectivity service type (max 15 chars, lowercase + hyphen).
    static let serviceType = "starkhud-link"
}
