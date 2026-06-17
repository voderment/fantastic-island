import Combine
import CoreLocation
import Foundation

struct HorizonWeatherSnapshot: Equatable {
    var temperatureCelsius: Double?
    var conditionSymbol: String
    var conditionText: String
    var locationLabel: String

    static let unavailable = HorizonWeatherSnapshot(
        temperatureCelsius: nil,
        conditionSymbol: "cloud",
        conditionText: "Weather unavailable",
        locationLabel: "Location"
    )
}

@MainActor
final class HorizonWeatherService: NSObject, ObservableObject {
    @Published private(set) var snapshot = HorizonWeatherSnapshot.unavailable
    @Published private(set) var authorizationStatus: CLAuthorizationStatus = .notDetermined

    private let locationManager = CLLocationManager()
    private var lastFetchAt = Date.distantPast
    private var isFetching = false

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyThreeKilometers
        authorizationStatus = locationManager.authorizationStatus
    }

    func refreshIfNeeded(force: Bool = false, requestAuthorizationIfNeeded: Bool = false) {
        let status = locationManager.authorizationStatus
        authorizationStatus = status

        switch status {
        case .notDetermined:
            if requestAuthorizationIfNeeded {
                locationManager.requestWhenInUseAuthorization()
            }
        case .authorizedAlways, .authorizedWhenInUse:
            guard force || Date().timeIntervalSince(lastFetchAt) > 900 else {
                return
            }

            locationManager.requestLocation()
        default:
            snapshot = HorizonWeatherSnapshot(
                temperatureCelsius: nil,
                conditionSymbol: "location.slash",
                conditionText: "Location access needed",
                locationLabel: "Weather"
            )
        }
    }

    private func fetchForecast(latitude: Double, longitude: Double) async {
        guard !isFetching else {
            return
        }

        isFetching = true
        defer { isFetching = false }

        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")
        components?.queryItems = [
            URLQueryItem(name: "latitude", value: String(latitude)),
            URLQueryItem(name: "longitude", value: String(longitude)),
            URLQueryItem(name: "current", value: "temperature_2m,weather_code"),
            URLQueryItem(name: "timezone", value: "auto"),
        ]

        guard let url = components?.url else {
            return
        }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, (200 ... 299).contains(http.statusCode) else {
                return
            }

            let decoded = try JSONDecoder().decode(OpenMeteoResponse.self, from: data)
            let weatherCode = decoded.current.weatherCode
            let mapped = Self.mapWeatherCode(weatherCode)

            snapshot = HorizonWeatherSnapshot(
                temperatureCelsius: decoded.current.temperature2M,
                conditionSymbol: mapped.symbol,
                conditionText: mapped.text,
                locationLabel: "Local"
            )
            lastFetchAt = .now
        } catch {
            snapshot = HorizonWeatherSnapshot(
                temperatureCelsius: nil,
                conditionSymbol: "cloud.slash",
                conditionText: "Weather fetch failed",
                locationLabel: "Weather"
            )
        }
    }
}

extension HorizonWeatherService: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            authorizationStatus = manager.authorizationStatus
            refreshIfNeeded(force: true)
        }
    }

    nonisolated func locationManager(_: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else {
            return
        }

        Task { @MainActor in
            await fetchForecast(
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude
            )
        }
    }

    nonisolated func locationManager(_: CLLocationManager, didFailWithError _: Error) {
        Task { @MainActor in
            snapshot = HorizonWeatherSnapshot(
                temperatureCelsius: nil,
                conditionSymbol: "exclamationmark.cloud",
                conditionText: "Could not resolve location",
                locationLabel: "Weather"
            )
        }
    }
}

private extension HorizonWeatherService {
    struct OpenMeteoResponse: Decodable {
        struct Current: Decodable {
            let temperature2M: Double
            let weatherCode: Int

            enum CodingKeys: String, CodingKey {
                case temperature2M = "temperature_2m"
                case weatherCode = "weather_code"
            }
        }

        let current: Current
    }

    static func mapWeatherCode(_ code: Int) -> (symbol: String, text: String) {
        switch code {
        case 0:
            return ("sun.max.fill", "Clear")
        case 1, 2, 3:
            return ("cloud.sun.fill", "Partly cloudy")
        case 45, 48:
            return ("cloud.fog.fill", "Fog")
        case 51, 53, 55, 56, 57:
            return ("cloud.drizzle.fill", "Drizzle")
        case 61, 63, 65, 66, 67, 80, 81, 82:
            return ("cloud.rain.fill", "Rain")
        case 71, 73, 75, 77, 85, 86:
            return ("cloud.snow.fill", "Snow")
        case 95, 96, 99:
            return ("cloud.bolt.rain.fill", "Thunderstorm")
        default:
            return ("cloud.fill", "Cloudy")
        }
    }
}
