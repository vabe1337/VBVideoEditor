//
//  VideoEditor.swift
//  BlackDot
//
//  Created by Ivan Nezdropa on 06.04.2020.
//  Copyright © 2020 CookieDev. All rights reserved.
//

import UIKit
import AVKit
import Photos

class VideoEditor {
    
    static let shared = VideoEditor()
    
    private init(){}
    
    struct Constants {
        static let frameDuration = CMTime(value: 1, timescale: 30)
        static let pathExtension = "mov"
        static let renderSize: CGSize = CGSize(width: 720, height: 1280)
    }
    
    
    func renderVideo(videoURL: URL, isPortrait: Bool, viewForAttach: UIView?, isFilterEnabled: Bool, playerVideoFrame: CGRect, onComplete: @escaping (URL?) -> Void) {
        let asset = AVURLAsset(url: videoURL)
        let composition = AVMutableComposition()
        
        guard
            let compositionTrack = composition.addMutableTrack(
                withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid),
            let assetTrack = asset.tracks(withMediaType: .video).first
            else {
                LogManager.shared.printLog(title: "Error", content: "Something is wrong with the asset.")
                onComplete(nil)
                return
        }
        
        do {
            let timeRange = CMTimeRange(start: .zero, duration: asset.duration)
            try compositionTrack.insertTimeRange(timeRange, of: assetTrack, at: .zero)
            
            if let audioAssetTrack = asset.tracks(withMediaType: .audio).first,
                let compositionAudioTrack = composition.addMutableTrack(
                    withMediaType: .audio,
                    preferredTrackID: kCMPersistentTrackID_Invalid) {
                try compositionAudioTrack.insertTimeRange(
                    timeRange,
                    of: audioAssetTrack,
                    at: .zero)
            }
        } catch {
            LogManager.shared.printLog(title: "Error", content: error.localizedDescription)
            onComplete(nil)
            return
        }
        
        compositionTrack.preferredTransform = assetTrack.preferredTransform
        
        let videoSize = getCalculatedVideoSize(track: assetTrack, isFilterEnabled: isFilterEnabled, videoURL: videoURL)

        let backgroundLayer = getBackgroundLayer(isPortrait: isPortrait, videoSize: videoSize)
        
        let videoLayer = getVideoLayer(isPortrait: isPortrait, videoSize: videoSize)
        
        let overlayLayer = getOverlayLayer(viewForAttach: viewForAttach, videoSize: videoSize, isPortrait: isPortrait)

        
        let outputLayer = CALayer()
        outputLayer.frame = CGRect(origin: .zero, size: isPortrait ? videoSize : Constants.renderSize)
        outputLayer.addSublayer(backgroundLayer)
        outputLayer.addSublayer(videoLayer)
        outputLayer.addSublayer(overlayLayer)
        
        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = isPortrait ? videoSize : Constants.renderSize
        videoComposition.frameDuration = Constants.frameDuration
        videoComposition.animationTool = AVVideoCompositionCoreAnimationTool(
            postProcessingAsVideoLayer: videoLayer,
            in: outputLayer)
        
        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(
            start: .zero,
            duration: composition.duration)
        videoComposition.instructions = [instruction]
        let layerInstruction = compositionLayerInstruction(
            for: compositionTrack, isPortrait: isPortrait, playerVideoFrame: playerVideoFrame, videoSize: videoSize)
        instruction.layerInstructions = [layerInstruction]
        guard let export = AVAssetExportSession(
            asset: composition,
            presetName: AVAssetExportPreset1280x720)
            else {
                LogManager.shared.printLog(title: "Error", content: "Cannot create export session.")
                onComplete(nil)
                return
        }
        
        let videoName = UUID().uuidString
        let exportURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(videoName)
            .appendingPathExtension(Constants.pathExtension)
        
        export.videoComposition = videoComposition
        export.outputFileType = .mov
        export.shouldOptimizeForNetworkUse = true
        export.outputURL = exportURL
        let duration = asset.duration.seconds
        let scale = Int64(duration * 0.4)
        export.fileLengthLimit = 1048576 * scale
        export.exportAsynchronously {
            DispatchQueue.main.async {
                switch export.status {
                case .completed:
                    VideoEditor.checkFileSize(sizeUrl: exportURL, message: "The file size of the compressed file is: ")
                    onComplete(exportURL)
                default:
                    LogManager.shared.printLog(title: "Error", content: "Something went wrong during export.")
                    LogManager.shared.printLog(title: "Error", content: export.error?.localizedDescription ?? "unknown error")
                    onComplete(nil)
                    break
                }
            }
        }
        
        
    }
    
    private func getCalculatedVideoSize(track: AVAssetTrack, isFilterEnabled: Bool, videoURL: URL) -> CGSize {
        let videoInfo = getVideoOrientation(track: track, url: videoURL)
        let videoSize: CGSize
        if videoInfo.orientation == .portrait, !isFilterEnabled {
            videoSize = CGSize(
                width: videoInfo.size.width,
                height: videoInfo.size.height)
        } else {
            videoSize = track.naturalSize
        }
        return videoSize
    }
    
    private func getOverlayLayer(viewForAttach: UIView?, videoSize: CGSize, isPortrait: Bool) -> CALayer {
        let overlayLayer = CALayer()
        
        overlayLayer.frame = CGRect(origin: .zero, size: isPortrait ? videoSize : Constants.renderSize)
        
        if let viewForAttach = viewForAttach {
            let watermarkLayer = CALayer()
            watermarkLayer.contents = viewForAttach.getImage().cgImage
            watermarkLayer.contentsGravity = .resizeAspectFill
            if isPortrait {
                watermarkLayer.frame = CGRect(origin: .zero, size: videoSize)
            } else {
                watermarkLayer.frame = CGRect(origin: .zero, size: Constants.renderSize)
            }
            
            overlayLayer.addSublayer(watermarkLayer)
        }
        
        return overlayLayer
    }
    
    private func getBackgroundLayer(isPortrait: Bool, videoSize: CGSize) -> CALayer {
        let backgroundLayer = CALayer()
        backgroundLayer.backgroundColor = UIColor.black.cgColor
        backgroundLayer.frame = CGRect(origin: .zero, size: isPortrait ? videoSize : Constants.renderSize)
        return backgroundLayer
    }
    
    private func getVideoLayer(isPortrait: Bool, videoSize: CGSize) -> CALayer {
        let videoLayer = CALayer()
        videoLayer.frame = CGRect(origin: .zero, size: videoSize)
 
        if !isPortrait {
            videoLayer.setAffineTransform(CGAffineTransform(scaleX: Constants.renderSize.width / videoSize.width, y: Constants.renderSize.height / videoSize.height))
            var updatedFrame = videoLayer.frame
            updatedFrame.origin.y = .zero
            updatedFrame.origin.x = .zero
            videoLayer.frame = updatedFrame
        }
        return videoLayer
    }
    
    func getVideoOrientation(track: AVAssetTrack, url: URL) -> (orientation: UIInterfaceOrientation, size: CGSize) {

        let size = track.naturalSize
        
        guard let img = VideoEditor.thumbnailImage(videoURL: url) else {
            return (.portrait, size)
        }
        
        if img.size.width > img.size.height {
            return (.landscapeLeft, img.size)
        } else {
            return (.portrait, img.size)
        }

    }
    private func compositionLayerInstruction(for track: AVCompositionTrack, isPortrait: Bool, playerVideoFrame: CGRect, videoSize: CGSize) -> AVMutableVideoCompositionLayerInstruction {
        let instruction = AVMutableVideoCompositionLayerInstruction(assetTrack: track)
        if isPortrait {
            instruction.setTransform(track.preferredTransform, at: .zero)
        } else {
            let scale = Constants.renderSize.height / UIScreen.main.bounds.height
            let transform: CGAffineTransform = CGAffineTransform(scaleX: Constants.renderSize.width / track.naturalSize.width, y: (playerVideoFrame.height * scale) / track.naturalSize.height)
            let translate = CGAffineTransform(translationX: .zero, y: ((Constants.renderSize.height - (playerVideoFrame.height*scale))) / 2)
            instruction.setTransform(track.preferredTransform.concatenating(transform).concatenating(translate), at: .zero)
        }
        return instruction
    }
    
    static func thumbnailImage(videoURL: URL?) -> UIImage? {
        if let videoURL = videoURL {
            let asset = AVURLAsset(url: videoURL)
            let assetIG = AVAssetImageGenerator(asset: asset)
            assetIG.appliesPreferredTrackTransform = true
            assetIG.apertureMode = AVAssetImageGenerator.ApertureMode.encodedPixels
            
            let cmTime = CMTime(seconds: 0, preferredTimescale: 60)
            let thumbnailImageRef: CGImage
            do {
                thumbnailImageRef = try assetIG.copyCGImage(at: cmTime, actualTime: nil)
            } catch let error {
                LogManager.shared.printLog(title: "Error", content: error.localizedDescription)
                return nil
            }
            
            return UIImage(cgImage: thumbnailImageRef)
        }
        return nil
    }
    
    static func compressVideo(videoURL: URL?, completion:@escaping((URL?) -> ())) {
        if let videoURL = videoURL {
            let videoName = UUID().uuidString
            let exportURL = URL(fileURLWithPath: NSTemporaryDirectory())
                .appendingPathComponent(videoName)
                .appendingPathExtension("mov")
            let asset = AVURLAsset(url: videoURL)
            let exporter = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetHighestQuality)
            exporter?.outputFileType = .mov
            exporter?.outputURL = exportURL
            let duration = asset.duration.seconds
            let scale = Int64(duration * 0.4)
            exporter?.fileLengthLimit = 1048576 * scale
            exporter?.shouldOptimizeForNetworkUse = true
            exporter?.exportAsynchronously(completionHandler: {() -> () in
                if exporter?.status == .completed {
                    VideoEditor.checkFileSize(sizeUrl: exportURL, message: "The file size of the compressed file is: ")
                    let outputURL: URL? = exporter?.outputURL
                    completion(outputURL)
                }
            })
        } else {
            completion(nil)
        }
    }
    
    @discardableResult
    static func checkFileSize(sizeUrl: URL?, message: String) -> Double {
        if let sizeUrl = sizeUrl {
            let data = try? Data(contentsOf: sizeUrl)
            let sizeMB = (Double(data?.count ?? 0) / 1048576.0)
            print(message, sizeMB)
            return sizeMB
        }
        return 0.0
    }
    
}
