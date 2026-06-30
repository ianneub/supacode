import Testing

@testable import supacode

struct DiffLineCountFormatTests {
  @Test func abbreviatesLargeCounts() {
    #expect(DiffLineCountFormat.abbreviated(0) == "0")
    #expect(DiffLineCountFormat.abbreviated(42) == "42")
    #expect(DiffLineCountFormat.abbreviated(999) == "999")
    #expect(DiffLineCountFormat.abbreviated(1000) == "1k")
    #expect(DiffLineCountFormat.abbreviated(1100) == "1.1k")
    #expect(DiffLineCountFormat.abbreviated(1500) == "1.5k")
    #expect(DiffLineCountFormat.abbreviated(9999) == "10k")
    #expect(DiffLineCountFormat.abbreviated(12345) == "12k")
  }
}
