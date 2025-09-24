ffmpeg -f v4l2 -list_formats all -i /dev/video0


ffplay -f v4l2 -framerate 30 -video_size 1280x720 -i /dev/video0

  v4l2-ctl --list-formats-ext

