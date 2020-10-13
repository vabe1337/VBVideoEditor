Usage: 

            isPortrait = editor.getVideoOrientation(track: track, url: videoURL).orientation == .portrait
            
            //isFilterEnabled - set true if you applied CIFilter
            //playerVideoFrame - playerLayer.videoRect
            editor.renderVideo(videoURL: videoURL, isPortrait: isPortrait, viewForAttach: imageView, isFilterEnabled: self.isFilterEnabled, playerVideoFrame: playerVideoFrame, onComplete: { [weak self] url in
                self?.outputURL = url
                completion()
            })
