import CoreLocation
import MapKit
import UIKit

enum ImageCompressor {
    /// 長辺 maxDimension に縮小して JPEG 化。描き直すので EXIF（撮影位置など）も落ちる。
    static func jpegData(from data: Data, maxDimension: CGFloat = 1200, quality: CGFloat = 0.7) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let size = image.size
        let scale = min(1, maxDimension / max(size.width, size.height))
        let target = CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let resized = UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
        return resized.jpegData(compressionQuality: quality)
    }
}

extension MKCoordinateRegion {
    static let tokyo = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 35.6812, longitude: 139.7671),
        span: MKCoordinateSpan(latitudeDelta: 0.35, longitudeDelta: 0.35)
    )
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
