//
//  ViewController.swift
//  VideoH264
//
//  Created by dzq_mac on 2020/7/29.
//  Copyright © 2020 dzq_mac. All rights reserved.
//

import UIKit
import AVFoundation
import Photos
import VideoToolbox

class ViewController: UIViewController {

    //按钮
    var captureButton:UIButton!
    var recodButton:UIButton!
    
    
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .white
        captureButton = UIButton(frame: CGRect(x: 10, y: view.bounds.size.height - 60, width: 150, height: 50))
        captureButton.backgroundColor = .gray
        captureButton.center.y = view.center.y
        captureButton.setTitle("拍照", for: .normal)
        captureButton.addTarget(self, action: #selector(capture(btn:)), for: .touchUpInside)
        view.addSubview(captureButton)
        
        recodButton = UIButton(frame: CGRect(x: view.bounds.size.width - 160, y: view.bounds.size.height - 60, width: 150, height: 50))
        recodButton.backgroundColor = .gray
        recodButton.center.y = view.center.y
        recodButton.setTitle("视频编码H264", for: .normal)
        recodButton.addTarget(self, action: #selector(recordAction(btn:)), for: .touchUpInside)
        view.addSubview(recodButton)
        
    }
    
    @objc func recordAction(btn:UIButton){
        self.navigationController?.pushViewController(VideoViewController(), animated: true)
        
    }
    @objc func capture(btn:UIButton){
       
        
        self.navigationController?.pushViewController(TakephotoViewController(), animated: true)
    
    }
    
}

