import Foundation

func currentUnixTimeMs() -> Int {
  return Int(Date().timeIntervalSince1970 * 1000)
}
