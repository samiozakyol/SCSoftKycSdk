import Foundation
import UIKit

public class SdkModel {
    var mrzInfo : QKMRZScanResult?
    
    var idFrontImage : UIImage?
    var idBackImage : UIImage?
    var selfieImage : UIImage?
    
    var autoCropped_idFrontImage : UIImage?
    var autoCropped_idBackImage : UIImage?
    var autoCropped_selfieImage : UIImage?
    
    var nfcData : IDCardUtil?
}
