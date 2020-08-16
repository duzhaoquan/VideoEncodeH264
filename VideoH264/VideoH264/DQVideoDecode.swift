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
    
    var videoDecodeCallback:((CVImageBuffer?) -> Void)?
    func SetVideoDecodeCallback(block:((CVImageBuffer?) -> Void)?)  {
        videoDecodeCallback = block
    }
    
    init(width:Int32,height:Int32) {
        self.width = width
        self.height = height
        
        
    }
    
    func initDecoder() -> Bool {
        
        if decompressionSession != nil {
            return true
        }
        guard spsData != nil,ppsData != nil else {
            return false
        }
//        var frameData = Data(capacity: Int(size))
//        frameData.append(length, count: 4)
//        let point :UnsafePointer<UInt8> = [UInt8](data).withUnsafeBufferPointer({$0}).baseAddress!
//        frameData.append(point + UnsafePointer<UInt8>.Stride(4), count: Int(naluSize))
        //处理sps/pps
        var sps : [UInt8] = []
        [UInt8](spsData!).suffix(from: 4).forEach { (value) in
            sps.append(value)
        }
        var pps : [UInt8] = []
        [UInt8](ppsData!).suffix(from: 4).forEach{(value) in
            pps.append(value)
        }
        
        let spsAndpps = [sps.withUnsafeBufferPointer{$0}.baseAddress!,pps.withUnsafeBufferPointer{$0}.baseAddress!]
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
        let descriptionState = CMVideoFormatDescriptionCreateFromH264ParameterSets(allocator: kCFAllocatorDefault, parameterSetCount: 2, parameterSetPointers: spsAndpps, parameterSetSizes: sizes, nalUnitHeaderLength: 4, formatDescriptionOut: &decodeDesc)
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
//            kCVPixelBufferOpenGLCompatibilityKey:true
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
//            sourceFrameRefCon = imageBuffer
            if let block = decoder.videoDecodeCallback  {
                decoder.callBackQueue.async {
                    block(imageBuffer)
                }
                
            }
        }
    }
    func decode(data:Data) {
        decodeQueue.async {
            let length:UInt32 =  UInt32(data.count)
            self.decodeByte(data: data, size: length)
        }
    }
    private func decodeByte(data:Data,size:UInt32) {
        //数据类型:frame的前4个字节是NALU数据的开始码，也就是00 00 00 01，
        // 将NALU的开始码转为4字节大端NALU的长度信息
        let naluSize = size - 4
        let length : [UInt8] = [
            UInt8(truncatingIfNeeded: naluSize >> 24),
            UInt8(truncatingIfNeeded: naluSize >> 16),
            UInt8(truncatingIfNeeded: naluSize >> 8),
            UInt8(truncatingIfNeeded: naluSize)
            ]
        var frameByte :[UInt8] = length
        [UInt8](data).suffix(from: 4).forEach { (bb) in
            frameByte.append(bb)
        }
        let bytes = frameByte //[UInt8](frameData)
        // 第5个字节是表示数据类型，转为10进制后，7是sps, 8是pps, 5是IDR（I帧）信息
        let type :Int  = Int(bytes[4] & 0x1f)
        switch type{
        case 0x05:
            if initDecoder() {
                decode(frame: bytes, size: size)
            }
            
        case 0x06:
//            print("增强信息")
            break
        case 0x07:
            spsData = data
        case 0x08:
            ppsData = data
        default:
            if initDecoder() {
                decode(frame: bytes, size: size)
            }
        }
    }
    
    private func decode(frame:[UInt8],size:UInt32) {
        //
        var blockBUffer :CMBlockBuffer?
        var frame1 = frame
//        var memoryBlock = frame1.withUnsafeMutableBytes({$0}).baseAddress
//        var ddd = Data(bytes: frame, count: Int(size))
        //创建blockBuffer
        /*!
         参数1: structureAllocator kCFAllocatorDefault
         参数2: memoryBlock  frame
         参数3: frame size
         参数4: blockAllocator: Pass NULL
         参数5: customBlockSource Pass NULL
         参数6: offsetToData  数据偏移
         参数7: dataLength 数据长度
         参数8: flags 功能和控制标志
         参数9: newBBufOut blockBuffer地址,不能为空
         */
        let blockState = CMBlockBufferCreateWithMemoryBlock(allocator: kCFAllocatorDefault,
                                           memoryBlock: &frame1,
                                           blockLength: Int(size),
                                           blockAllocator: kCFAllocatorNull,
                                           customBlockSource: nil,
                                           offsetToData:0,
                                           dataLength: Int(size),
                                           flags: 0,
                                           blockBufferOut: &blockBUffer)
        if blockState != 0 {
            print("创建blockBuffer失败")
        }
//
        var sampleSizeArray :[Int] = [Int(size)]
        var sampleBuffer :CMSampleBuffer?
        //创建sampleBuffer
        /*
         参数1: allocator 分配器,使用默认内存分配, kCFAllocatorDefault
         参数2: blockBuffer.需要编码的数据blockBuffer.不能为NULL
         参数3: formatDescription,视频输出格式
         参数4: numSamples.CMSampleBuffer 个数.
         参数5: numSampleTimingEntries 必须为0,1,numSamples
         参数6: sampleTimingArray.  数组.为空
         参数7: numSampleSizeEntries 默认为1
         参数8: sampleSizeArray
         参数9: sampleBuffer对象
         */
        let readyState = CMSampleBufferCreateReady(allocator: kCFAllocatorDefault,
                                  dataBuffer: blockBUffer,
                                  formatDescription: decodeDesc,
                                  sampleCount: CMItemCount(1),
                                  sampleTimingEntryCount: CMItemCount(),
                                  sampleTimingArray: nil,
                                  sampleSizeEntryCount: CMItemCount(1),
                                  sampleSizeArray: &sampleSizeArray,
                                  sampleBufferOut: &sampleBuffer)
        if readyState != 0 {
            print("Sample Buffer Create Ready faile")
        }
        //解码数据
        /*
         参数1: 解码session
         参数2: 源数据 包含一个或多个视频帧的CMsampleBuffer
         参数3: 解码标志
         参数4: 解码后数据outputPixelBuffer
         参数5: 同步/异步解码标识
         */
        let sourceFrame:UnsafeMutableRawPointer? = nil
        var inforFalg = VTDecodeInfoFlags.asynchronous
        let decodeState = VTDecompressionSessionDecodeFrame(self.decompressionSession!, sampleBuffer: sampleBuffer!, flags:VTDecodeFrameFlags._EnableAsynchronousDecompression , frameRefcon: sourceFrame, infoFlagsOut: &inforFalg)
        if decodeState != 0 {
            print("解码失败")
        }
    }
    
    deinit {
        if decompressionSession != nil {
            VTDecompressionSessionInvalidate(decompressionSession!)
            decompressionSession = nil
        }
        
    }
}
extension Int {
    // MARK:- 转成 2位byte
    func lyz_to2Bytes() -> [UInt8] {
        let UInt = UInt16.init(Double.init(self))
        return [UInt8(truncatingIfNeeded: UInt >> 8),UInt8(truncatingIfNeeded: UInt)]
    }
    // MARK:- 转成 4字节的bytes
    func lyz_to4Bytes() -> [UInt8] {
        let UInt = UInt32.init(Double.init(self))
        return [UInt8(truncatingIfNeeded: UInt >> 24),
                UInt8(truncatingIfNeeded: UInt >> 16),
                UInt8(truncatingIfNeeded: UInt >> 8),
                UInt8(truncatingIfNeeded: UInt)]
    }
    // MARK:- 转成 8位 bytes
    func lyz_toEightBytes() -> [UInt8] {
        let UInt = UInt64.init(Double.init(self))
        return [UInt8(truncatingIfNeeded: UInt >> 56),
                UInt8(truncatingIfNeeded: UInt >> 48),
                UInt8(truncatingIfNeeded: UInt >> 40),
                UInt8(truncatingIfNeeded: UInt >> 32),
                UInt8(truncatingIfNeeded: UInt >> 24),
                UInt8(truncatingIfNeeded: UInt >> 16),
                UInt8(truncatingIfNeeded: UInt >> 8),
                UInt8(truncatingIfNeeded: UInt)]
    }
}
extension Data {
    //1bytes转Int
    func lyz_1BytesToInt() -> Int {
        var value : UInt8 = 0
        let data = NSData(bytes: [UInt8](self), length: self.count)
        data.getBytes(&value, length: self.count)
        value = UInt8(bigEndian: value)
        return Int(value)
    }
    
    //2bytes转Int
    func lyz_2BytesToInt() -> Int {
        var value : UInt16 = 0
        let data = NSData(bytes: [UInt8](self), length: self.count)
        data.getBytes(&value, length: self.count)
        value = UInt16(bigEndian: value)
        return Int(value)
    }
    
    //4bytes转Int
    func lyz_4BytesToInt() -> Int {
        var value : UInt32 = 0
        let data = NSData(bytes: [UInt8](self), length: self.count)
        data.getBytes(&value, length: self.count)
        value = UInt32(bigEndian: value)
        return Int(value)
    }
    
}
