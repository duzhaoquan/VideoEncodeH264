//
//  TakephotoViewController.swift
//  VideoH264
//
//  Created by dzq_mac on 2020/8/1.
//  Copyright © 2020 dzq_mac. All rights reserved.
//

import UIKit
import AVFoundation
import Photos
import MobileCoreServices

class TakephotoViewController: UIViewController {
    //按钮
    var captureButton:UIButton!
    var recodButton:UIButton!
    
    var session : AVCaptureSession = AVCaptureSession()
    var queue = DispatchQueue(label: "quque")
    var input: AVCaptureDeviceInput?
    lazy var previewLayer  = AVCaptureVideoPreviewLayer(session: self.session)
    lazy var recordOutput = AVCaptureMovieFileOutput()
    let imageOutPut = AVCapturePhotoOutput.init()
    var imageView : UIImageView!
    
    var focusBox:UIView!
    var exposureBox : UIView!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        self.title = "拍照"
        view.backgroundColor = .white
        previewLayer.frame = view.bounds
        previewLayer.isHidden = true
        previewLayer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(previewLayer)
        recodButton = UIButton(frame: CGRect(x: view.bounds.size.width - 160, y: view.bounds.size.height - 60, width: 150, height: 50))
        recodButton.center.x = view.center.x
        recodButton.backgroundColor = .gray
        
        recodButton.setTitle("拍摄", for: .normal)
        recodButton.addTarget(self, action: #selector(recordAction(btn:)), for: .touchUpInside)
        view.addSubview(recodButton)
        
        imageView = UIImageView(frame: CGRect.init(x: 10, y: view.bounds.size.height - 110, width: 100, height: 100))
        imageView.backgroundColor = .orange
        view.addSubview(imageView)
        imageView.isHidden = true
        
        let tapImage = UITapGestureRecognizer(target: self,action: #selector(imageTap))
        imageView.addGestureRecognizer(tapImage)
        imageView.isUserInteractionEnabled = true
        
        let tap = UITapGestureRecognizer(target: self, action: #selector(tapAction(tap:)))
        view.addGestureRecognizer(tap)
        tap.numberOfTapsRequired = 1
        let tap1 = UITapGestureRecognizer(target: self, action: #selector(doubleTap(tap:)))
        tap1.numberOfTapsRequired = 2
        view.addGestureRecognizer(tap1)
        
        focusBox = boxView(color: UIColor(red: 0.102, green:0.636, blue:1.000, alpha:1.000))
        focusBox.isHidden = true
        exposureBox = boxView(color: UIColor(red: 1, green: 0.421, blue: 0.054, alpha: 1.0))
        exposureBox.isHidden = true
        self.view.addSubview(focusBox)
        self.view.addSubview(exposureBox)
        
        self.capture()
    }
    @objc func imageTap() {
        let imagepiker = UIImagePickerController()
        imagepiker.sourceType = .photoLibrary
        imagepiker.mediaTypes = [String(kUTTypeImage),String(kUTTypeMovie)]
        
        self.present(imagepiker, animated: true, completion: nil)
        
    }
    func boxView(color:UIColor) -> UIView{
        let view = UIView(frame: CGRect(x: 0, y: 0, width: 120, height: 120))
        view.backgroundColor = .clear
        view.layer.borderWidth = 5
        view.layer.borderColor = color.cgColor
        return view
    }
    func boxAnimation(boxView:UIView,point:CGPoint) {
        boxView.center = point
        boxView.isHidden = false
        UIView.animate(withDuration: 0.15,delay: 0, options: .curveEaseInOut, animations: {
            
            boxView.layer.transform = CATransform3DMakeScale(0.5, 0.5, 1.0)
        }) { (complet) in
            let time = DispatchTime.now() + Double(Int64(1 * Double(NSEC_PER_SEC))) / Double(NSEC_PER_SEC)
            DispatchQueue.main.asyncAfter(deadline: time) {
                
                boxView.isHidden = true
                boxView.layer.transform = CATransform3DIdentity
            }
        }
    }
    @objc func tapAction(tap:UITapGestureRecognizer){
        let point = tap.location(in: view)
        setFocus(point: point)
        boxAnimation(boxView: focusBox, point: point)
    }
    
    @objc func doubleTap(tap:UITapGestureRecognizer){
        let point = tap.location(in: view)
        setExposure(point: point)
        boxAnimation(boxView: exposureBox, point: point)
    }
    
    @objc func recordAction(btn:UIButton){
        if session.isRunning {
        
            if !session.isRunning{
                session.startRunning()
            }
            
            //Output必须是全局的，否则无法获取照片
            if session.canAddOutput(imageOutPut) {
                session.addOutput(imageOutPut)
            }
            
            //https://www.jianshu.com/p/83a55032c657
            //AVVideoCodecKey:AVVideoCodecType.jpeg,
            let setting = AVCapturePhotoSettings(format: [AVVideoCodecKey:AVVideoCodecType.jpeg])
            setting.flashMode = .off
            imageOutPut.capturePhoto(with: setting , delegate: self)
            
        }else{
            
            imageView.isHidden = true
            
        }
        
    }
    func capture(){
 
        guard let device = getCamera(postion: .back) else{
            return
        }
        
        guard let input = try? AVCaptureDeviceInput(device: device) else{
            return
        }
        self.input = input
        if session.canAddInput(input) {
            session.addInput(input)
        }
        previewLayer.isHidden = false
        DispatchQueue.global().async {
            self.session.startRunning()
        }
    }
    //MARK: -闪光灯
    func setFlash(mode : AVCaptureDevice.FlashMode){
        //设备是否支持闪光灯
        guard let device = self.input?.device,device.hasFlash else {
            return
        }
        //        When using AVCapturePhotoOutput, AVCaptureDevice's flashMode property is ignored. You specify flashMode on a per photo basis by setting the AVCapturePhotoSettings.flashMode property.
        imageOutPut.photoSettingsForSceneMonitoring?.flashMode = mode
//        if device.isFlashModeSupported(mode){
//            do {
//                try device.lockForConfiguration()
//                imageOutPut.photoSettingsForSceneMonitoring?.flashMode = mode
//                device.unlockForConfiguration()
//            } catch let error {
//                print(error.localizedDescription)
//            }
//        }
        
        
        
    }
    //MARK: - 手电筒
    func setTorch(mode:AVCaptureDevice.TorchMode) {
        //设备是否有手电筒
        guard let device = self.input?.device,device.hasTorch else {
            return
        }
        if device.isTorchModeSupported(mode){
            do {
                try device.lockForConfiguration()
                device.torchMode = mode
                device.unlockForConfiguration()
            } catch let error {
                print(error.localizedDescription)
            }
        }
    }
    
    //MARK: - 聚焦
    func setFocus(point:CGPoint? = nil ) {
        guard let device = self.input?.device else {
            return
        }
        
        if let po =  point {
            // 触摸屏幕的坐标点需要转换成0-1，设置聚焦点
            let cameraPoint = CGPoint(x: po.x/previewLayer.bounds.size.width, y: po.y/previewLayer.bounds.size.height)
            if device.isFocusModeSupported(.continuousAutoFocus) && device.isFocusPointOfInterestSupported {
                do {
                    try device.lockForConfiguration()
                    /*****必须先设定聚焦位置，在设定聚焦方式******/
                    device.focusPointOfInterest = cameraPoint
                    device.focusMode = .continuousAutoFocus
                    
                    device.unlockForConfiguration()
                } catch let error {
                    print(error.localizedDescription)
                }
            }
        }else{
            let mode = AVCaptureDevice.FocusMode.autoFocus
            if device.isFocusModeSupported(mode) {
                do {
                    try device.lockForConfiguration()
                    device.focusMode = mode
                    device.unlockForConfiguration()
                } catch let error {
                    print(error.localizedDescription)
                }
            }
        }
        
    }
    
    //MARK: - 曝光
    func setExposure(point:CGPoint? = nil)  {
        guard let device = self.input?.device else {
            return
        }
        if let po = point {
            let cameraPoint = CGPoint(x: po.x/previewLayer.bounds.size.width, y: po.y/previewLayer.bounds.size.height)
            if device.isExposureModeSupported(.continuousAutoExposure) && device.isExposurePointOfInterestSupported {
                do {
                    try device.lockForConfiguration()
                    device.exposurePointOfInterest = cameraPoint
                    device.exposureMode = .continuousAutoExposure
                    
                } catch let error {
                    print(error.localizedDescription)
                }
            }
            
        }else{
            if device.isExposureModeSupported(.autoExpose) {
                do {
                    try device.lockForConfiguration()
                    device.exposureMode = .autoExpose
                    device.unlockForConfiguration()
                } catch let error {
                    print(error.localizedDescription)
                }
            }
        }
    }
    
    //获取相机设备
    func getCamera(postion: AVCaptureDevice.Position) -> AVCaptureDevice? {
        var devices = [AVCaptureDevice]()
        
        if #available(iOS 10.0, *) {
            let discoverySession = AVCaptureDevice.DiscoverySession(deviceTypes: [AVCaptureDevice.DeviceType.builtInWideAngleCamera], mediaType: AVMediaType.video, position: AVCaptureDevice.Position.unspecified)
            devices = discoverySession.devices
        } else {
            devices = AVCaptureDevice.devices(for: AVMediaType.video)
        }
        
        for device in devices {
            if device.position == postion {
                return device
            }
        }
        return nil
    }
    //切换摄像头
    func swapFrontAndBackCameras() {
        if let input = input {
            
            var newDevice: AVCaptureDevice?
            
            if input.device.position == .front {
                newDevice = getCamera(postion: AVCaptureDevice.Position.back)
            } else {
                newDevice = getCamera(postion: AVCaptureDevice.Position.front)
            }
            
            if let new = newDevice {
                do{
                    let newInput = try AVCaptureDeviceInput(device: new)
                    
                    session.beginConfiguration()
                    
                    session.removeInput(input)
                    session.addInput(newInput)
                    self.input = newInput
                    
                    session.commitConfiguration()
                }
                catch let error as NSError {
                    print("AVCaptureDeviceInput(): \(error)")
                }
            }
        }
    }
    //设置横竖屏问题
    func setupVideoPreviewLayerOrientation() {
        
        if let connection = previewLayer.connection, connection.isVideoOrientationSupported {
            if #available(iOS 13.0, *) {
                if let orientation = UIApplication.shared.windows.first?.windowScene?.interfaceOrientation{
                    switch orientation {
                    case .portrait:
                        connection.videoOrientation = .portrait
                    case .landscapeLeft:
                        connection.videoOrientation = .landscapeLeft
                    case .landscapeRight:
                        connection.videoOrientation = .landscapeRight
                    case .portraitUpsideDown:
                        connection.videoOrientation = .portraitUpsideDown
                    default:
                        connection.videoOrientation = .portrait
                    }
                }
            }else{
                switch UIApplication.shared.statusBarOrientation {
                case .portrait:
                    connection.videoOrientation = .portrait
                case .landscapeRight:
                    connection.videoOrientation = .landscapeRight
                case .landscapeLeft:
                    connection.videoOrientation = .landscapeLeft
                case .portraitUpsideDown:
                    connection.videoOrientation = .portraitUpsideDown
                default:
                    connection.videoOrientation = .portrait
                }
            }
        }
    }
}
//MARK: -AVCaptureVideoDataOutputSampleBufferDelegate
extension TakephotoViewController : AVCaptureVideoDataOutputSampleBufferDelegate {
    
    //采集结果
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        
        //guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return  }

    }
    
}
//MARK: -AVCaptureFileOutputRecordingDelegate
extension TakephotoViewController : AVCaptureFileOutputRecordingDelegate {
    
    //录制完成
    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        
    }
        
}
//MARK: - AVCapturePhotoCaptureDelegate
extension TakephotoViewController : AVCapturePhotoCaptureDelegate {
   
    func photoOutput(_ output: AVCapturePhotoOutput, willBeginCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings) {
         print(resolvedSettings)
    }
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        if let imageData = photo.fileDataRepresentation() {
            
            if let uiImage = UIImage(data: imageData){
                
                imageView.image = uiImage
                imageView.isHidden  = false
                //存入相册
                PHPhotoLibrary.shared().performChanges({
                    PHAssetChangeRequest.creationRequestForAsset(from: uiImage)
                }) { (suceess, eooro) in
                    //保存成功
                    if suceess {
                        DispatchQueue.main.async {
                            let alert = UIAlertController(title: "提示", message: "保存图片到相册成功", preferredStyle: UIAlertController.Style.alert)
                            let action = UIAlertAction(title: "确定", style: .default) { (alertAction) in
                                alert.dismiss(animated: true, completion: nil)
                            }
                            alert.addAction(action)
                            self.present(alert, animated: true, completion: nil)
                        }
                    }
                }
            }
        }
    }
}
