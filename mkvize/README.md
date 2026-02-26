README.md 
# mkvize-with-subs
Batch remux videos into **MKV** and embed the **matching SRT** subtitle file **1:1 by filename** — with **no re-encode** (no quality loss).
This is a tiny “factory line” workflow:
- Standardize files into MKV
- Attach soft subtitles (SRT) so you don’t need to burn-in subs
- Keep playback flexible (Plex/mpv/etc.)
## What it does
For each video file in a folder:
- Writes an output MKV to `OutputDir` (default: `<VideoDir>\mkvized_out\`)
- If a matching `.srt` exists, embeds it as a subtitle track
- Uses `ffmpeg` stream copy (`-c copy`) so video/audio are NOT re-encoded
✅ **No quality loss** (no re-encoding)  
✅ **Fast** (remux + subtitle mux)  
✅ **One subtitle per video** (correct 1:1 matching)  
✅ **Batchable** (entire seasons / libraries)
## What it does NOT do
- ❌ It does **not** burn subtitles into the video.
- ❌ It does **not** re-encode video/audio.
- ❌ It does **not** attach every subtitle to every video.
## Requirements
- Windows PowerShell 5.1+ or PowerShell 7+
- `ffmpeg` in your PATH
Install ffmpeg (Windows):
```powershell
winget install Gyan.FFmpeg
