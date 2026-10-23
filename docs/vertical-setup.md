# Horizontal + vertical streaming with one OBS output

This fork adds a **vertical layout editor** and a **dual view** to Restreamer:

- OBS sends one horizontal stream to Restreamer.
- Restreamer composes a vertical (1080x1920) channel from it: you choose which parts of the
  horizontal picture to show and where, e.g. gameplay at the bottom and the facecam on top.
- Both channels have their own publications (YouTube, Twitch, TikTok via RTMP, ...).
- The dual view shows both players, stats and publication lists side by side.

The vertical channel is encoded on the NVIDIA GPU (NVENC). Cropping and scaling run on the CPU.
The horizontal channel can stay in passthrough, so it costs almost nothing.

UI code: [Robin-qwerty/restreamer-ui](https://github.com/Robin-qwerty/restreamer-ui).

Setting up a new server with an AI agent? [`new-server-prompt.md`](new-server-prompt.md) is a
ready-to-paste prompt with every step below, including a reverse proxy for servers whose ports 80/443
are already in use, and a performance checklist for OBS and the server.

## 1. Build the image

**On the server (recommended):** clone both repositories next to each other and run the build script:

```sh
git clone -b 2.x  https://github.com/Robin-qwerty/restreamer.git
git clone -b main https://github.com/Robin-qwerty/restreamer-ui.git
cd restreamer && scripts/build-local.sh cuda ../restreamer-ui
```

This builds `restreamer:cuda-local`. Variants: `cuda`, `cuda-ffmpeg8` and `default` (see below).

**Or with GitHub Actions (GHCR):**

1. In this repository on GitHub, open **Actions** → **Build custom image (GHCR)** → **Run workflow**.
   - `ui_ref`: the branch of the UI fork to build (`main`, or a feature branch).
   - `variant`:
     - `cuda` uses FFmpeg 6.1 and needs NVIDIA driver 515 or newer. This is the recommended choice.
     - `cuda-ffmpeg8` uses FFmpeg 8.1 and needs NVIDIA driver 570 or newer.
     - `default` is CPU only.
2. When the run is done, the image is at `ghcr.io/robin-qwerty/restreamer:cuda-latest`.
   - The first time, open the package page on GitHub (your profile → **Packages** → `restreamer`)
     and set its visibility to **public**. Otherwise you have to `docker login ghcr.io` on the server.

The workflow only shows up in the Actions tab once it is on the default branch (`2.x`).

## 2. Prepare the Ubuntu server

```sh
# NVIDIA driver (if not installed yet)
sudo ubuntu-drivers install
sudo reboot

# Docker
curl -fsSL https://get.docker.com | sudo sh

# NVIDIA Container Toolkit
curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | \
  sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
  sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list
sudo apt-get update && sudo apt-get install -y nvidia-container-toolkit
sudo nvidia-ctk runtime configure --runtime=docker
sudo systemctl restart docker

# check that containers can see the GPU
sudo docker run --rm --gpus all ubuntu nvidia-smi
```

## 3. Start Restreamer

Copy `docker-compose.yml` and `.env.example` (as `.env`) from this repository to a folder on the server.
In `.env`:
- Set `RESTREAMER_IMAGE`: `restreamer:cuda-local` from the build script, or the GHCR image.
- Adjust the ports if needed. For example, `RESTREAMER_HTTP=127.0.0.1:8080` keeps the UI off the network when a reverse proxy (nginx, Apache, Caddy) serves it under your domain.

Then:

```sh
sudo docker compose up -d
```

Open `http://<server>:8080/ui` and set up the admin login.

## 4. Horizontal channel (from OBS)

1. Create a channel. In the wizard choose **RTMP server** as the source.
2. Copy the RTMP address the wizard shows into OBS (**Settings → Stream → Custom**).
   - OBS runs on the same server, so you can replace the host name with `127.0.0.1`.
3. Recommended OBS output settings:
   - Keyframe interval: **2 s**.
   - Encoder: NVENC.
   - Resolution: 1920x1080 at 30 or 60 fps.
4. Finish the wizard. Choose **passthrough** (copy) for video and audio unless you need re-encoding.
   For YouTube audio glitches, set the audio encoding on that publication (or in the channel) to AAC.

### OBS on the same server (localhost)

The address the wizard shows uses your public domain, e.g.
`rtmps://restreamer.example.net:1936/<channel-id>.stream`. On the same machine you don't need the
domain:

- **Use plain RTMP:** `rtmp://localhost:1935/<channel-id>.stream` (or `127.0.0.1`).
  - If you set an RTMP token in the settings, add it the same way the wizard shows it.
  - The RTMP server on port 1935 stays on even when RTMPS is enabled.
  - Nothing else needs to change: Restreamer only looks at the stream name (`<channel-id>.stream`), not at the host OBS connects to.
- **`rtmps://localhost:1936/...` does not work.** The TLS certificate is issued for your domain, so OBS rejects the connection to `localhost`. Encryption isn't needed when the traffic never leaves the machine.
- **Pulling a stream** that already runs on this server (for example another program's RTMP or SRT output): choose **Network source** and enter its address, e.g. `rtmp://127.0.0.1:1935/live/stream`.
- **"Virtual source"** in the advanced setup is only a test-pattern generator (color bars and similar). It can't receive a stream, so it isn't needed for any of this.

## 5. Vertical channel

1. On the horizontal channel's page click **Create vertical channel**.
2. Arrange the layout. The left side is the source picture (the channel snapshot, refresh it with
   the ↻ button) and the right side is the 9:16 output with a live preview.
   - Drag a colored box on the **source** to choose what a region shows. Drag the corners to crop.
   - Drag the same box on the **output** to choose where it appears and how big it is.
   - **Keep proportions** stops the picture from being stretched.
   - **+** adds a region (up to 4). The copy icon duplicates one, so you can show the same source
     several times with a different crop. Regions lower in the list are drawn on top.
   - Presets: *Center crop*, *Facecam + gameplay*, *Full frame*.
   - Background: a blurred copy of the source, or a solid color.
   - Encoder: **NVIDIA NVENC** (GPU) or x264 (CPU). Also set the bitrate, framerate and audio
     (passthrough, AAC or none).
3. Click **Save**. The vertical channel starts and the dual view opens.

Saving a changed layout restarts the vertical stream, so it drops out for a few seconds.
Change the layout before you go live, or accept the short gap.

## 6. Dual view and publications

The **Dual view** button on either channel's page opens both channels side by side.

- Each side has its own publication list. Add publications with **+** and switch them on and off.
- Typical setup:
  - Horizontal → YouTube, Twitch.
  - Vertical → TikTok, YouTube Shorts live, Instagram (via RTMP).

## 7. Channel list and activity log

### Channel list

The camera button (top right) opens and closes the channel list on the right.

- Channels are grouped and ordered by status:
  - **green, Live:** a publication is streaming. A red warning sign on the dot means another publication of that channel is failing.
  - **light purple, Receiving:** the input is there, nothing is published.
  - **red, Problems:** the input is lost or waiting, or a publication is failing.
  - **gray, Inactive:** the channel is stopped.
- Hover over a dot to see the details.
- The list uses one column while all channels fit on the screen, and two smaller columns otherwise. The fullscreen button shows all channels in a large grid.
- Snapshots of channels with an input refresh every minute. Channels without input show a gray "No input" tile.

### Activity log

The **Activity** panel on the left of a channel page folds in and out with the arrow, or with the "Activity" tab on the left edge. It shows:

- **Status:** the state of the input, uptime, bitrate, FPS and speed, and how many publications are live or failing.
- **Input stability:**
  - Stable / Some issues / Unstable, based on bitrate jumps, dropped frames, speed (real-time or not) and restarts in the last hour
  - small graphs of bitrate and FPS for the last 5 minutes
- **Events** of the channel and its publications:
  - A failed attempt is one line, e.g. "Stopped: Connection refused ×4".
  - Click an event for an explanation, a tip, and the original FFmpeg message.
  - Filter with *All / Problems / Publications*.
- **Raw logs:** *Raw process log* and *Process report* open the original logs.

On the dual page, the panel can show both channels in one **combined** log (the default), **side by side**, or only one of them. The panel remembers whether it was open.

## Troubleshooting

- **The vertical channel shows an error:** the horizontal channel has to be running. Check
  **Process details** on the vertical channel. With NVENC errors, run `nvidia-smi` inside the
  container (`docker exec -it restreamer nvidia-smi`) and check the driver version against the
  variant you built.
- **High delay on the vertical channel:** make sure the RTMP server is enabled
  (`CORE_RTMP_ENABLE=true`, already set in `docker-compose.yml`) and that the horizontal channel
  has RTMP enabled. The layout editor tells you which input it uses.
