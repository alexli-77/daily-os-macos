import XCTest
@testable import DailyOSClient
@testable import DailyOSCore

final class Decode: XCTestCase {
  func testRoutines() throws {
    let data = try Data(contentsOf: URL(fileURLWithPath: "/tmp/routines.json"))
    do {
      let r = try JSONDecoder().decode(RoutinesResponse.self, from: data)
      print("ROUTINES OK periods=\(r.periods.count)")
    } catch { print("ROUTINES FAIL \(error)") ; throw error }
  }
  func testSchedule() throws {
    let data = try Data(contentsOf: URL(fileURLWithPath: "/tmp/schedule.json"))
    do {
      _ = try JSONDecoder().decode(CycleScheduleResponse.self, from: data)
      print("SCHEDULE OK")
    } catch { print("SCHEDULE FAIL \(error)"); throw error }
  }
}
