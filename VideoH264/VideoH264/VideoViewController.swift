//
//  VideoViewController.swift
//  VideoH264
//
//  Created by dzq_mac on 2020/8/1.
//  Copyright © 2020 dzq_mac. All rights reserved.
//

import UIKit
import AVFoundation
import Photos
import VideoToolbox

class VideoViewController: UIViewController {
    //按钮
    var captureButton:UIButton!
    var recodButton:UIButton!
    
    var session : AVCaptureSession = AVCaptureSession()
    var queue = DispatchQueue(label: "quque")
    var input: AVCaptureDeviceInput?
    lazy var previewLayer  = AVCaptureVideoPreviewLayer(session: self.session)
    lazy var recordOutput = AVCaptureMovieFileOutput()
    var imageView : UIImageView!
    var dataOutPut: AVCaptureMetadataOutput!
    
    var focusBox:UIView!
    var exposureBox : UIView!
    
    var encodeSession:VTCompressionSession!
    
    var encodeCallBack:VTCompressionOutputCallback?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        self.title = "拍照"
      
        view.backgroundColor = .white
        
        previewLayer.frame = view.bounds
        //CGRect(x: 0, y: 100, width: view.bounds.size.width, height: view.bounds.size.height - 200)
        previewLayer.isHidden = true
        previewLayer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(previewLayer)
        
        recodButton = UIButton(frame: CGRect(x: view.bounds.size.width - 160, y: view.bounds.size.height - 60, width: 150, height: 50))
        recodButton.backgroundColor = .gray
        recodButton.center.x = view.center.x
        recodButton.setTitle("start record", for: .normal)
        recodButton.addTarget(self, action: #selector(recordAction(btn:)), for: .touchUpInside)
        view.addSubview(recodButton)
        
        imageView = UIImageView(frame: CGRect.init(x: 100, y: 200, width: 200, height: 300))
        imageView.backgroundColor = .orange
        view.addSubview(imageView)
        imageView.isHidden = true
        
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
        
        startCapture()
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
    
    func startCapture(){
        
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
        //视图重力
        previewLayer.videoGravity = .resizeAspect
        session.startRunning()
    
    }
    @objc func recordAction(btn:UIButton){
        btn.isSelected = !btn.isSelected
        if session.isRunning {
            if btn.isSelected {
                
                btn.setTitle("stop record", for: .normal)
                if !session.isRunning{
                    session.startRunning()
                }
                let output = AVCaptureVideoDataOutput()
                output.setSampleBufferDelegate(self, queue: queue)
                if session.canAddOutput(output){
                    session.addOutput(output)
                }
                output.alwaysDiscardsLateVideoFrames = false
                //这里设置格式为BGRA，而不用YUV的颜色空间，避免使用Shader转换
                //注意:这里必须和后面CVMetalTextureCacheCreateTextureFromImage 保存图像像素存储格式保持一致.否则视频会出现异常现象.
                output.videoSettings = [String(kCVPixelBufferPixelFormatTypeKey)  :NSNumber(value: kCVPixelFormatType_32BGRA) ]
                let connection: AVCaptureConnection = output.connection(with: .video)!
                connection.videoOrientation = .portrait
                
                //生成的文件地址
                guard let path = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true).first else { return  }
                let filePath =  "\(path)/video.h264"
                
                try? FileManager.default.removeItem(atPath: filePath)
                if FileManager.default.createFile(atPath: filePath, contents: nil, attributes: nil){
                    print("创建264文件成功")
                }else{
                    print("创建264文件失败")
                }
                
                
            }else{
                btn.setTitle("start record", for: .normal)
            }
        }else{
            imageView.isHidden = true
        }
        
    }
    
    func initVideoToolBox() {
         
        //创建VTCompressionSession
        var bself = self
        let state = VTCompressionSessionCreate(allocator: nil, width: 480, height: 640, codecType: kCMVideoCodecType_H264, encoderSpecification: nil, imageBufferAttributes: nil, compressedDataAllocator: nil, outputCallback: encodeCallBack, refcon: &bself, compressionSessionOut: &self.encodeSession)
        
        if state != 0{
            print("creat VTCompressionSession failed")
        }
            
        //设置实时编码输出
        VTSessionSetProperty(encodeSession, key: kVTCompressionPropertyKey_RealTime, value: kCFBooleanTrue)
        //设置编码方式
        VTSessionSetProperty(encodeSession, key: kVTCompressionPropertyKey_ProfileLevel, value: kVTProfileLevel_H264_Baseline_AutoLevel)
        //设置是否产生B帧(因为B帧在解码时并不是必要的,是可以抛弃B帧的)
        VTSessionSetProperty(encodeSession, key: kVTCompressionPropertyKey_AllowFrameReordering, value: kCFBooleanFalse)
        //设置关键帧间隔
        var frameInterval = 10
        let number = CFNumberCreate(kCFAllocatorDefault, CFNumberType.intType, &frameInterval)
        VTSessionSetProperty(encodeSession, key: kVTCompressionPropertyKey_MaxKeyFrameInterval, value: number)
        //设置期望帧率，不是实际帧率
        var fps = 10
        let fpscf = CFNumberCreate(kCFAllocatorDefault, CFNumberType.intType, &fps)
        VTSessionSetProperty(encodeSession, key: kVTCompressionPropertyKey_ExpectedFrameRate, value: fpscf)
        
        //设置码率平均值，单位是bps。码率大了话就会非常清晰，但同时文件也会比较大。码率小的话，图像有时会模糊，但也勉强能看
        //码率计算公式参考笔记
        var bitrate = 480 * 640 * 3 * 4
        let bitrateAverage = CFNumberCreate(kCFAllocatorDefault, CFNumberType.intType, &bitrate)
        VTSessionSetProperty(encodeSession, key: kVTCompressionPropertyKey_AverageBitRate, value: bitrateAverage)
        
        //码率限制
        var bitRates :[Int] = [bitrate,1]
        
//        CFArrayCreate(kCFAllocatorDefault, bitRates, CFIndex(bitPattern: 2), UnsafePointer<CFArrayCallBacks>!)
//        VTSessionSetProperty(encodeSession, key: kVTCompressionPropertyKey_DataRateLimits, value: [bitrateAverage])
        
        encodeCallBack = {(outputCallbackRefCon, sourceFrameRefCon, status, flag, sampleBuffer) in
        
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
    //MARK: -切换摄像头
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
 
    //MARK: -闪光灯
    func setFlash(mode : AVCaptureDevice.FlashMode){
        //设备是否支持闪光灯
        guard let device = self.input?.device,device.hasFlash else {
            return
        }
        //        When using AVCapturePhotoOutput, AVCaptureDevice's flashMode property is ignored. You specify flashMode on a per photo basis by setting the AVCapturePhotoSettings.flashMode property.
        if device.isFlashModeSupported(mode){
            do {
                try device.lockForConfiguration()
                device.flashMode = mode
                device.unlockForConfiguration()
            } catch let error {
                print(error.localizedDescription)
            }
        }
        
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
    
}

//MARK: -AVCaptureVideoDataOutputSampleBufferDelegate
extension VideoViewController : AVCaptureVideoDataOutputSampleBufferDelegate {
    
    //采集结果
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        
        //guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return  }

    }
    
}
//MARK: -AVCaptureFileOutputRecordingDelegate
extension VideoViewController : AVCaptureFileOutputRecordingDelegate {
    
    //录制完成
    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        
    }
        
}

