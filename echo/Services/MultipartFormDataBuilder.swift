import Foundation

class MultipartFormDataBuilder {
    private let boundary: String
    private var body = Data()
    
    init() {
        self.boundary = UUID().uuidString
    }
    
    var contentType: String {
        return "multipart/form-data; boundary=\(boundary)"
    }
    
    func addTextField(name: String, value: String) {
        appendBoundary()
        appendDisposition(name: name)
        appendValue(value)
    }
    
    func addFileField(name: String, filename: String, contentType: String, data: Data) {
        appendBoundary()
        appendFileDisposition(name: name, filename: filename)
        appendContentType(contentType)
        appendValue(data)
    }
    
    func build() -> Data {
        appendFinalBoundary()
        return body
    }
    
    private func appendBoundary() {
        appendString("--\(boundary)\r\n")
    }
    
    private func appendDisposition(name: String) {
        appendString("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
    }
    
    private func appendFileDisposition(name: String, filename: String) {
        appendString("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n")
    }
    
    private func appendContentType(_ contentType: String) {
        appendString("Content-Type: \(contentType)\r\n\r\n")
    }
    
    private func appendValue(_ value: String) {
        appendString("\(value)\r\n")
    }
    
    private func appendValue(_ data: Data) {
        body.append(data)
        appendString("\r\n")
    }
    
    private func appendFinalBoundary() {
        appendString("--\(boundary)--\r\n")
    }
    
    private func appendString(_ string: String) {
        if let data = string.data(using: .utf8) {
            body.append(data)
        }
    }
}