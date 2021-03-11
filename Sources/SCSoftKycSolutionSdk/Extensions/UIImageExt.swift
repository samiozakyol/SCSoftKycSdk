//
//  UIImageExt.swift
//  CardScanner
//
//  Created by work on 5.03.2021.
//  Copyright © 2021 Hassan Shahbazi. All rights reserved.
//

import Foundation
import UIKit

public enum ImageFormat {
    case png
    case jpeg(CGFloat)
}

extension UIImage {
    public func toBase64(format: ImageFormat) -> String? {
        var imageData: Data?

        switch format {
        case .png:
            imageData = self.pngData()
        case .jpeg(let compression):
            imageData = self.jpegData(compressionQuality: compression)
        }

        return imageData?.base64EncodedString()
    }
}
