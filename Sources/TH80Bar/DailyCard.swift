import EventKit
import Foundation

struct DailyCardSettings: Codable, Equatable {
    var enabled = false
    var hour = 8
    var city = ""
    var showWeather = true
    var showCalendar = false
    var lastSent: String?   // "yyyy-MM-dd"
}

/// Busca clima (Open-Meteo, sem chave) e o próximo compromisso do dia (Calendário).
enum DailyCardService {
    static func todayKey(_ d: Date = Date()) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: d)
        return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }

    static func gather(_ s: DailyCardSettings) async -> ScreenArt.DayInfo {
        var info = ScreenArt.DayInfo()
        if s.showWeather, !s.city.trimmingCharacters(in: .whitespaces).isEmpty {
            await fillWeather(&info, city: s.city)
        }
        if s.showCalendar { info.event = await nextEvent() }
        return info
    }

    private static func fillWeather(_ info: inout ScreenArt.DayInfo, city: String) async {
        struct Geo: Decodable { struct R: Decodable { let latitude: Double; let longitude: Double; let name: String }; let results: [R]? }
        struct Forecast: Decodable {
            struct Cur: Decodable { let temperature_2m: Double; let weather_code: Int }
            struct Daily: Decodable { let temperature_2m_max: [Double]; let temperature_2m_min: [Double] }
            let current: Cur; let daily: Daily
        }
        var gc = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")!
        gc.queryItems = [.init(name: "name", value: city), .init(name: "count", value: "1"), .init(name: "language", value: "pt")]
        guard let (gd, _) = try? await URLSession.shared.data(from: gc.url!),
              let place = (try? JSONDecoder().decode(Geo.self, from: gd))?.results?.first else { return }
        var fc = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        fc.queryItems = [
            .init(name: "latitude", value: "\(place.latitude)"), .init(name: "longitude", value: "\(place.longitude)"),
            .init(name: "current", value: "temperature_2m,weather_code"),
            .init(name: "daily", value: "temperature_2m_max,temperature_2m_min"),
            .init(name: "timezone", value: "auto"), .init(name: "forecast_days", value: "1"),
        ]
        guard let (fd, _) = try? await URLSession.shared.data(from: fc.url!),
              let f = try? JSONDecoder().decode(Forecast.self, from: fd) else { return }
        info.city = place.name
        info.temperature = Int(f.current.temperature_2m.rounded())
        info.maxTemp = f.daily.temperature_2m_max.first.map { Int($0.rounded()) }
        info.minTemp = f.daily.temperature_2m_min.first.map { Int($0.rounded()) }
        (info.weatherSymbol, info.weatherText) = describe(f.current.weather_code)
    }

    /// Códigos WMO → símbolo e texto.
    static func describe(_ code: Int) -> (String, String) {
        switch code {
        case 0: ("sun.max.fill", "Céu limpo")
        case 1, 2: ("cloud.sun.fill", "Parcialmente nublado")
        case 3: ("cloud.fill", "Nublado")
        case 45, 48: ("cloud.fog.fill", "Neblina")
        case 51...57: ("cloud.drizzle.fill", "Garoa")
        case 61...67, 80...82: ("cloud.rain.fill", "Chuva")
        case 71...77, 85, 86: ("cloud.snow.fill", "Neve")
        case 95...99: ("cloud.bolt.rain.fill", "Tempestade")
        default: ("cloud.sun.fill", "")
        }
    }

    private static func nextEvent() async -> String? {
        let store = EKEventStore()
        guard (try? await store.requestFullAccessToEvents()) == true else { return "Sem acesso ao Calendário" }
        let now = Date()
        let end = Calendar.current.startOfDay(for: now).addingTimeInterval(86_400)
        let events = store.events(matching: store.predicateForEvents(withStart: now, end: end, calendars: nil))
            .filter { !$0.isAllDay }.sorted { $0.startDate < $1.startDate }
        guard let e = events.first else { return "Sem compromissos hoje" }
        let time = e.startDate.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
        return "\(time) · \(e.title ?? "Compromisso")"
    }
}
