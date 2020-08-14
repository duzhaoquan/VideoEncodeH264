//
//  DQVideoDecode.swift
//  VideoH264
//
//  Created by dzq_mac on 2020/8/13.
//  Copyright © 2020 dzq_mac. All rights reserved.
//

import UIKit
import AVFoundation
import VideoToolbox

class DQVideoDecode: NSObject {

    var width: Int32 = 480
    var height:Int32 = 640
    
    var decodeQueue = DispatchQueue(label: "decode")
    var callBackQueue = DispatchQueue(label: "decodeCallBack")
    var decodeDesc : CMVideoFormatDescription?
    
    var spsData:Data?
    var ppsData:Data?
    
    var decompressionSession : VTDecompressionSession?
    var callback :VTDecompressionOutputCallback?
    
    var videoDecodeCallback:((CVImageBuffer) -> Void)?
    func SetVideoDecodeCallback(block:((CVImageBuffer) -> Void)?)  {
        videoDecodeCallback = block
    }
    
    init(width:Int32,height:Int32) {
        self.width = width
        self.height = height
        
        
    }
    
    func initDecoder() -> Bool {
        
        if decodeDesc != nil {
            return true
        }
        guard spsData != nil,ppsData != nil else {
            return false
        }
        
        var sps : [UInt8] = []
        [UInt8](spsData!).suffix(from: 4).forEach { (value) in
            sps.append(value)
        }
        var pps : [UInt8] = []
        [UInt8](ppsData!).suffix(from: 4).forEach{(value) in
            pps.append(value)
        }
        let spsAndpps = [sps.withUnsafeBufferPointer{$0}.baseAddress!,pps.withUnsafeBufferPointer{$0}.baseAddress!]
        
//        guard let pionter = spsAndpps.withUnsafeBufferPointer({$0}).baseAddress else{return false}
        let sizes = [sps.count,pps.count]

        /**
        根据sps pps设置解码参数
        param kCFAllocatorDefault 分配器
        param 2 参数个数
        param parameterSetPointers 参数集指针
        param parameterSetSizes 参数集大小
        param naluHeaderLen nalu nalu start code 的长度 4
        param _decodeDesc 解码器描述
        return 状态
        */
        let descriptionState = CMVideoFormatDescriptionCreateFromH264ParameterSets(allocator: nil, parameterSetCount: 2, parameterSetPointers: spsAndpps, parameterSetSizes: sizes, nalUnitHeaderLength: 4, formatDescriptionOut: &decodeDesc)
        if descriptionState != 0 {
            print("description创建失败" )
            return false
        }
        //解码回调设置
        /*
         VTDecompressionOutputCallbackRecord 是一个简单的结构体，它带有一个指针 (decompressionOutputCallback)，指向帧解压完成后的回调方法。你需要提供可以找到这个回调方法的实例 (decompressionOutputRefCon)。VTDecompressionOutputCallback 回调方法包括七个参数：
                参数1: 回调的引用
                参数2: 帧的引用
                参数3: 一个状态标识 (包含未定义的代码)
                参数4: 指示同步/异步解码，或者解码器是否打算丢帧的标识
                参数5: 实际图像的缓冲
                参数6: 出现的时间戳
                参数7: 出现的持续时间
         */
        setCallBack()
        var callbackRecord = VTDecompressionOutputCallbackRecord(decompressionOutputCallback: callback, decompressionOutputRefCon: unsafeBitCast(self, to: UnsafeMutableRawPointer.self))
        /*
         解码参数:
        * kCVPixelBufferPixelFormatTypeKey:摄像头的输出数据格式
         kCVPixelBufferPixelFormatTypeKey，已测可用值为
            kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange，即420v
            kCVPixelFormatType_420YpCbCr8BiPlanarFullRange，即420f
            kCVPixelFormatType_32BGRA，iOS在内部进行YUV至BGRA格式转换
         YUV420一般用于标清视频，YUV422用于高清视频，这里的限制让人感到意外。但是，在相同条件下，YUV420计算耗时和传输压力比YUV422都小。
         
        * kCVPixelBufferWidthKey/kCVPixelBufferHeightKey: 视频源的分辨率 width*height
         * kCVPixelBufferOpenGLCompatibilityKey : 它允许在 OpenGL 的上下文中直接绘制解码后的图像，而不是从总线和 CPU 之间复制数据。这有时候被称为零拷贝通道，因为在绘制过程中没有解码的图像被拷贝.
         
         */
        let imageBufferAttributes = [
            kCVPixelBufferPixelFormatTypeKey:kCVPixelFormatType_420YpCbCr8BiPlanarFullRange,
            kCVPixelBufferWidthKey:width,
            kCVPixelBufferHeightKey:height,
            kCVPixelBufferOpenGLCompatibilityKey:true
            ] as [CFString : Any]
        
        //创建session
        
        /*!
         @function    VTDecompressionSessionCreate
         @abstract    创建用于解压缩视频帧的会话。
         @discussion  解压后的帧将通过调用OutputCallback发出
         @param    allocator  内存的会话。通过使用默认的kCFAllocatorDefault的分配器。
         @param    videoFormatDescription 描述源视频帧
         @param    videoDecoderSpecification 指定必须使用的特定视频解码器.NULL
         @param    destinationImageBufferAttributes 描述源像素缓冲区的要求 NULL
         @param    outputCallback 使用已解压缩的帧调用的回调
         @param    decompressionSessionOut 指向一个变量以接收新的解压会话
         */
        let state = VTDecompressionSessionCreate(allocator: kCFAllocatorDefault, formatDescription: decodeDesc!, decoderSpecification: nil, imageBufferAttributes: imageBufferAttributes as CFDictionary, outputCallback: &callbackRecord, decompressionSessionOut: &decompressionSession)
        if state != 0 {
            print("创建decodeSession失败")
        }
        VTSessionSetProperty(self.decompressionSession!, key: kVTDecompressionPropertyKey_RealTime, value: kCFBooleanTrue)
        
        return true
        
    }
    //解码成功的回掉
    private func setCallBack()  {
        //(UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, OSStatus, VTDecodeInfoFlags, CVImageBuffer?, CMTime, CMTime) -> Void
        callback = { decompressionOutputRefCon,sourceFrameRefCon,status,inforFlags,imageBuffer,presentationTimeStamp,presentationDuration in
            let decoder :DQVideoDecode = unsafeBitCast(decompressionOutputRefCon, to: DQVideoDecode.self)
            guard imageBuffer != nil else {
                return
            }
            if let block = decoder.videoDecodeCallback  {
                block(imageBuffer!)
            }
        }
    }
    func decode(data:Data) {
        decodeQueue.async {
            var length:UInt32 =  UInt32(data.count)
            self.decodeByte(data: data, size: &length)
        }
    }
    private func decodeByte(data:Data,size:UnsafePointer<UInt32>) {
        //数据类型:frame的前4个字节是NALU数据的开始码，也就是00 00 00 01，
        // 将NALU的开始码转为4字节大端NALU的长度信息
        var bytes = [UInt8](data)
        let naluSize :UnsafePointer<UInt32> = size - 4
        
        bytes[0] = UInt8(naluSize[3])
        bytes[1] = UInt8(naluSize[2])
        bytes[2] = UInt8(naluSize[1])
        bytes[3] = UInt8(naluSize[0])
        
        // 第5个字节是表示数据类型，转为10进制后，7是sps, 8是pps, 5是IDR（I帧）信息
        let type :Int  = Int(bytes[4] & 0x1f)
        switch type{
        case 0x05:
            if initDecoder() {
                decode(frame: bytes, size: size.pointee)
            }
            
        case 0x06:
            print("")
        case 0x07:
            spsData = data
        case 0x08:
            ppsData = data
        default:
            if initDecoder() {
                decode(frame: bytes, size: size.pointee)
            }
        }
    }
    
    private func decode(frame:[UInt8],size:UInt32) {
        
        
        
    }
}
