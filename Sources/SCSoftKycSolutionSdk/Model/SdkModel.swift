import Foundation
import UIKit

public class SdkModel {
    var mrzInfo : QKMRZScanResult?
    
    var idFrontImage : UIImage?
    var idBackImage : UIImage?
    var selfieImage : UIImage?
    var mrzImage : UIImage?
    
    var autoCropped_idFrontImage : UIImage?
    var autoCropped_idBackImage : UIImage?
    var autoCropped_selfieImage : UIImage?
    
    var base64_idFrontImage : String?
    var base64_idBackImage : String?
    var base64_selfieImage : String?
    var base64_autoCropped_idFrontImage : String?
    var base64_autoCropped_idBackImage : String?
    var base64_autoCropped_selfieImage : String?
    
    var nfcData : IDCardUtil?
}
