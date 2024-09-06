#if canImport(Flutter)
import Flutter
#elseif canImport(FlutterMacOS)
import FlutterMacOS
#endif

import AVKit

#if os(iOS)
import UIKit
#endif


@available(iOS 15.0, *)
public class VideoOutputPIP: VideoOutput, AVPictureInPictureSampleBufferPlaybackDelegate, AVPictureInPictureControllerDelegate {
    
    private var bufferDisplayLayer: AVSampleBufferDisplayLayer = AVSampleBufferDisplayLayer()
    private var pipController: AVPictureInPictureController? = nil
    private var videoFormat: CMVideoFormatDescription? = nil
    
    // Initialization
    override init(handle: Int64, configuration: VideoOutputConfiguration, registry: FlutterTextureRegistry, textureUpdateCallback: @escaping VideoOutput.TextureUpdateCallback) {
        super.init(handle: handle, configuration: configuration, registry: registry, textureUpdateCallback: textureUpdateCallback)
        
        // Notification observers for app state
        NotificationCenter.default.addObserver(self, selector: #selector(appWillResignActive(_:)), name: UIApplication.willResignActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(appWillEnterForeground(_:)), name: UIApplication.willEnterForegroundNotification, object: nil)
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    @objc private func appWillResignActive(_ notification: NSNotification) {
        // Handle app going to background
        if pipController != nil, pipController!.isPictureInPictureActive {
            switchToSoftwareRendering()
        }
    }
    
    @objc private func appWillEnterForeground(_ notification: NSNotification) {
        worker.enqueue {
            self.switchToHardwareRendering()
        }
    }
    
    override public func refreshPlaybackState() {
        pipController?.invalidatePlaybackState()
    }

    override public func enablePictureInPicture() -> Bool {
        if pipController == nil {
            bufferDisplayLayer.frame = CGRect(x: 0, y: 0, width: 1, height: 1)
            bufferDisplayLayer.opacity = 0
            bufferDisplayLayer.videoGravity = .resizeAspect
            
            let contentSource = AVPictureInPictureController.ContentSource(sampleBufferDisplayLayer: bufferDisplayLayer, playbackDelegate: self)
            pipController = AVPictureInPictureController(contentSource: contentSource)
            pipController?.delegate = self
            
            UIApplication.shared.keyWindow?.rootViewController?.view.layer.addSublayer(bufferDisplayLayer)
        }
        return true
    }
    
    override public func disablePictureInPicture() {
        bufferDisplayLayer.removeFromSuperlayer()
        pipController = nil
    }
    
    override public func enterPictureInPicture() -> Bool {
        if let pipController = pipController {
            pipController.startPictureInPicture()
            return true
        }
        return false
    }
    
    override func _updateCallback() {
        // Custom update callback for PiP
        super._updateCallback()
        
        if pipController != nil, let pixelBuffer = texture.copyPixelBuffer()?.takeUnretainedValue() {
            var sampleBuffer: CMSampleBuffer?
            if videoFormat == nil || !CMVideoFormatDescriptionMatchesImageBuffer(videoFormat!, imageBuffer: pixelBuffer) {
                videoFormat = nil
                let err = CMVideoFormatDescriptionCreateForImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: pixelBuffer, formatDescriptionOut: &videoFormat)
                if err != noErr {
                    NSLog("Error creating video format description: \(err)")
                }
            }
            var timingInfo = CMSampleTimingInfo(duration: .invalid, presentationTimeStamp: CMTime(seconds: CACurrentMediaTime(), preferredTimescale: 100), decodeTimeStamp: .invalid)
            let err = CMSampleBufferCreateForImageBuffer(allocator: nil, imageBuffer: pixelBuffer, dataReady: true, makeDataReadyCallback: nil, refcon: nil, formatDescription: videoFormat!, sampleTiming: &timingInfo, sampleBufferOut: &sampleBuffer)
            if err == noErr {
                bufferDisplayLayer.enqueue(sampleBuffer!)
            }
        }
    }

    // MARK: - AVPictureInPictureSampleBufferPlaybackDelegate
    public func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, setPlaying playing: Bool) {
        var isPaused: Int8 = 0
        mpv_get_property(handle, "pause", MPV_FORMAT_FLAG, &isPaused)
        if playing != (isPaused == 0) {
            mpv_command_string(handle, "cycle pause")
        }
    }

    public func pictureInPictureControllerTimeRangeForPlayback(_ pictureInPictureController: AVPictureInPictureController) -> CMTimeRange {
        var position: Double = 0
        mpv_get_property(handle, "time-pos", MPV_FORMAT_DOUBLE, &position)
        
        var duration: Double = 0
        mpv_get_property(handle, "duration", MPV_FORMAT_DOUBLE, &duration)
        
        return CMTimeRange(start: CMTime(seconds: CACurrentMediaTime() - position, preferredTimescale: 100), duration: CMTime(seconds: duration, preferredTimescale: 100))
    }

    public func pictureInPictureControllerIsPlaybackPaused(_ pictureInPictureController: AVPictureInPictureController) -> Bool {
        var isPaused: Int8 = 0
        mpv_get_property(handle, "pause", MPV_FORMAT_FLAG, &isPaused)
        return isPaused == 1
    }

    public func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, skipByInterval skipInterval: CMTime, completion completionHandler: @escaping () -> Void) {
        mpv_command_string(handle, "seek \(skipInterval.seconds)")
        completionHandler()
    }
    
    public func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, failedToStartPictureInPictureWithError error: Error) {
        NSLog("Picture in Picture failed with error: \(error)")
    }

    public func pictureInPictureControllerWillStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
        // Handle stopping PiP
    }
}
#endif
