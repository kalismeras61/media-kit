#if canImport(Flutter)
import Flutter
#elseif canImport(FlutterMacOS)
import FlutterMacOS
#endif

import AVKit
import MediaPlayer
import Foundation
#if os(iOS)
import UIKit
#endif


#if os(iOS)
@available(iOS 15.0, *)
public class VideoOutputPIP: VideoOutput, AVPictureInPictureSampleBufferPlaybackDelegate, AVPictureInPictureControllerDelegate {
    private var bufferDisplayLayer: AVSampleBufferDisplayLayer = AVSampleBufferDisplayLayer()
    private var pipController: AVPictureInPictureController? = nil
    private var videoFormat: CMVideoFormatDescription? = nil
    private var notificationCenter: NotificationCenter {
        return .default
    }

    private var airPlayPickerView: AVRoutePickerView? = nil
    private var airPlayDelegate: AVRoutePickerViewDelegate? = nil
  
    override init(handle: Int64, configuration: VideoOutputConfiguration, registry: FlutterTextureRegistry, textureUpdateCallback: @escaping VideoOutput.TextureUpdateCallback) {
        super.init(handle: handle, configuration: configuration, registry: registry, textureUpdateCallback: textureUpdateCallback)
        notificationCenter.addObserver(self, selector: #selector(appWillResignActive(_:)), name: UIApplication.willResignActiveNotification, object: nil)
        notificationCenter.addObserver(self, selector: #selector(appWillEnterForeground(_:)), name: UIApplication.willEnterForegroundNotification, object: nil)
        // app did enter background
        notificationCenter.addObserver(self, selector: #selector(appDidEnterBackground(_:)), name: UIApplication.didEnterBackgroundNotification, object: nil)
    }
  
    deinit {
        notificationCenter.removeObserver(self)
    }



     @objc private func appDidEnterBackground(_ notification: NSNotification) {
        NSLog("appDidEnterBackground")
        worker.enqueue {
            self.switchToSoftwareRendering()
        }
    }
    
  
    @objc private func appWillEnterForeground(_ notification: NSNotification) {
        NSLog("appWillEnterForeground")
        worker.enqueue {
            self.switchToHardwareRendering()
        }
    }
  
    @objc private func appWillResignActive(_ notification: NSNotification) {
        NSLog("appWillResignActive")
        if pipController == nil {
            return
        }

        if UIDevice.current.userInterfaceIdiom == .pad {
            return
        }

        if pipController!.canStartPictureInPictureAutomaticallyFromInline || pipController!.isPictureInPictureActive {
            switchToSoftwareRendering()
            return
        }

        var isPaused: Int8 = 0
        mpv_get_property(handle, "pause", MPV_FORMAT_FLAG, &isPaused)
    
        if isPaused == 1 {
            return
        }
    
        mpv_command_string(handle, "cycle pause")
    }

    override public func refreshPlaybackState() {
        pipController?.invalidatePlaybackState()
    }

    override public func enablePictureInPicture() -> Bool {
        if pipController != nil {
            return true
        }
    
        do {
            try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
            try? AVAudioSession.sharedInstance().setActive(true)
        } catch {
            NSLog("AVAudioSession set category failed")
        }
    
        bufferDisplayLayer.frame = CGRect(x: 0, y: 0, width: 1, height: 1)
        bufferDisplayLayer.opacity = 0
        bufferDisplayLayer.videoGravity = .resizeAspect
        bufferDisplayLayer.contentsScale = UIScreen.main.scale 
    
        let contentSource = AVPictureInPictureController.ContentSource(sampleBufferDisplayLayer: bufferDisplayLayer, playbackDelegate: self)
        pipController = AVPictureInPictureController(contentSource: contentSource)
        pipController!.delegate = self
    
        let controller = UIApplication.shared.keyWindow?.rootViewController
        controller?.view.layer.addSublayer(bufferDisplayLayer)
    
        return true
    }

    override public func disablePictureInPicture() {
        if bufferDisplayLayer.superlayer != nil {
            bufferDisplayLayer.removeFromSuperlayer()
        }
        pipController = nil
    }

    // Setting up the AirPlay button
     // Setting up the AirPlay button
      override public func setupAirPlayButton() -> Bool {
          DispatchQueue.main.async {
              var buttonView: UIView? = nil
              let buttonFrame = CGRect(x: 0, y: 0, width: 44, height: 44)
              NSLog("AirPlay button setup")
              
              // Using AVRoutePickerView for iOS 11+
              if #available(iOS 11.0, *) {
                  NSLog("AirPlay button setup iOS 11+")
                  self.airPlayPickerView = AVRoutePickerView(frame: buttonFrame)
                  self.airPlayPickerView?.activeTintColor = .systemBlue
                  self.airPlayPickerView?.tintColor = .white
                  buttonView = self.airPlayPickerView
              } else {
                  // For older iOS versions, fallback to MPVolumeView
                  let tempView = MPVolumeView(frame: buttonFrame)
                  tempView.showsVolumeSlider = false
                  buttonView = tempView
              }

              // Set the delegate for additional event handling (optional)
              self.airPlayDelegate = AirPlayDelegate()
              self.airPlayPickerView?.delegate = self.airPlayDelegate
              
              // Use UIApplication.shared.windows to get the key window correctly
              guard let controller = UIApplication.shared.windows.first(where: { $0.isKeyWindow })?.rootViewController else {
                  NSLog("AirPlay button setup failed - rootViewController not found")
                  return
              }

              // Add AirPlayPickerView to the view hierarchy
              if let airPlayPicker = self.airPlayPickerView {
                  airPlayPicker.translatesAutoresizingMaskIntoConstraints = false
                  controller.view.addSubview(airPlayPicker)
                  NSLog("AirPlay button added") // Debugging purposes 

                  NSLayoutConstraint.activate([
                      airPlayPicker.trailingAnchor.constraint(equalTo: controller.view.trailingAnchor, constant: -16),
                      airPlayPicker.bottomAnchor.constraint(equalTo: controller.view.bottomAnchor, constant: -50),
                      airPlayPicker.widthAnchor.constraint(equalToConstant: 40),
                      airPlayPicker.heightAnchor.constraint(equalToConstant: 40)
                  ])
              }
          }
          return true
      }

    
    // New delegate to handle AVRoutePickerView events
    class AirPlayDelegate: NSObject, AVRoutePickerViewDelegate {
        func routePickerViewWillBeginPresentingRoutes(_ routePickerView: AVRoutePickerView) {
            NSLog("AirPlay picker presented.")
        }

        func routePickerViewDidEndPresentingRoutes(_ routePickerView: AVRoutePickerView) {
            NSLog("AirPlay picker dismissed.")
        }
    }

    override public func enableAutoPictureInPicture() -> Bool {
        if enablePictureInPicture() {
            pipController?.canStartPictureInPictureAutomaticallyFromInline = true
            return true
        }
        return false
    }

    override public func disableAutoPictureInPicture() {
        if pipController != nil {
            pipController?.canStartPictureInPictureAutomaticallyFromInline = false
        }
    }

    override public func enterPictureInPicture() -> Bool {
        if enablePictureInPicture() {
            pipController?.startPictureInPicture()
            return true
        }
        return false
    }
  
    override func _updateCallback() {
        super._updateCallback()
        if pipController != nil {
            let pixelBuffer = texture.copyPixelBuffer()?.takeUnretainedValue()
            if pixelBuffer == nil {
                return
            }
      
            var sampleBuffer: CMSampleBuffer?
            if videoFormat == nil || !CMVideoFormatDescriptionMatchesImageBuffer(videoFormat!, imageBuffer: pixelBuffer!)  {
                videoFormat = nil
                let err = CMVideoFormatDescriptionCreateForImageBuffer(allocator: kCFAllocatorDefault, imageBuffer: pixelBuffer!, formatDescriptionOut: &videoFormat)
                if (err != noErr) {
                    NSLog("Error at CMVideoFormatDescriptionCreateForImageBuffer \(err)")
                }
            }
      
            var sampleTimingInfo = CMSampleTimingInfo(duration: .invalid, presentationTimeStamp: CMTime(seconds: CACurrentMediaTime(), preferredTimescale: 100), decodeTimeStamp: .invalid)
            let err = CMSampleBufferCreateForImageBuffer(allocator: nil, imageBuffer: pixelBuffer!, dataReady: true, makeDataReadyCallback: nil, refcon: nil, formatDescription: videoFormat!, sampleTiming: &sampleTimingInfo, sampleBufferOut: &sampleBuffer)
            if err == noErr {
                bufferDisplayLayer.enqueue(sampleBuffer!)
            } else {
                NSLog("Error at CMSampleBufferCreateForImageBuffer \(err)")
            }
        }
    }

    public override func dispose() {
        super.dispose()
        disablePictureInPicture()
        airPlayPickerView?.removeFromSuperview()
        airPlayDelegate = nil // Cleanup the delegate to avoid memory leaks
    }

    public func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, setPlaying playing: Bool) {
        var isPaused: Int8 = 0
        mpv_get_property(handle, "pause", MPV_FORMAT_FLAG, &isPaused)
    
        if playing == (isPaused == 0) {
            return
        }
    
        mpv_command_string(handle, "cycle pause")
    }
  
    public func pictureInPictureControllerTimeRangeForPlayback(_ pictureInPictureController: AVPictureInPictureController) -> CMTimeRange {
        var position: Double = 0
        mpv_get_property(handle, "time-pos", MPV_FORMAT_DOUBLE, &position)
    
        var duration: Double = 0
        mpv_get_property(handle, "duration", MPV_FORMAT_DOUBLE, &duration)
    
        return CMTimeRange(
            start: CMTime(seconds: CACurrentMediaTime() - position, preferredTimescale: 100),
            duration: CMTime(seconds: duration, preferredTimescale: 100)
        )
    }

    public func pictureInPictureControllerIsPlaybackPaused(_ pictureInPictureController: AVPictureInPictureController) -> Bool {
        var isPaused: Int8 = 0
        mpv_get_property(handle, "pause", MPV_FORMAT_FLAG, &isPaused)
        return isPaused == 1
    }

    public func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, didTransitionToRenderSize newRenderSize: CMVideoDimensions) {
        // Handle render size changes
    }
  
    public func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, skipByInterval skipInterval: CMTime, completion completionHandler: @escaping () -> Void) {
        mpv_command_string(handle, "seek \(skipInterval.seconds)")
        completionHandler()
    }
  
    public func pictureInPictureController(_ pictureInPictureController: AVPictureInPictureController, failedToStartPictureInPictureWithError error: Error) {
        NSLog("pictureInPictureController error: \(error)")
    }

    public func pictureInPictureControllerWillStopPictureInPicture(_ pictureInPictureController: AVPictureInPictureController) {
    }
}
#endif
