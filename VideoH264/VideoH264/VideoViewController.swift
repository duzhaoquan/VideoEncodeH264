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
//    var imageView : UIImageView!
//    var dataOutPut: AVCaptureMetadataOutput!
    
    var captureView : UIView!
    let output = AVCaptureVideoDataOutput()
    var focusBox:UIView!
    var exposureBox : UIView!
    
    var encodeSession:VTCompressionSession!
    
    var encodeCallBack:VTCompressionOutputCallback?
    
    var encoder : DQVideoEncoder!
    var decoder:DQVideoDecode!
    var ccencode : CCVideoEncoder?
    var ccDecode : CCVideoDecoder?
    var player : AAPLEAGLLayer?
    
    var fileHandle : FileHandle?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        self.title = "拍照"
      
        view.backgroundColor = .white
        
        captureView = UIView(frame: CGRect(x: 5, y: 200, width: view.frame.size.width/2 - 10, height: 300))
        captureView.backgroundColor = .orange
        view.addSubview(captureView)
        previewLayer.frame = captureView.bounds
        //CGRect(x: 0, y: 100, width: view.bounds.size.width, height: view.bounds.size.height - 200)
        previewLayer.isHidden = true
        previewLayer.videoGravity = .resizeAspectFill
        captureView.layer.addSublayer(previewLayer)
        
        player = AAPLEAGLLayer(frame: CGRect(x: view.frame.size.width/2 + 5, y: 200, width: view.frame.size.width/2 - 10, height: 300))
        view.layer.addSublayer(player!)
        
        recodButton = UIButton(frame: CGRect(x: view.bounds.size.width - 160, y: view.bounds.size.height - 60, width: 150, height: 50))
        recodButton.backgroundColor = .gray
        recodButton.center.x = view.center.x
        recodButton.setTitle("start record", for: .normal)
        recodButton.addTarget(self, action: #selector(recordAction(btn:)), for: .touchUpInside)
        view.addSubview(recodButton)
        
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
        DispatchQueue.global().async {
            self.session.startRunning()
        }
        
        
        //编码
        encoder = DQVideoEncoder(width: 480, height: 640)
        encoder.videoEncodeCallback {[weak self] (data) in
//            self?.writeTofile(data: data)
            self?.decoder.decode(data: data)
//            self?.ccDecode?.decodeNaluData(data)
        }
        encoder.videoEncodeCallbackSPSAndPPS {[weak self] (sps, pps) in
            //存入文件
//            self?.writeTofile(data: sps)
//            self?.writeTofile(data: pps)
            //直接解码
            self?.decoder.decode(data: sps)
            self?.decoder.decode(data: pps)
//            self?.ccDecode?.decodeNaluData(sps)
//            self?.ccDecode?.decodeNaluData(pps)
        }
        //解码
        decoder = DQVideoDecode(width: 480, height: 640)
        decoder.SetVideoDecodeCallback { (image) in
            self.player?.pixelBuffer = image
            
        }
        
        //OC版本使用
        let con = CCVideoConfig()
        con.width = 480
        con.height = 640
        con.bitrate = 480 * 640 * 5
        ccencode = CCVideoEncoder(config: con)
        ccencode?.delegate = self
        ccDecode = CCVideoDecoder(config: con)
        ccDecode?.delegate = self
    
    }
    
    func writeTofile(data: Data){
        _ = try? self.fileHandle?.seekToEnd()
        self.fileHandle?.write(data)
    }
    @objc func recordAction(btn:UIButton){
        btn.isSelected = !btn.isSelected
        if !session.isRunning{
            session.startRunning()
        }
        if btn.isSelected {
            
            btn.setTitle("stop record", for: .normal)
            
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
            
            if fileHandle == nil{
                //生成的文件地址
                guard let path = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true).first else { return  }
                let filePath =  "\(path)/video.h264"
                try? FileManager.default.removeItem(atPath: filePath)
                if FileManager.default.createFile(atPath: filePath, contents: nil, attributes: nil){
                    print("创建264文件成功")
                }else{
                    print("创建264文件失败")
                }
                fileHandle = FileHandle(forWritingAtPath: filePath)
            }
            
        }else{
            session.removeOutput(output)
            btn.setTitle("start record", for: .normal)
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
    var flash = false
    func setFlash(){
        //设备是否支持闪光灯
        guard let device = self.input?.device,device.isTorchAvailable else {
            return
        }
        //        When using AVCapturePhotoOutput, AVCaptureDevice's flashMode property is ignored. You specify flashMode on a per photo basis by setting the AVCapturePhotoSettings.flashMode property.
        
        
        do {
            try device.lockForConfiguration()
            if flash {
                device.torchMode = .off
                flash = false
            }else{
                device.torchMode = .on
                flash = true
            }
            
            device.unlockForConfiguration()
        } catch let error {
            print(error.localizedDescription)
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
        
        encoder.encodeVideo(sampleBuffer: sampleBuffer)
//        ccencode?.encodeVideoSampleBuffer(sampleBuffer)

    }
    
}
//MARK: -AVCaptureFileOutputRecordingDelegate
extension VideoViewController : AVCaptureFileOutputRecordingDelegate {
    
    //录制完成
    func fileOutput(_ output: AVCaptureFileOutput, didFinishRecordingTo outputFileURL: URL, from connections: [AVCaptureConnection], error: Error?) {
        
    }
        
}
//Mark - OC版代理回掉
extension VideoViewController :CCVideoDecoderDelegate,CCVideoEncoderDelegate{
    func videoDecodeCallback(_ imageBuffer: CVPixelBuffer!) {
        player?.pixelBuffer = imageBuffer
    }
    
    func videoEncodeCallback(_ h264Data: Data!) {
        self.decoder.decode(data: h264Data)
    }
    
    func videoEncodeCallbacksps(_ sps: Data!, pps: Data!) {
        self.decoder.decode(data: sps)
        self.decoder.decode(data: pps)
    }

}

