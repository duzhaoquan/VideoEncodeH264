//
//  DQVideoEncoder.swift
//  VideoH264
//
//  Created by dzq_mac on 2020/8/6.
//  Copyright © 2020 dzq_mac. All rights reserved.
//

import UIKit
import VideoToolbox


class DQVideoEncoder: NSObject {
    
    var frameID:Int64 = 0
    var hasSpsPps = false
    var width: Int32 = 480
    var height:Int32 = 640
    var bitRate : Int32 = 480 * 640 * 3 * 4
    var fps : Int32 = 10
    var encodeQueue = DispatchQueue(label: "encode")
    var callBackQueue = DispatchQueue(label: "callBack")
    
    var encodeSession:VTCompressionSession!
    var encodeCallBack:VTCompressionOutputCallback?
    
    var videoEncodeCallback : ((Data)-> Void)?
    func videoEncodeCallback(block:@escaping (Data)-> Void){
        self.videoEncodeCallback = block
    }
    var videoEncodeCallbackSPSAndPPS :((Data,Data)->Void)?
    func videoEncodeCallbackSPSAndPPS(block:@escaping (Data,Data)->Void) {
        videoEncodeCallbackSPSAndPPS = block
    }
    
    init(width:Int32 = 480,height:Int32 = 640,bitRate : Int32? = nil,fps: Int32? = nil ) {
        
        self.width = width
        self.height = height
        self.bitRate = bitRate != nil ? bitRate! : 480 * 640 * 3 * 4
        self.fps = (fps != nil) ? fps! : 10
        super.init()
        
        setCallBack()
        initVideoToolBox()
        
    }
    //初始化编码器
    func initVideoToolBox() {
        
        //创建VTCompressionSession
        var bself = self
        let state = VTCompressionSessionCreate(allocator: nil, width: width, height: height, codecType: kCMVideoCodecType_H264, encoderSpecification: nil, imageBufferAttributes: nil, compressedDataAllocator: nil, outputCallback:encodeCallBack , refcon: &bself, compressionSessionOut: &self.encodeSession)
        
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
        let fpscf = CFNumberCreate(kCFAllocatorDefault, CFNumberType.intType, &fps)
        VTSessionSetProperty(encodeSession, key: kVTCompressionPropertyKey_ExpectedFrameRate, value: fpscf)
        
        //设置码率平均值，单位是bps。码率大了话就会非常清晰，但同时文件也会比较大。码率小的话，图像有时会模糊，但也勉强能看
        //码率计算公式参考笔记
        //        var bitrate = width * height * 3 * 4
        let bitrateAverage = CFNumberCreate(kCFAllocatorDefault, CFNumberType.intType, &bitRate)
        VTSessionSetProperty(encodeSession, key: kVTCompressionPropertyKey_AverageBitRate, value: bitrateAverage)
        
        //码率限制
        let bitRatesLimit :CFArray = [bitRate * 2,1] as CFArray
        VTSessionSetProperty(encodeSession, key: kVTCompressionPropertyKey_DataRateLimits, value: bitRatesLimit)
    }
    
    //开始编码
    func encodeVideo(sampleBuffer:CMSampleBuffer){
        encodeQueue.async {
            let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer)
            let time = CMTime(value: self.frameID, timescale: 1000)
            
            let state = VTCompressionSessionEncodeFrame(self.encodeSession, imageBuffer: imageBuffer!, presentationTimeStamp: time, duration: .invalid, frameProperties: nil, sourceFrameRefcon: nil, infoFlagsOut: nil)
            if state != 0{
                print("encode filure")
            }
        }
        
    }
    private func setCallBack()  {
        //编码完成回调
        encodeCallBack = {(outputCallbackRefCon, sourceFrameRefCon, status, flag, sampleBuffer)  in
            let encodepointer = outputCallbackRefCon?.bindMemory(to: DQVideoEncoder.self, capacity: 1)
            guard sampleBuffer != nil else {
                return
            }
            if let encoder = encodepointer?.pointee {
                encoder.callBackQueue.async {
                    /// 0. 原始字节数据 8字节
                    let buffer : [UInt8] = [0,0,0,1]
                    /// 1. [UInt8] -> UnsafeBufferPointer<UInt8>
                    let unsafeBufferPointer = buffer.withUnsafeBufferPointer {$0}
                    /// 2.. UnsafeBufferPointer<UInt8> -> UnsafePointer<UInt8>
                    let  unsafePointer = unsafeBufferPointer.baseAddress
                    guard let startCode = unsafePointer else {return}
                    
                    let attachArray = CMSampleBufferGetSampleAttachmentsArray(sampleBuffer!, createIfNecessary: false)

                    var strkey = kCMSampleAttachmentKey_NotSync
                    let dic = CFArrayGetValueAtIndex(attachArray, 0).bindMemory(to: CFDictionary.self, capacity: 1).pointee
                    let keyFrame = !CFDictionaryContainsKey(dic, &strkey);//没有这个键就意味着同步,就是关键帧

                    //  获取sps pps
                    if keyFrame && !encoder.hasSpsPps{
                        if let description = CMSampleBufferGetFormatDescription(sampleBuffer!){
                            var spsSize: Int = 0, spsCount :Int = 0,spsHeaderLength:Int32 = 0
                            var ppsSize: Int = 0, ppsCount: Int = 0,ppsHeaderLength:Int32 = 0
                            //var spsData:UInt8 = 0, ppsData:UInt8 = 0
                            
                            var spsDataPointer : UnsafePointer<UInt8>? = UnsafePointer(UnsafeMutablePointer<UInt8>.allocate(capacity: 0))
                            var ppsDataPointer : UnsafePointer<UInt8>? = UnsafePointer<UInt8>(bitPattern: 0)
                            let spsstatus = CMVideoFormatDescriptionGetH264ParameterSetAtIndex(description, parameterSetIndex: 0, parameterSetPointerOut: &spsDataPointer, parameterSetSizeOut: &spsSize, parameterSetCountOut: &spsCount, nalUnitHeaderLengthOut: &spsHeaderLength)
                            if spsstatus != 0{
                                print("sps失败")
                            }
                            
                            let ppsStatus = CMVideoFormatDescriptionGetH264ParameterSetAtIndex(description, parameterSetIndex: 1, parameterSetPointerOut: &ppsDataPointer, parameterSetSizeOut: &ppsSize, parameterSetCountOut: &ppsCount, nalUnitHeaderLengthOut: &ppsHeaderLength)
                            if ppsStatus != 0 {
                                print("pps失败")
                            }
                            
                            
                            if let spsData = spsDataPointer,let ppsData = ppsDataPointer{
                                var spsDataValue = Data(capacity: 4 + spsSize)
                                spsDataValue.append(startCode, count: 4)
                                spsDataValue.append(spsData, count: spsSize)
                                
                                var ppsDataValue = Data(capacity: 4 + ppsSize)
                                ppsDataValue.append(startCode, count: 4)
                                ppsDataValue.append(ppsData, count: ppsSize)
                                encoder.callBackQueue.async {
                                    encoder.videoEncodeCallbackSPSAndPPS!(spsDataValue, ppsDataValue)
                                }
                                
                               
                            }
                        }
                    }
                    
                    let dataBuffer = CMSampleBufferGetDataBuffer(sampleBuffer!)
                    var arr = [Int8]()
                    let pointer = arr.withUnsafeMutableBufferPointer({$0})
                    var dataPointer: UnsafeMutablePointer<Int8>?  = pointer.baseAddress
                    var totalLength :Int = 0
                    let blockState = CMBlockBufferGetDataPointer(dataBuffer!, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &totalLength, dataPointerOut: &dataPointer)
                    if blockState != 0{
                        print("获取data失败\(blockState)")
                    }
                    
                    //NALU
                    var offset :UInt32 = 0
                    //返回的nalu数据前四个字节不是0001的startcode(不是系统端的0001)，而是大端模式的帧长度length
                    let lengthInfoSize = 4
                    //循环写入nalu数据
                    while offset < totalLength - lengthInfoSize {
                        //获取nalu 数据长度
                        var naluDataLength:UInt32 = 0
                        memcpy(&naluDataLength, dataPointer! + UnsafeMutablePointer<Int8>.Stride(offset), lengthInfoSize)
                        //大端转系统端
                        naluDataLength = CFSwapInt32BigToHost(naluDataLength)
                        //获取到编码好的视频数据
                        var data = Data(capacity: Int(naluDataLength) + lengthInfoSize)
                        data.append(startCode, count: 4)
                        //转化pointer；UnsafeMutablePointer<Int8> -> UnsafePointer<UInt8>
                        let i8:UInt8 = UInt8(dataPointer?.pointee ?? 0)
                        let bufferPoint = [i8].withUnsafeBufferPointer{$0}
                        let naluUnsafePoint = bufferPoint.baseAddress!
                        data.append(naluUnsafePoint + UnsafePointer<UInt8>.Stride(offset) , count: Int(naluDataLength))
                        
                        encoder.callBackQueue.async {
                            encoder.videoEncodeCallback!(data)
                        }
                        
                        
                        offset += naluDataLength
                        
                    }
                    
                    
                }
            }
        }
    }
    
    
    deinit {
        if ((encodeSession) != nil) {
            VTCompressionSessionCompleteFrames(encodeSession, untilPresentationTimeStamp: .invalid)
            VTCompressionSessionInvalidate(encodeSession);
            
           
            encodeSession = nil;
        }
    }
    
}

//UnsafeMutableRawPointer?, UnsafeMutableRawPointer?, OSStatus, VTEncodeInfoFlags, CMSampleBuffer?
func staticCallBack(outputCallbackRefCon:UnsafeMutableRawPointer?, sourceFrameRefCon:UnsafeMutableRawPointer?, status:OSStatus, flag:VTEncodeInfoFlags, sampleBuffer:CMSampleBuffer?) {
    
}
