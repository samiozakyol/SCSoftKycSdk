import Foundation
import UIKit
import AVFoundation
import Vision
import SwiftyTesseract
import QKMRZParser
import NFCPassportReader
import JitsiMeetSDK
import CoreNFC

public enum ViewType {
    case idPhoto
    case selfie
    case nfcRead
    case jitsi
}

public protocol SCSoftKycViewDelegate: class {
    func didDetectSdkDataBeforeJitsi(_ kycView: SCSoftKycView, didDetect sdkModel: SdkModel)
    
    func didCaptureIdFrontPhoto(_ kycView : SCSoftKycView, image : UIImage , imageBase64 : String, cropImage : UIImage , cropImageBase64 : String)
    
    func didCaptureIdBackPhoto(_ kycView : SCSoftKycView, image : UIImage , imageBase64 : String, cropImage : UIImage , cropImageBase64 : String)
    
    func didCaptureSelfiePhoto(_ kycView : SCSoftKycView, image : UIImage , imageBase64 : String, cropImage : UIImage , cropImageBase64 : String)
    
    func didReadNfc(_ kycView : SCSoftKycView , didRead passportModel : NFCPassportModel)
    
    func didClose(_ kycView: SCSoftKycView, didDetect sdkModel: SdkModel)
}

@IBDesignable
public class SCSoftKycView: UIView {
    
    // Public variables
    
    public var forceNfc = false
    //public var jitsiMoreButtonIsHidden = true
    
    public weak var delegate: SCSoftKycViewDelegate?
    //public var _viewTypes = [ViewType]()
    var viewTypeLinkedList = LinkedListViewType<ViewType>()
    var _viewTypes = [ViewType]()
    public var viewTypes:[ViewType] {
     get {
       return _viewTypes
     }
     set (newVal) {
        _viewTypes = newVal
        viewTypeLinkedList = LinkedListViewType(array: newVal)
        if _viewTypes.count > 0 {
            selectedViewType = _viewTypes[0]
            showViewType(viewType: selectedViewType)
        }
     }
    }
    private var selectedViewType = ViewType.idPhoto
    
    //Video Capture
    private var bufferSize: CGSize = .zero
    private let videoDataOutputQueue = DispatchQueue(label: "videoDataOutputQueue", qos: .userInitiated, attributes: [], autoreleaseFrequency: .workItem)
    private var captureSession = AVCaptureSession()
    private var videoDataOutput = AVCaptureVideoDataOutput()
    private var videoPreviewLayer = AVCaptureVideoPreviewLayer()
    
    //View outlets
    private let takePhotoButton = CircleButton()
    private let cutoutView = QKCutoutView()
    private let cutoutSelfieView = OvalOverlayView()
    private var idPhotoLabel = StatementLabel()
    private let flashButton = ToggleButton()
    private var nfcReadLabel = StatementLabel()
    private var jitsiLabel = StatementLabel()
    private let jitsiButton = UIButton()
    private var informationLabel = StatementLabel()
    private let nfcReadButton = UIButton()
    private let informationNextButton = UIButton()
    private let closeButton = UIButton()
    //private var jitsiMoreButton : ExpandingMenuButton?
    private var flipImageView = UIImageView()
    //private var imgView: UIImageView!
    
    private var sdkModel = SdkModel()
    private var isFinish = false
    private var isFront = true
    private var checkFace = false
    private var checkMrz = false
    private var checkRectangle = false
    
    private var backCamera : AVCaptureDevice?
    private var frontCamera : AVCaptureDevice?
    private var backInput : AVCaptureInput!
    private var frontInput : AVCaptureInput!
    
    fileprivate var observer: NSKeyValueObservation?
    @objc fileprivate dynamic var isScanning = false
    fileprivate var isScanningPaused = false
    
    //Capture result
    private var capturedImage: UIImage!
    private var capturedFace: UIImage!
    private var capturedMrz: UIImage!
    
    fileprivate let tesseract = SwiftyTesseract(language: .custom("ocrb"), dataSource: Bundle(for: SCSoftKycView.self), engineMode: .tesseractOnly)
    //fileprivate let tesseract = SwiftyTesseract(language: .custom("ocrb"), dataSource: Bundle(for: SCSoftKycView.self), engineMode: .tesseractOnly)
    fileprivate let mrzParser = QKMRZParser(ocrCorrection: true)
    
    fileprivate var inputCIImage: CIImage!
    fileprivate var inputCGImage: CGImage!
    
    private var refreshTimer: Timer?
    
    // Jitsi config
    fileprivate var inJitsi : Bool = false
    fileprivate var jitsiMeetView = JitsiMeetView()
    private var didConferenceTerminated:((_ data: [AnyHashable : Any]?) -> Void)?
    
    //private var cameraColor = UIColor(red: 33.0 / 255.0, green: 209.0 / 255.0, blue: 144.0 / 255.0, alpha: 1.0)
    private var cameraColor = UIColor(red: 27.0 / 255.0, green: 170.0 / 255.0, blue: 194.0 / 255.0, alpha: 1.0)
    
    private var hasNfc = false
    private let idCardReader = PassportReader()
    
    private var noCameraText = ""
    
    fileprivate var cutoutRect: CGRect? {
        return cutoutView.cutoutRect
    }
    
    fileprivate var cutoutSelfieRect: CGRect? {
        return cutoutSelfieView.overlayFrame
    }
    
    private lazy var facesRequest: VNDetectFaceRectanglesRequest = {
        return VNDetectFaceRectanglesRequest(completionHandler: self.handleFacesRequest)
    }()
    
    private lazy var mrzRequest: VNDetectTextRectanglesRequest = {
        return VNDetectTextRectanglesRequest(completionHandler: self.handleMrzRequest)
    }()
    
    private lazy var rectanglesRequest: VNDetectRectanglesRequest = {
        let rectanglesRequest = VNDetectRectanglesRequest(completionHandler: self.handleRectanglesRequest)
        rectanglesRequest.minimumAspectRatio = VNAspectRatio(1.3)
        rectanglesRequest.maximumAspectRatio = VNAspectRatio(1.6)
        rectanglesRequest.minimumSize = Float(0.5)
        rectanglesRequest.maximumObservations = 1
        return rectanglesRequest
    }()
    
    // MARK: Initializers
    override public init(frame: CGRect) {
        super.init(frame: frame)
        initialize()
    }
    
    required public init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        initialize()
    }
    
    // MARK: Init methods
    fileprivate func initialize() {
        FilterVendor.registerFilters()
        if NFCReaderSession.readingAvailable{
            hasNfc = true
        }
        setupAndStartCaptureSession()
        setViewStyle()
        initiateScreen()
        
        refreshTimer = Timer.scheduledTimer(timeInterval: 2, target: self, selector: #selector(runTimedCode), userInfo: nil, repeats: true)
        addAppObservers()
    }
    
    // MARK: UIApplication Observers
    @objc fileprivate func appWillEnterForeground() {
        if isScanningPaused {
            isScanningPaused = false
            startScanning()
        }
    }
    
    @objc fileprivate func appDidEnterBackground() {
        if isScanning {
            isScanningPaused = true
            stopScanning()
        }
    }
    
    override public func layoutSubviews() {
        super.layoutSubviews()
        videoPreviewLayer.frame = bounds
    }
    
    // MARK: Scanning
    public func startScanning() {
        guard !captureSession.inputs.isEmpty else {
            return
        }
        captureSession.startRunning()
    }
    
    public func stopScanning() {
        captureSession.stopRunning()
    }
    
    fileprivate func setViewStyle() {
        backgroundColor = .clear
    }
    
    @objc func runTimedCode(){
        self.checkFace = false
        //self.checkMrz = false
        self.checkRectangle = false
        updateScanArea()
    }
    
    private func initiateScreen(){
        DispatchQueue.main.async {
            self.initiateStatement()
            self.initiateFlashButton()
            self.initiateTakePhotoButton()
            self.initiateNfcReadLabel(forceText: "")
            self.initiateNfcReadButton()
            self.initiateInformationNextButton()
            //self.initiateJitsiMoreButton()
            self.initiateCloseButton()
            self.initiateFlipImageView()
            self.initiateJitsiLabel()
            self.initiateJitsiButton()
            self.viewChange()
        }
    }
    
    private func updateScanArea() {
        var found = false
        
        if selectedViewType == .idPhoto {
            if checkRectangle && ((isFront && checkFace) || (!isFront && checkMrz && !checkFace)){
                found = true
            }
            
            DispatchQueue.main.async {
                (self.cutoutView.layer.sublayers?.first as? CAShapeLayer)?.strokeColor = (found) ? self.cameraColor.cgColor : #colorLiteral(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0)
                self.cutoutView.layoutIfNeeded()
                
                let btnImage = (found) ? "camera_button_on" : "camera_button_off"
                
                self.takePhotoButton.setBackgroundImage(self.getMyImage(named: btnImage), for: .normal)
                self.takePhotoButton.isEnabled = found
            }
        }
        else if selectedViewType == .selfie{
            if checkFace{
                found = true
            }
            
            DispatchQueue.main.async {
                (self.cutoutSelfieView.layer.sublayers?.first as? CAShapeLayer)?.strokeColor = (found) ? self.cameraColor.cgColor : #colorLiteral(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0)
                self.cutoutSelfieView.layoutIfNeeded()
                
                let btnImage = (found) ? "camera_button_on" : "camera_button_off"
                
                self.takePhotoButton.setBackgroundImage(self.getMyImage(named: btnImage), for: .normal)
                self.takePhotoButton.isEnabled = found
            }
        }
    }
    
    func getMyImage(named : String) -> UIImage? {
        let bundle = Bundle(for: SCSoftKycView.self)
        return UIImage(named: named, in: bundle, compatibleWith: nil)
    }
    
    // MARK: Document Image from Photo cropping
    fileprivate func cutoutRect(for cgImage: CGImage) -> CGRect {
        let imageWidth = CGFloat(cgImage.width)
        let imageHeight = CGFloat(cgImage.height)
        let rect = videoPreviewLayer.metadataOutputRectConverted(fromLayerRect: cutoutRect!)
        let videoOrientation = videoPreviewLayer.connection!.videoOrientation
        
        if videoOrientation == .portrait || videoOrientation == .portraitUpsideDown {
            return CGRect(x: (rect.minY * imageWidth), y: (rect.minX * imageHeight), width: (rect.height * imageWidth), height: (rect.width * imageHeight))
        }
        else {
            return CGRect(x: (rect.minX * imageWidth), y: (rect.minY * imageHeight), width: (rect.width * imageWidth), height: (rect.height * imageHeight))
        }
    }
    
    fileprivate func documentImage(from cgImage: CGImage) -> CGImage {
        let croppingRect = cutoutRect(for: cgImage)
        return cgImage.cropping(to: croppingRect) ?? cgImage
    }
    
    fileprivate func enlargedDocumentImage(from cgImage: CGImage) -> UIImage {
        var croppingRect = cutoutRect(for: cgImage)
        let margin = (0.05 * croppingRect.height) // 5% of the height
        croppingRect = CGRect(x: (croppingRect.minX - margin), y: (croppingRect.minY - margin), width: croppingRect.width + (margin * 2), height: croppingRect.height + (margin * 2))
        return UIImage(cgImage: cgImage.cropping(to: croppingRect)!)
    }
    
    fileprivate func selfieImage(from cgImage: CGImage) -> CGImage {
        let croppingRect = cutoutSelfieRect(for: cgImage)
        return cgImage.cropping(to: croppingRect) ?? cgImage
    }
    
    // MARK: Document Image from Photo cropping
    fileprivate func cutoutSelfieRect(for cgImage: CGImage) -> CGRect {
        let imageWidth = CGFloat(cgImage.width)
        let imageHeight = CGFloat(cgImage.height)
        let rect = videoPreviewLayer.metadataOutputRectConverted(fromLayerRect: cutoutSelfieRect!)
        let videoOrientation = videoPreviewLayer.connection!.videoOrientation
        
        if videoOrientation == .portrait || videoOrientation == .portraitUpsideDown {
            return CGRect(x: (rect.minY * imageWidth), y: (rect.minX * imageHeight), width: (rect.height * imageWidth), height: (rect.width * imageHeight))
        }
        else {
            return CGRect(x: (rect.minX * imageWidth), y: (rect.minY * imageHeight), width: (rect.width * imageWidth), height: (rect.height * imageHeight))
        }
    }
    
    fileprivate func enlargedSelfieImage(from cgImage: CGImage) -> UIImage {
        var croppingRect = cutoutSelfieRect(for: cgImage)
        let margin = (0.05 * croppingRect.height) // 5% of the height
        croppingRect = CGRect(x: (croppingRect.minX - margin), y: (croppingRect.minY - margin), width: croppingRect.width + (margin * 2), height: croppingRect.height + (margin * 2))
        return UIImage(cgImage: cgImage.cropping(to: croppingRect)!)
    }
    
    fileprivate func addAppObservers() {
        NotificationCenter.default.addObserver(self, selector: #selector(appDidEnterBackground), name: UIApplication.didEnterBackgroundNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(appWillEnterForeground), name: UIApplication.willEnterForegroundNotification, object: nil)
    }
    
    //MARK:- Camera Setup
    private func setupAndStartCaptureSession(){
        //get back camera
        if let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) {
            backCamera = device
        } else {
            //handle this appropriately for production purposes
            noCameraText = "no back camera"
            return
        }
        
        //get front camera
        if let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front) {
            frontCamera = device
        } else {
            noCameraText = "no front camera"
            return
        }
        
        //DispatchQueue.global(qos: .userInitiated).async{
        //init session
        self.captureSession = AVCaptureSession()
        //start configuration
        self.captureSession.beginConfiguration()
        
        //session specific configuration
        if self.captureSession.canSetSessionPreset(.photo) {
            self.captureSession.sessionPreset = .photo
        }
        self.captureSession.automaticallyConfiguresCaptureDeviceForWideColor = true
        
        observer = captureSession.observe(\.isRunning, options: [.new]) { [unowned self] (model, change) in
            // CaptureSession is started from the global queue (background). Change the `isScanning` on the main
            // queue to avoid triggering the change handler also from the global queue as it may affect the UI.
            DispatchQueue.main.async {
                [weak self] in self?.isScanning = change.newValue!
            }
        }
        
        //setup inputs
        self.setupInputs()
        
        //DispatchQueue.main.async {
        //setup preview layer
        self.setupPreviewLayer()
        //}
        
        //setup output
        self.setupOutput()
        
        //commit configuration
        self.captureSession.commitConfiguration()
        //start running it
        self.captureSession.startRunning()
        //}
    }
    
    private func setupInputs(){
        
        //now we need to create an input objects from our devices
        guard let bInput = try? AVCaptureDeviceInput(device: backCamera!) else {
            noCameraText = "could not create input device from back camera"
            return
        }
        backInput = bInput
        if !captureSession.canAddInput(backInput) {
            noCameraText = "could not add back camera input to capture session"
            return
        }
        
        guard let fInput = try? AVCaptureDeviceInput(device: frontCamera!) else {
            noCameraText = "could not create input device from front camera"
            return
        }
        frontInput = fInput
        if !captureSession.canAddInput(frontInput) {
            noCameraText = "could not add front camera input to capture session"
            return
        }
        
        //connect back camera input to session
        captureSession.addInput(backInput)
    }
    
    private func setupOutput(){
        videoDataOutput = AVCaptureVideoDataOutput()
        let videoQueue = DispatchQueue(label: "videoQueue", qos: .userInteractive)
        videoDataOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA] as [String : Any]
        videoDataOutput.alwaysDiscardsLateVideoFrames = true
        videoDataOutput.setSampleBufferDelegate(self, queue: videoQueue)
        
        if captureSession.canAddOutput(videoDataOutput) {
            captureSession.addOutput(videoDataOutput)
        } else {
            noCameraText = "could not add video output"
            return
        }
        
        videoDataOutput.connections.first?.videoOrientation = .portrait
    }
    
    private func setupPreviewLayer(){
        videoPreviewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        videoPreviewLayer.videoGravity = .resizeAspectFill
        videoPreviewLayer.frame = bounds
    }
    
     public func showJitsiView(){
        // for save data
        delegate?.didDetectSdkDataBeforeJitsi(self, didDetect: sdkModel)
        
        selectedViewType = .jitsi
        DispatchQueue.main.async {
        self.viewChange()
        }
    }
    
    public func showNfcView(){
        selectedViewType = .nfcRead
        DispatchQueue.main.async {
            self.viewChange()
        }
    }
    
    public func showSelfieView(){
        /*if inJitsi{
            let seconds = 0.5
            DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
                self.showSelfieView()
            }
            return
        }*/
        selectedViewType = .selfie
        
        if noCameraText.isEmpty{
        captureSession.beginConfiguration()
        if let inputs = captureSession.inputs as? [AVCaptureDeviceInput] {
            for input in inputs {
                captureSession.removeInput(input)
            }
        }
        if captureSession.inputs.isEmpty {
            self.captureSession.addInput(frontInput)
        }
        
        //deal with the connection again for portrait mode
        videoDataOutput.connections.first?.videoOrientation = .portrait
        //mirror the video stream for front camera
        videoDataOutput.connections.first?.isVideoMirrored = true
        //commit config
        captureSession.commitConfiguration()
        }
        DispatchQueue.main.async {
            self.viewChange()
        }
    }
    
    public func showIdPhotoView(){
        /*if inJitsi{
            let seconds = 1.5
            DispatchQueue.main.asyncAfter(deadline: .now() + seconds) {
                self.showIdPhotoView()
            }
            return
        }*/
        
        selectedViewType = .idPhoto
        
        if noCameraText.isEmpty{
        captureSession.beginConfiguration()
        
        if let inputs = captureSession.inputs as? [AVCaptureDeviceInput] {
            for input in inputs {
                captureSession.removeInput(input)
            }
        }
        if captureSession.inputs.isEmpty {
            self.captureSession.addInput(backInput)
        }

        //deal with the connection again for portrait mode
        videoDataOutput.connections.first?.videoOrientation = .portrait
        //mirror the video stream for front camera
        videoDataOutput.connections.first?.isVideoMirrored = false
        //commit config
        captureSession.commitConfiguration()
        }
        DispatchQueue.main.async {
            self.viewChange()
        }
    }
    
    fileprivate func viewChange(){
        // REMOVE VIEW
        //idPhoto
        add_removeInformationView(isAdd: false)
        add_removeFlipImageView(isAdd: false)
        add_removeCloseButton(isAdd: false)
        add_removeCutoutView(isAdd: false)
        add_removeIdPhotoLabel(isAdd: false)
        add_removeFlashButton(isAdd: false)
        
        //share camera view
        add_removeTakePhotoButton(isAdd: false)
        
        //selfie
        add_removeCutoutSelfieView(isAdd: false)
        
        //nfc
        add_removeNfcViews(isAdd: false)
        videoPreviewLayer.removeFromSuperlayer()
        
        //jitsi
        add_removeJitsiView(isAdd: false)
        add_removeJitsiInfoViews(isAdd: false)
        //add_removeJitsiMoreButton(isAdd: false)
        //jitsiMoreButton?.removeFromSuperview()
        
        if !noCameraText.isEmpty && frontCamera == nil && selectedViewType == .selfie {
            initiateInformationLabel(text: "Cihazınızda ön kamera bulunmamaktadır. Devam butonuna basarak sürece devam edebilirsiniz.")
            add_removeInformationView(isAdd: true)
            add_removeCloseButton(isAdd: true)
            return
        }
        
        if !noCameraText.isEmpty && backCamera == nil && selectedViewType == .idPhoto {
            initiateInformationLabel(text: "Cihazınızda arka kamera bulunmamaktadır. Devam butonuna basarak sürece devam edebilirsiniz.")
            add_removeInformationView(isAdd: true)
            add_removeCloseButton(isAdd: true)
            return
        }
        
        if forceNfc && !hasNfc {
            initiateInformationLabel(text: "Cihazınızda NFC desteği bulunmamaktadır. Bu kontrol zorunlu tutulduğu için ilerleme yapılamamaktadır.")
            add_removeInformationView(isAdd: true)
            add_removeCloseButton(isAdd: true)
            return
        }
        
        if viewTypes.count == 0 {
            initiateInformationLabel(text: "Sdk içerisine işlem listesi boş gönderilmiştir.")
            add_removeInformationView(isAdd: true)
            add_removeCloseButton(isAdd: true)
            return
        }
        if isFinish {
            initiateInformationLabel(text: "Süreç tamamlanmıştır.")
            add_removeInformationView(isAdd: true)
            add_removeCloseButton(isAdd: true)
            return
        }
        
        // ADD VIEW
        //share camera view
        if selectedViewType == .idPhoto || selectedViewType == .selfie {
            layer.addSublayer(videoPreviewLayer)
        }
        
        if selectedViewType == .idPhoto {
            add_removeCutoutView(isAdd: true)
            add_removeTakePhotoButton(isAdd: true)
            add_removeFlashButton(isAdd: true)
            add_removeIdPhotoLabel(isAdd: true)
            add_removeFlipImageView(isAdd: true)
        }
        else if selectedViewType == .selfie {
            add_removeCutoutSelfieView(isAdd: true)
            add_removeTakePhotoButton(isAdd: true)
        }
        else if selectedViewType == .nfcRead {
            add_removeNfcViews(isAdd: true)
        }
        else if selectedViewType == .jitsi {
            add_removeJitsiInfoViews(isAdd: true)
            //if !jitsiMoreButtonIsHidden {
                //addSubview(jitsiMoreButton!)
            //}
        }
        add_removeCloseButton(isAdd: true)
    }
    
    public func setJitsiConference(url : String, room : String, token : String){
        if selectedViewType == .jitsi {
            add_removeJitsiInfoViews(isAdd: false)
            add_removeJitsiView(isAdd: true)
            openJitsiMeet(url: url, room: room, token: token)
        }
    }
    
    private func getNextViewType(){
        if viewTypeLinkedList.isEmpty || viewTypeLinkedList.head == nil {
            return
        }
        var newViewType = selectedViewType
        var isNext = false
        var tempValue = viewTypeLinkedList.head
        while tempValue != nil {
            if isNext && tempValue != nil{
                newViewType = tempValue!.value
                break
            }
            
            if tempValue?.value == selectedViewType {
                isNext = true
            }
            if tempValue?.next == nil {
                isFinish = true
                DispatchQueue.main.async {
                    self.viewChange()
                }
                break
            }
            else{
                tempValue = tempValue?.next!
            }
        }
        if newViewType != selectedViewType{
            showViewType(viewType: newViewType)
        }
    }
    
    private func showViewType(viewType : ViewType){
            if viewType == .idPhoto {
                showIdPhotoView()
            }
            else if viewType == .selfie {
                showSelfieView()
            }
            else if viewType == .nfcRead {
                showNfcView()
            }
            else if viewType == .jitsi {
                showJitsiView()
            }
    }
    
    @objc private func closeButtonInput(){
        self.delegate?.didClose(self, didDetect: sdkModel)
    }
    
    //button onclick
    @objc private func analyzeCard() {
        takePhotoButton.setBackgroundImage(self.getMyImage(named: "camera_button_off"), for: .normal)
        takePhotoButton.setImage(self.getMyImage(named: "loading_card"), for: .normal)
        takePhotoButton.rotateButton()
        
        if selectedViewType == .idPhoto {
            if isFront{
                self.flipImageView.alpha = 1
                let opt : UIView.AnimationOptions = [.curveLinear, .autoreverse]
                UIView.animate(withDuration: 1.7, delay: 0.4, options: opt, animations:
                                {
                                    self.flipImageView.transform = CGAffineTransform(scaleX: -1, y: 1)
                                },
                               completion: {_ in
                                self.flipImageView.alpha = 0
                               })
                idPhotoLabel.shape("T.C Kimlik Kartınızın arka yüzünü yukarıda belirtilen alan içerisine yerleştirerek fotoğraf çekme butonuna basınız.", font: UIFont.boldSystemFont(ofSize: 18))
                sdkModel.idFrontImage = UIImage(cgImage: self.inputCGImage)
                sdkModel.autoCropped_idFrontImage = self.capturedImage
                sdkModel.base64_idFrontImage =  sdkModel.idFrontImage?.toBase64(format: .png)
                sdkModel.base64_autoCropped_idFrontImage = sdkModel.autoCropped_idFrontImage?.toBase64(format: .png)
                isFront = false
                //self.delegate?.didDetectSdkData(self, didDetect: sdkModel)
                self.delegate?.didCaptureIdFrontPhoto(self, image: sdkModel.idFrontImage!, imageBase64: sdkModel.base64_idFrontImage!, cropImage: sdkModel.autoCropped_idFrontImage!, cropImageBase64: sdkModel.base64_autoCropped_idFrontImage!)
            }
            else if !isFront{
                idPhotoLabel.shape("T.C Kimlik Kartınızın ön yüzünü yukarıda belirtilen alan içerisine yerleştirerek fotoğraf çekme butonuna basınız.", font: UIFont.boldSystemFont(ofSize: 18))
                isFront = true
                sdkModel.idBackImage = UIImage(cgImage: self.inputCGImage)
                sdkModel.autoCropped_idBackImage = self.capturedImage
                sdkModel.base64_idBackImage =  sdkModel.idBackImage?.toBase64(format: .png)
                sdkModel.base64_autoCropped_idBackImage = sdkModel.autoCropped_idBackImage?.toBase64(format: .png)
                //self.delegate?.didDetectSdkData(self, didDetect: sdkModel)
                self.delegate?.didCaptureIdBackPhoto(self, image: sdkModel.idBackImage!, imageBase64: sdkModel.base64_idBackImage!, cropImage: sdkModel.autoCropped_idBackImage!, cropImageBase64: sdkModel.base64_autoCropped_idBackImage!)
                getNextViewType()
            }
        }
        else if selectedViewType == .selfie {
            sdkModel.selfieImage = UIImage(cgImage: self.inputCGImage)
            sdkModel.autoCropped_selfieImage = self.capturedFace
            sdkModel.base64_selfieImage =  sdkModel.selfieImage?.toBase64(format: .png)
            sdkModel.base64_autoCropped_selfieImage = sdkModel.autoCropped_selfieImage?.toBase64(format: .png)
            //self.delegate?.didDetectSdkData(self, didDetect: sdkModel)
            self.delegate?.didCaptureSelfiePhoto(self, image: sdkModel.selfieImage!, imageBase64: sdkModel.base64_selfieImage!, cropImage: sdkModel.autoCropped_selfieImage!, cropImageBase64: sdkModel.base64_autoCropped_selfieImage!)
            getNextViewType()
        }
    }
    
    @objc private func flashState(){
        let avDevice = AVCaptureDevice.default(for: AVMediaType.video)
        if ((avDevice?.hasTorch) != nil) {
            do {
                _ = try avDevice!.lockForConfiguration()
            } catch {
                print("aaaa")
            }
            
            if avDevice!.isTorchActive {
                avDevice!.torchMode = AVCaptureDevice.TorchMode.off
            } else {
                do {
                    _ = try avDevice!.setTorchModeOn(level: 1.0)
                } catch {
                    print("bbb")
                }
            }
            avDevice!.unlockForConfiguration()
        }
    }
    
    @objc private func informationNextButtonInput(){
        getNextViewType()
        return
    }
    
    @objc private func nfcReadInput(){
        if !hasNfc {
            getNextViewType()
            return
        }
        
        if sdkModel.mrzInfo != nil {
            let documentNumber = sdkModel.mrzInfo!.documentNumber
            let birthDate = sdkModel.mrzInfo!.birthDate!
            let expiryDate = sdkModel.mrzInfo!.expiryDate!
            
            let idCardModel = IDCardModel(documentNumber: documentNumber, birthDate: birthDate, expiryDate: expiryDate)
            readCard(idCardModel)
        }else {
            initiateNfcReadLabel(forceText: "Kimlik mrz bilgisi bulunamamıştır. Nfc okuması yapılabilmesi için öncelikle kimlik bilgilerinin sistem tarafından kaydedilmesi gerekmektedir.")
        }
    }
}

extension SCSoftKycView{
    
    fileprivate func add_removeNfcViews(isAdd : Bool){
        if isAdd {
            addSubview(nfcReadLabel)
            addSubview(nfcReadButton)
            
            nfcReadLabel.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                nfcReadLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
                nfcReadLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10)
            ])
            nfcReadLabel.centerXAnchor.constraint(equalTo: centerXAnchor).isActive = true
            nfcReadLabel.centerYAnchor.constraint(equalTo: centerYAnchor).isActive = true
            
            nfcReadButton.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                nfcReadButton.heightAnchor.constraint(equalToConstant: 50),
                nfcReadButton.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -30),
                nfcReadButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 30),
                nfcReadButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -30)
            ])
        }
        else{
            nfcReadLabel.removeFromSuperview()
            nfcReadButton.removeFromSuperview()
        }
    }
    
    fileprivate func add_removeJitsiInfoViews(isAdd : Bool){
        if isAdd {
            addSubview(jitsiLabel)
            addSubview(jitsiButton)
            
            jitsiLabel.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                jitsiLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
                jitsiLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10)
            ])
            jitsiLabel.centerXAnchor.constraint(equalTo: centerXAnchor).isActive = true
            jitsiLabel.centerYAnchor.constraint(equalTo: centerYAnchor).isActive = true
            
            jitsiButton.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                jitsiButton.heightAnchor.constraint(equalToConstant: 50),
                jitsiButton.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -30),
                jitsiButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 30),
                jitsiButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -30)
            ])
        }
        else{
            jitsiLabel.removeFromSuperview()
            jitsiButton.removeFromSuperview()
        }
    }
    
    fileprivate func add_removeInformationView(isAdd : Bool){
        if isAdd {
            addSubview(informationLabel)
            addSubview(informationNextButton)
            
            informationLabel.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                informationLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
                informationLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10)
            ])
            informationLabel.centerXAnchor.constraint(equalTo: centerXAnchor).isActive = true
            informationLabel.centerYAnchor.constraint(equalTo: centerYAnchor).isActive = true
    
            informationNextButton.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                informationNextButton.heightAnchor.constraint(equalToConstant: 50),
                informationNextButton.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -30),
                informationNextButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 30),
                informationNextButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -30)
            ])
            
        }
        else{
            informationLabel.removeFromSuperview()
            informationNextButton.removeFromSuperview()
        }
    }
    
    fileprivate func add_removeIdPhotoLabel(isAdd : Bool){
        if isAdd {
            addSubview(idPhotoLabel)
            idPhotoLabel.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                idPhotoLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
                idPhotoLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
                idPhotoLabel.bottomAnchor.constraint(equalTo: takePhotoButton.topAnchor, constant: -30),
                idPhotoLabel.centerXAnchor.constraint(equalTo: centerXAnchor)
            ])
        }
        else{
            idPhotoLabel.removeFromSuperview()
        }
    }
    
    
    /*fileprivate func add_removeJitsiMoreButton(isAdd : Bool){
        if isAdd {
            addSubview(jitsiMoreButton)
            jitsiMoreButton.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                jitsiMoreButton.heightAnchor.constraint(equalToConstant: 36),
                jitsiMoreButton.widthAnchor.constraint(equalToConstant: 36),
                jitsiMoreButton.topAnchor.constraint(equalTo: topAnchor, constant: 30),
                jitsiMoreButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 30)
            ])
        }
        else{
            jitsiMoreButton.removeFromSuperview()
        }
    }*/
    
    fileprivate func add_removeFlashButton(isAdd : Bool){
        if isAdd {
            addSubview(flashButton)
            flashButton.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                flashButton.heightAnchor.constraint(equalToConstant: 24),
                flashButton.widthAnchor.constraint(equalToConstant: 24),
                flashButton.centerYAnchor.constraint(equalTo: takePhotoButton.centerYAnchor),
                flashButton.leadingAnchor.constraint(equalTo: takePhotoButton.trailingAnchor, constant: 30)
            ])
        }
        else{
            flashButton.removeFromSuperview()
        }
    }
    
    fileprivate func add_removeJitsiView(isAdd : Bool){
        if isAdd {
            addSubview(jitsiMeetView)
            jitsiMeetView.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                jitsiMeetView.topAnchor.constraint(equalTo: topAnchor),
                jitsiMeetView.bottomAnchor.constraint(equalTo: bottomAnchor),
                jitsiMeetView.leftAnchor.constraint(equalTo: leftAnchor),
                //takePhotoButton.heightAnchor.constraint(equalToConstant: 100),
                //takePhotoButton.widthAnchor.constraint(equalToConstant: 100)
                jitsiMeetView.rightAnchor.constraint(equalTo: rightAnchor)
            ])
        }
        else{
            jitsiMeetView.removeFromSuperview()
        }
    }
    
    fileprivate func add_removeTakePhotoButton(isAdd : Bool){
        if isAdd {
            addSubview(takePhotoButton)
            takePhotoButton.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                takePhotoButton.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -30),
                takePhotoButton.centerXAnchor.constraint(equalTo: centerXAnchor),
                takePhotoButton.heightAnchor.constraint(equalToConstant: 70),
                takePhotoButton.widthAnchor.constraint(equalToConstant: 70)
            ])
        }
        else{
            takePhotoButton.removeFromSuperview()
        }
    }
    
    fileprivate func add_removeCloseButton(isAdd : Bool){
        if isAdd {
            addSubview(closeButton)
            closeButton.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                closeButton.topAnchor.constraint(equalTo: topAnchor,constant: 20),
                //closeButton.bottomAnchor.constraint(equalTo: bottomAnchor),
                //closeButton.leftAnchor.constraint(equalTo: leftAnchor),
                closeButton.heightAnchor.constraint(equalToConstant: 24),
                closeButton.widthAnchor.constraint(equalToConstant: 24),
                closeButton.trailingAnchor.constraint(equalTo: trailingAnchor,constant: -20)
            ])
        }
        else{
            closeButton.removeFromSuperview()
        }
    }
    
    
    fileprivate func add_removeCutoutView(isAdd : Bool){
        if isAdd {
            cutoutView.translatesAutoresizingMaskIntoConstraints = false
            addSubview(cutoutView)
            NSLayoutConstraint.activate([
                cutoutView.topAnchor.constraint(equalTo: topAnchor),
                cutoutView.bottomAnchor.constraint(equalTo: bottomAnchor),
                cutoutView.leftAnchor.constraint(equalTo: leftAnchor),
                cutoutView.rightAnchor.constraint(equalTo: rightAnchor)
            ])
        }
        else{
            cutoutView.removeFromSuperview()
        }
    }
    
    fileprivate func add_removeFlipImageView(isAdd : Bool){
        if isAdd {
            flipImageView.translatesAutoresizingMaskIntoConstraints = false
            addSubview(flipImageView)
            NSLayoutConstraint.activate([
                flipImageView.centerXAnchor.constraint(equalTo: centerXAnchor),
                flipImageView.centerYAnchor.constraint(equalTo: centerYAnchor),
                flipImageView.widthAnchor.constraint(equalToConstant: 80),
                flipImageView.heightAnchor.constraint(equalToConstant: 80)
            ])
        }
        else{
            flipImageView.removeFromSuperview()
        }
    }
    
    fileprivate func add_removeCutoutSelfieView(isAdd : Bool){
        if isAdd {
            cutoutSelfieView.translatesAutoresizingMaskIntoConstraints = false
            addSubview(cutoutSelfieView)
            NSLayoutConstraint.activate([
                cutoutSelfieView.topAnchor.constraint(equalTo: topAnchor),
                cutoutSelfieView.bottomAnchor.constraint(equalTo: bottomAnchor),
                cutoutSelfieView.leftAnchor.constraint(equalTo: leftAnchor),
                cutoutSelfieView.rightAnchor.constraint(equalTo: rightAnchor)
            ])
        }
        else{
            cutoutSelfieView.removeFromSuperview()
        }
    }
    
    private func initiateInformationNextButton() {
        let text = "Devam"
        informationNextButton.setTitle(text, for: .normal)
        informationNextButton.setTitleColor(.white, for: .normal)
        informationNextButton.backgroundColor = cameraColor
        informationNextButton.titleLabel?.font = UIFont.systemFont(ofSize: 17.0, weight: .semibold)
        informationNextButton.addTarget(self, action: #selector(self.informationNextButtonInput), for:.touchUpInside)
        informationNextButton.layer.cornerRadius = 8
        informationNextButton.layer.masksToBounds = true
        //informationNextButton.layoutIfNeeded()
    }
    
    fileprivate func initiateInformationLabel(text : String) {
        informationLabel.numberOfLines = 0
        informationLabel.shape(text, font: UIFont.boldSystemFont(ofSize: 15))
    }
    
    fileprivate func initiateJitsiLabel() {
        jitsiLabel.numberOfLines = 0
        let text = "Birazdan müşteri temsilcisine bağlanacaksınız. \nLütfen bekleyiniz."
        jitsiLabel.shape(text, font: UIFont.boldSystemFont(ofSize: 15))
    }
    
    private func initiateJitsiButton() {
        let text = "İptal Et"
        jitsiButton.setTitle(text, for: .normal)
        jitsiButton.setTitleColor(.white, for: .normal)
        jitsiButton.backgroundColor = cameraColor
        jitsiButton.titleLabel?.font = UIFont.systemFont(ofSize: 17.0, weight: .semibold)
        jitsiButton.addTarget(self, action: #selector(self.closeButtonInput), for:.touchUpInside)
        jitsiButton.layer.cornerRadius = 8
        jitsiButton.layer.masksToBounds = true
        //jitsiButton.layoutIfNeeded()
    }
    
    fileprivate func initiateNfcReadLabel(forceText : String) {
        nfcReadLabel.numberOfLines = 0
        var text = "T.C. Kimlik kartınızı telefonun arka kısmına yaklaştırın ve Tara butonuna basın."
        if !hasNfc {
            text = "Cihazınızda Nfc desteği bulunmamaktadır. Devam butonuna basarak sürece devam edebilirsiniz."
        }
        if !forceText.isEmpty {
            text = forceText
        }
        nfcReadLabel.shape(text, font: UIFont.boldSystemFont(ofSize: 15))
    }
    
    private func initiateNfcReadButton() {
        var text = "Tara"
        if !hasNfc {
            text = "Devam"
        }
        nfcReadButton.setTitle(text, for: .normal)
        nfcReadButton.setTitleColor(.white, for: .normal)
        nfcReadButton.backgroundColor = cameraColor
        nfcReadButton.titleLabel?.font = UIFont.systemFont(ofSize: 17.0, weight: .semibold)
        nfcReadButton.addTarget(self, action: #selector(self.nfcReadInput), for:.touchUpInside)
        nfcReadButton.layer.cornerRadius = 8
        nfcReadButton.layer.masksToBounds = true
        //nfcReadButton.layoutIfNeeded()
    }
    
    private func initiateFlipImageView() {
        flipImageView.image = self.getMyImage(named: "flip_h")
        flipImageView.alpha = 0
    }
    
    private func initiateCloseButton() {
        closeButton.setBackgroundImage(getMyImage(named: "cancel"), for: .normal)
        closeButton.setImage(nil, for: .normal)
        closeButton.addTarget(self, action: #selector(self.closeButtonInput), for:.touchUpInside)
    }
    
    /*private func initiateJitsiMoreButton() {
        let menuButtonSize: CGSize = CGSize(width: 64.0, height: 64.0)
        let rect = CGRect(x: 10, y: 10, width: 64, height: 64)
        jitsiMoreButton = ExpandingMenuButton(frame: rect, image: getMyImage(named: "chooser-button-tab")!, rotatedImage: getMyImage(named: "chooser-button-tab-highlighted")!)
        jitsiMoreButton!.expandingDirection = .bottom
        jitsiMoreButton!.menuTitleDirection = .right
        //menuButton.menuButtonHapticStyle = .heavy
        //menuButton.playSound = true
        //menuButton.menuItemsHapticStyle = .heavy
        
        //menuButton.center = CGPoint(x: 32.0, y: bounds.height - 72.0)
        //addSubview(jitsiMoreButton!)
        
        let item1 = ExpandingMenuItem(size: menuButtonSize, title: "Kimlik Fotoğrafı Çek", image: self.getMyImage(named: "view_id")!, highlightedImage: self.getMyImage(named: "view_id")!, backgroundImage: self.getMyImage(named: "chooser-moment-button"), backgroundHighlightedImage: self.getMyImage(named: "chooser-moment-button-highlighted")) { () -> Void in
            // Do some action
            self.jitsiMeetView.leave()
            self.viewTypes = [.idPhoto,.jitsi]
            //self.showIdPhotoView()
        }
        
        let item2 = ExpandingMenuItem(size: menuButtonSize, title: "Selfie Çek", image: self.getMyImage(named: "view_selfie")!, highlightedImage: self.getMyImage(named: "view_selfie")!, backgroundImage: self.getMyImage(named: "chooser-moment-button"), backgroundHighlightedImage: self.getMyImage(named: "chooser-moment-button-highlighted")) { () -> Void in
            // Do some action
            self.jitsiMeetView.leave()
            self.viewTypes = [.selfie,.jitsi]
            //self.showSelfieView()
        }
        
        let item3 = ExpandingMenuItem(size: menuButtonSize, title: "Nfc Tara", image: self.getMyImage(named: "view_nfc")!, highlightedImage: self.getMyImage(named: "view_nfc")!, backgroundImage: self.getMyImage(named: "chooser-moment-button"), backgroundHighlightedImage: self.getMyImage(named: "chooser-moment-button-highlighted")) { () -> Void in
            // Do some action
            self.jitsiMeetView.leave()
            self.viewTypes = [.nfcRead,.jitsi]
            //self.showNfcView()
        }
        jitsiMoreButton!.addMenuItems([item1, item2, item3])
    }*/
    
    private func initiateStatement() {
        idPhotoLabel.numberOfLines = 0
        idPhotoLabel.shape("T.C Kimlik Kartınızın ön yüzünü yukarıda belirtilen alan içerisine yerleştiriniz.", font: UIFont.boldSystemFont(ofSize: 18))
    }
    
    private func initiateFlashButton(){
        flashButton.isOn = false
        flashButton.offImage = self.getMyImage(named: "flash-off")
        flashButton.onImage = self.getMyImage(named: "flash")
        flashButton.addTarget(self, action: #selector(self.flashState), for:.touchUpInside)
    }
    
    private func initiateTakePhotoButton() {
        takePhotoButton.setBackgroundImage(self.getMyImage(named: "camera_button_off"), for: .normal)
        takePhotoButton.setImage(nil, for: .normal)
        takePhotoButton.addTarget(self, action: #selector(self.analyzeCard), for:.touchUpInside)
        takePhotoButton.shapeButton()
        takePhotoButton.isEnabled = false
    }
    
    // idPhoto view
    private func getStatementArea() -> CGRect {
        let scanArea = getTakePhotoButtonArea()
        let width: CGFloat = frame.width - 16
        let height: CGFloat = 24
        let size = CGSize(width: width, height: height)
        
        let y = scanArea.origin.y - scanArea.height - 28
        let titlePoint: CGPoint = CGPoint(x: frame.width/2 - width/2, y: y)
        
        return CGRect(origin: titlePoint, size: size)
    }
    
    private func getFlashButtonArea() -> CGRect {
        let height: CGFloat = 24.0
        let width: CGFloat = 24.0
        let point = CGPoint(x: frame.width - width - 20 , y: 75)
        let size = CGSize(width: width, height: height)
        
        return CGRect(origin: point, size: size)
    }
    
    private func getTakePhotoButtonArea() -> CGRect {
        let height: CGFloat = 70.0
        let width: CGFloat = 70.0
        let point = CGPoint(x: frame.width/2 - width/2, y: frame.height - height - 36.0)
        let size = CGSize(width: width, height: height)
        
        return CGRect(origin: point, size: size)
    }
    
    private func getSwitchCameraButtonArea() -> CGRect {
        let height: CGFloat = 24.0
        let width: CGFloat = 24.0
        
        let point = CGPoint(x: frame.width - width - 20 , y: 115)
        let size = CGSize(width: width, height: height)
        
        return CGRect(origin: point, size: size)
    }
    
    private func getUIImage(from ciImage: CIImage) -> UIImage {
        let context = CIContext()
        guard let cgImage = context.createCGImage(ciImage, from: ciImage.extent) else { return UIImage() }
        return UIImage(cgImage: cgImage)
    }
    
    fileprivate func performVisionRequest(image: CGImage, orientation: CGImagePropertyOrientation) {
        
        // Fetch desired requests based on switch status.
        let requests = createVisionRequests()
        // Create a request handler.
        let imageRequestHandler = VNImageRequestHandler(cgImage: image,
                                                        orientation: orientation,
                                                        options: [:])
        try? imageRequestHandler.perform(requests)
        // Send the requests to the request handler.
        /*DispatchQueue.global(qos: .userInitiated).async {
         do {
         try imageRequestHandler.perform(requests)
         } catch let error as NSError {
         print("Failed to perform image request: \(error)")
         //self.presentAlert("Image Request Failed", error: error)
         return
         }
         }*/
    }
    
    /// - Tag: CreateRequests
    fileprivate func createVisionRequests() -> [VNRequest] {
        
        // Create an array to collect all desired requests.
        var requests: [VNRequest] = []
        if selectedViewType == .nfcRead {
            return requests
        }
        
        if selectedViewType == .idPhoto {
            requests.append(self.rectanglesRequest)
            if hasNfc{
                requests.append(self.mrzRequest)
            }
            else { checkMrz = true }
        }
        requests.append(self.facesRequest)
        
        // Return grouped requests as a single array.
        return requests
    }
    
    //fileprivate
    private func handleRectanglesRequest(request: VNRequest, error: Error?) {
        guard let observations = request.results as? [VNRectangleObservation] else { return }
        guard let detectedRectangle = observations.first else { return }
        if inputCIImage == nil || inputCGImage == nil {return}
        
        let imageSize = self.inputCIImage.extent.size
        
        //let boundingBox = detectedRectangle.boundingBox.scaled(to: imageSize)
        let topLeft = detectedRectangle.topLeft.scaled(to: imageSize)
        let topRight = detectedRectangle.topRight.scaled(to: imageSize)
        let bottomLeft = detectedRectangle.bottomLeft.scaled(to: imageSize)
        let bottomRight = detectedRectangle.bottomRight.scaled(to: imageSize)
        
        let correctedImage = self.inputCIImage
            // .cropped(to: boundingBox)
            .applyingFilter("CIPerspectiveCorrection", parameters: [
                "inputTopLeft": CIVector(cgPoint: topLeft),
                "inputTopRight": CIVector(cgPoint: topRight),
                "inputBottomLeft": CIVector(cgPoint: bottomLeft),
                "inputBottomRight": CIVector(cgPoint: bottomRight)
            ])
        
        let cgImage = CIContext.shared.createCGImage(correctedImage, from: correctedImage.extent)
        //correctedImage = correctedImage.cropped(to: boundingBox).oriented(forExifOrientation: Int32(CGImagePropertyOrientation.up.rawValue))
        //correctedImage = correctedImage.oriented(forExifOrientation: Int32(CGImagePropertyOrientation.up.rawValue))
        DispatchQueue.main.async {
            if cgImage != nil{
                self.didDetectCardImage(cgImage!)
            }
        }
    }
    
    fileprivate func handleFacesRequest(request: VNRequest, error: Error?) {
        guard let observations = request.results as? [VNFaceObservation] else { return }
        guard let detectedFace = observations.first else { return }
        if inputCIImage == nil || inputCGImage == nil {return}
        
        let imageSize = self.inputCIImage.extent.size
        
        let boundingBox = detectedFace.boundingBox.scaled(to: imageSize)
        let correctedImage = self.inputCIImage.cropped(to: boundingBox).oriented(forExifOrientation: Int32(CGImagePropertyOrientation.up.rawValue))
        DispatchQueue.main.async {
            self.didDetectFaceImage(correctedImage, at: boundingBox)
        }
    }
    
    fileprivate func handleMrzRequest(request: VNRequest, error: Error?) {
        guard let observations = request.results as? [VNTextObservation] else { return }
        if inputCIImage == nil || inputCGImage == nil {return}
        //guard let detectedRectangle = observations.first else { return }
        //let imageSize = inputImage.extent.size
        //let boundingBox = detectedRectangle.boundingBox.scaled(to: imageSize)
        //let correctedImage = inputImage.cropped(to: boundingBox).oriented(forExifOrientation: Int32(CGImagePropertyOrientation.up.rawValue))
        
        //let documentImage = convertCIImageToCGImage(inputImage: inputImage)
        
        //if documentImage != nil {
        let imageWidth = CGFloat(self.inputCGImage.width)
        let imageHeight = CGFloat(self.inputCGImage.height)
        let transform = CGAffineTransform.identity.scaledBy(x: imageWidth, y: -imageHeight).translatedBy(x: 0, y: -1)
        let mrzTextRectangles = observations.map({ $0.boundingBox.applying(transform) }).filter({ $0.width > (imageWidth * 0.8) })
        let mrzRegionRect = mrzTextRectangles.reduce(into: CGRect.null, { $0 = $0.union($1) })
        
        guard mrzRegionRect.height <= (imageHeight * 0.4) else { // Avoid processing the full image (can occur if there is a long text in the header)
            return
        }
        
        if let mrzTextImage = self.inputCGImage.cropping(to: mrzRegionRect) {
            if let mrzResult = self.mrz(from: mrzTextImage), mrzResult.allCheckDigitsValid {
                //self.stopScanning()
                
                DispatchQueue.main.async {
                    //var convertUIImage = UIImage(ciImage: self.inputCIImage)
                    let enlargedDocumentImage = self.enlargedDocumentImage(from: self.inputCGImage)
                    let scanResult = QKMRZScanResult(mrzResult: mrzResult, documentImage: enlargedDocumentImage)
                    //let scanResult = QKMRZScanResult(mrzResult: mrzResult, documentImage: UIImage(cgImage: self.inputCGImage))
                    self.didDetectMrzData(self.inputCIImage, at: mrzRegionRect,scanResult: scanResult)
                    
                    //if self.vibrateOnResult {
                    //    AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
                    //}
                }
            }
        }
        //}
    }
    
    // MARK: MRZ
    fileprivate func mrz(from cgImage: CGImage) -> QKMRZResult? {
        let preprocess_cgImage = preprocessImage(cgImage)
        if preprocess_cgImage != nil {
            let mrzTextImage = UIImage(cgImage: preprocess_cgImage!)
            let recognizedString = try? tesseract.performOCR(on: mrzTextImage).get()
            
            if let string = recognizedString, let mrzLines = mrzLines(from: string) {
                return mrzParser.parse(mrzLines: mrzLines)
            }
        }
        return nil
    }
    
    fileprivate func mrzLines(from recognizedText: String) -> [String]? {
        let mrzString = recognizedText.replacingOccurrences(of: " ", with: "")
        var mrzLines = mrzString.components(separatedBy: "\n").filter({ !$0.isEmpty })
        
        // Remove garbage strings located at the beginning and at the end of the result
        if !mrzLines.isEmpty {
            let averageLineLength = (mrzLines.reduce(0, { $0 + $1.count }) / mrzLines.count)
            mrzLines = mrzLines.filter({ $0.count >= averageLineLength })
        }
        
        return mrzLines.isEmpty ? nil : mrzLines
    }
    
    fileprivate func preprocessImage(_ image: CGImage) -> CGImage? {
        var inputImage = CIImage(cgImage: image)
        let averageLuminance = inputImage.averageLuminance
        var exposure = 0.5
        let threshold = (1 - pow(1 - averageLuminance, 0.2))
        
        if averageLuminance > 0.8 {
            exposure -= ((averageLuminance - 0.5) * 2)
        }
        
        if averageLuminance < 0.35 {
            exposure += pow(2, (0.5 - averageLuminance))
        }
        
        inputImage = inputImage.applyingFilter("CIExposureAdjust", parameters: ["inputEV": exposure])
            .applyingFilter("CILanczosScaleTransform", parameters: [kCIInputScaleKey: 2])
            .applyingFilter("LuminanceThresholdFilter", parameters: ["inputThreshold": threshold])
        
        return CIContext.shared.createCGImage(inputImage, from: inputImage.extent)
    }
    
    // callback vision request
    fileprivate func didDetectFaceImage(_ image: CIImage, at rect: CGRect) {
        checkFace = true
        updateScanArea()
        self.capturedFace = self.getUIImage(from: image)
    }
    
    fileprivate func didDetectMrzData(_ image: CIImage, at rect: CGRect, scanResult: QKMRZScanResult) {
        checkMrz = true
        updateScanArea()
        sdkModel.mrzInfo = scanResult
        self.capturedMrz = self.getUIImage(from: image)
        
        sdkModel.mrzImage = self.capturedMrz
        //self.delegate?.didDetectSdkData(self, didDetect: sdkModel)
    }
    
    fileprivate func didDetectCardImage(_ image: CGImage) {
        checkRectangle = true
        self.updateScanArea()
        
        self.capturedImage = UIImage(cgImage: image) //self.getUIImage(from: image)
        //if debugMode { self.imgView.image =  self.capturedImage }
    }
    
    private func readCard(_ idCardModel: IDCardModel?) {
        let idCardUtil = IDCardUtil()
        if idCardModel == nil {
            //fö
            //idCardUtil.passportNumber =  "A01H02164"//idCardModel.documentNumber
            //idCardUtil.dateOfBirth = "920407"//idCardModel.birthDate!.toString()
            //idCardUtil.expiryDate = "270222"//idCardModel.expiryDate!.toString()
            
            //sö
            //idCardUtil.passportNumber =  "A03K87112"//idCardModel.documentNumber
            //idCardUtil.dateOfBirth = "921207"//idCardModel.birthDate!.toString()
            //idCardUtil.expiryDate = "270618"//idCardModel.expiryDate!.toString()
        }
        else {
            idCardUtil.passportNumber =  idCardModel!.documentNumber
            idCardUtil.dateOfBirth = idCardModel!.birthDate!.toString()
            idCardUtil.expiryDate = idCardModel!.expiryDate!.toString()
        }

        let mrzKey = idCardUtil.getMRZKey()
        
        
        // Set the masterListURL on the Passport Reader to allow auto passport verification
        //let masterListURL = Bundle.main.url(forResource: "masterList", withExtension: ".pem")!
        //let masterListURL = Bundle(for: SCSoftKycView.self).url(forResource: "CSCA_TR", withExtension: ".pem")
        //if masterListURL != nil {
        //    idCardReader.setMasterListURL( masterListURL! )
        //}
        
        // If we want to read only specific data groups we can using:
        // let dataGroups : [DataGroupId] = [.COM, .SOD, .DG1, .DG2, .DG7, .DG11, .DG12, .DG14, .DG15]
        // passportReader.readPassport(mrzKey: mrzKey, tags:dataGroups, completed: { (passport, error) in
        
        //setMRZInfo(idCardUtil)
        idCardReader.readPassport(mrzKey: mrzKey, customDisplayMessage: { (displayMessage) in
            switch displayMessage {
            case .requestPresentPassport:
                return "IPhone'unuzu NFC özellikli bir Kimlik Kartının yakınında tutun."
            case .successfulRead:
                return "Kimlik Kartı Başarıyla okundu."
            case .readingDataGroupProgress(let dataGroup, let progress):
                let progressString = self.handleProgress(percentualProgress: progress)
                return "Yükleniyor lütfen bekleyiniz...\n\(progressString)"
            //return "Yükleniyor lütfen bekleyiniz \(dataGroup) ...\n\(progressString)"
            //return "Yükleniyor lütfen bekleyiniz...\n"
            default:
                return nil
            }
        }, completed: { (passport, error) in
            if let passport = passport {
                // All good, we got a passport
                DispatchQueue.main.async {
                    idCardUtil.passport = passport
                    self.setIDCard(idCardUtil)
                    // self.callApplyToBeNewCustomerService()
                }
            } else {
                print("Hata: ", error.debugDescription)
            }
        })
    }
    
    fileprivate func setIDCard(_ idCardUtil:IDCardUtil){
        let cameraPermissionDenied = false
        let newIdCardsNotFound = false
        let nfcNotSupported = false
        let customerIsNotAvailableForVideoCall = false
        let nfcReadSuccessful = true
        let docType = 1
        
        let cert1 = idCardUtil.passport?.documentSigningCertificate
        let cert2 = idCardUtil.passport?.countrySigningCertificate
        
        //let cert =  idCardUtil.passport?.certificateSigningGroups[.documentSigningCertificate]
        //let xyz = cert?.certToPEM()
        let com = idCardUtil.passport?.dataGroupsRead[.COM] as? COM
        //let sod = idCardUtil.passport?.dataGroupsRead[.SOD] as? SOD
        
        //let fghfh = sod?.pkck7CertificateData
        //let sss =  Data(fghfh!)
        //let sdfasdf  = sss.base64EncodedString()
        
        let sodH = idCardUtil.passport?.dataGroupHashes[.SOD] as? DataGroup
        
        let name = idCardUtil.passport?.firstName
        let surname = idCardUtil.passport?.lastName
        let personalNumber = idCardUtil.passport?.personalNumber
        var genderTemp = "N/A"
        if idCardUtil.passport?.gender == "F" {
            genderTemp = "FEMALE"
        } else if idCardUtil.passport?.gender == "M" {
            genderTemp = "MALE"
        }
        let gender = genderTemp
        let birthDate = idCardUtil.passport?.dateOfBirth
        let expiryDate = idCardUtil.passport?.documentExpiryDate
        let serialNumber = idCardUtil.passport?.documentNumber
        let nationality = idCardUtil.passport?.nationality
        let issuerAuthority = idCardUtil.passport?.issuingAuthority
        
        let faceImage = idCardUtil.passport?.passportImage!.jpegData(compressionQuality: getImageQuality(image: (idCardUtil.passport?.passportImage)!))
        let signatureImage = idCardUtil.passport?.passportImage!.jpegData(compressionQuality: getImageQuality(image: (idCardUtil.passport?.passportImage)!))
        if faceImage != nil {
            //let faceImageBase64 = AESHelper.fromDataToBase64String(faceImage!)
            //let portraitImageBase64 = AESHelper.fromDataToBase64String(faceImage!)
        }
        
        if signatureImage != nil {
            //let signatureBse64 = AESHelper.fromDataToBase64String(signatureImage!)
        }
        let fingerPrints = ["",""]
        
        //AdditionalPersonDetails
        var placeofBirth : [String] = []
        placeofBirth.append(idCardUtil.passport?.placeOfBirth ?? "")
        
        let placeOfBirth = placeofBirth
        
        var permanetAddress : [String] = []
        permanetAddress.append(idCardUtil.passport?.residenceAddress ?? "")
        
        let permanentAddress = permanetAddress
        
        
        let telephone = idCardUtil.passport?.phoneNumber
        
        let dg11 = idCardUtil.passport?.dataGroupsRead[.DG11] as? DataGroup11
        let custodyInfo = dg11?.custodyInfo ?? ""
        let fulldateOfBirth = dg11?.dateOfBirth ?? ""
        let title = dg11?.title ?? ""
        let profession = dg11?.profession ?? ""
        let proofOfCitizenship = dg11?.proofOfCitizenship ?? ""
        let personalNumber2 = dg11?.personalNumber ?? ""
        let personalSummary = dg11?.personalSummary ?? ""
        let tdNumber = dg11?.tdNumbers ?? ""
        var tdNumbers : [String] = []
        tdNumbers.append(tdNumber)
        
        let custodyInformation = custodyInfo
        let fullDateOfBirth2 = fulldateOfBirth
        
        let proofOfCitizenship2 = proofOfCitizenship
        let profession2 = profession
        let personalNumber3 = personalNumber2
        let personalSummary2 = personalSummary
        let otherValidTDNumbers = tdNumbers
        let title2 = title
        
        //self.infoLabel.isHidden = true
        self.callResultScreen(idCardUtil)
    }
    
    fileprivate func callResultScreen(_ idCardUtil:IDCardUtil){
        sdkModel.nfcData = idCardUtil
        //performSegue(withIdentifier: "showResult", sender: self)
        //delegate?.didDetectSdkData(self, didDetect: sdkModel)
        delegate?.didReadNfc(self, didRead: idCardUtil.passport!)
        //showJitsiView()
        getNextViewType()
    }
    
    fileprivate func handleProgress(percentualProgress: Int) -> String {
        let p = (percentualProgress/20)
        let full = String(repeating: "🟢 ", count: p)
        let empty = String(repeating: "⚪️ ", count: 5-p)
        return "\(full)\(empty)"
    }
    
    fileprivate func getImageQuality(image : UIImage) -> CGFloat{
        return 1.0
    }
}

extension SCSoftKycView: AVCaptureVideoDataOutputSampleBufferDelegate  {
    public func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        
        //guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        //let ciImage = CIImage(cvImageBuffer: pixelBuffer)
        //guard let cgImage = convertCIImageToCGImage(inputImage: ciImage) else { return }
        
        guard let cgImage = CMSampleBufferGetImageBuffer(sampleBuffer)?.cgImage else {return }
        if selectedViewType == .idPhoto && cutoutRect != nil{
            self.inputCGImage = self.documentImage(from: cgImage) // cropped image
            self.inputCIImage = CIImage(cgImage: inputCGImage)
        }
        else if selectedViewType == .selfie  && cutoutSelfieRect != nil {
            self.inputCGImage = self.selfieImage(from: cgImage) // cropped image
            self.inputCIImage = CIImage(cgImage: inputCGImage)
        }else {
            self.inputCGImage = cgImage
        }
        
        
        performVisionRequest(image: inputCGImage, orientation: .up)
    }
}

extension SCSoftKycView: JitsiMeetViewDelegate {
    public func conferenceJoined(_ data: [AnyHashable : Any]!) {
        print("conferenceJoined")
        inJitsi = true
    }
    
    public func conferenceTerminated(_ data: [AnyHashable : Any]!) {
        DispatchQueue.main.async {
                self.cleanUp()
        }
        didConferenceTerminated?(data)
        inJitsi = false
    }
    
    fileprivate func cleanUp() {
        jitsiMeetView.removeFromSuperview()
    }

    public func conferenceWillJoin(_ data: [AnyHashable : Any]!) {
        print("conferenceWillJoin")
    }
    
    fileprivate func openJitsiMeet(url : String, room : String, token : String) {
        let options = JitsiMeetConferenceOptions.fromBuilder { builder in
            //builder.serverURL = URL(string: self.url)
            //builder.room = self.room
            
            builder.serverURL = URL(string: url)
            builder.room = room
            builder.token = token
            
            builder.audioOnly = false
            builder.audioMuted = false
            builder.videoMuted = false
            builder.welcomePageEnabled = false
            
            builder.setFeatureFlag("add-people.enabled", withBoolean: false)
            builder.setFeatureFlag("invite.enabled", withBoolean: false)
            builder.setFeatureFlag("raise-hand.enabled", withBoolean: false)
            builder.setFeatureFlag("video-share.enabled", withBoolean: false)
            builder.setFeatureFlag("toolbox.alwaysVisible", withBoolean: false)
            builder.setFeatureFlag("toolbox.enabled", withBoolean: false)
            builder.setFeatureFlag("live-streaming.enabled", withBoolean: false)
            builder.setFeatureFlag("chat.enabled", withBoolean: false)
            builder.setFeatureFlag("meeting-password.enabled", withBoolean: false)
            builder.setFeatureFlag("meeting-name.enabled", withBoolean: false)
            builder.setFeatureFlag("calendar.enabled", withBoolean: false)
            builder.setFeatureFlag("conference-timer.enabled", withBoolean: false)
            builder.setFeatureFlag("call-integration.enabled", withBoolean: false)
            builder.setFeatureFlag("close-captions.enabled", withBoolean: false)
            builder.setFeatureFlag("kick-out.enabled", withBoolean: false)
            builder.setFeatureFlag("meeting-name.enabled", withBoolean: false)
            builder.setFeatureFlag("pip.enabled", withBoolean: false)
            builder.setFeatureFlag("recording.enabled", withBoolean: false)
            builder.setFeatureFlag("resolution", withBoolean: false)
            builder.setFeatureFlag("server-url-change.enabled", withBoolean: false)
            builder.setFeatureFlag("tile-view.enabled", withBoolean: false)
        }
        
        jitsiMeetView = JitsiMeetView()
        jitsiMeetView.delegate = self
        //view = jitsiMeetView
        jitsiMeetView.join(options)
    }
}
