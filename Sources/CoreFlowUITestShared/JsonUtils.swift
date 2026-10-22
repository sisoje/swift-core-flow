import Foundation

package enum JsonUtils {
    package static func encode(_ value: some Encodable) -> String {
        String(decoding: try! JSONEncoder().encode(value), as: UTF8.self)
    }

    package static func decode<Value: Decodable>(_ string: String) -> Value {
        try! JSONDecoder().decode(Value.self, from: Data(string.utf8))
    }
}
