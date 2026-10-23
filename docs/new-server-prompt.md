# Prompt: set up Restreamer on a new server

Fill in the values in the first block. Then paste everything below the line into an AI agent that
works on the new server (for example Claude Code started in a terminal on that server).

---

You are setting up **Restreamer** (a self-hosted live-stream relay) on this Ubuntu server, using my two
GitHub repositories. Work step by step. Check before you change something, and explain what you are
about to do. Ask me before you change anything that already exists on this server (web server
configuration, firewall rules, other containers). Never write passwords or tokens into a git repository.
At the end, give me a short report: what you did, the URLs, and anything I still have to do.

## My values

```
DOMAIN        = restreamer.example.com      # (sub)domain for the Restreamer UI, DNS points to this server
INSTALL_DIR   = /opt/restreamer             # everything goes here
VARIANT       = cuda                        # cuda (driver >= 515) | cuda-ffmpeg8 (driver >= 570) | default (CPU only)
OBS           = on this server              # OBS streams to Restreamer via localhost
```

Facts about this server:
- Ubuntu with an NVIDIA GPU and an Intel Xeon E5-2699 v4 (22 cores, no integrated GPU, so no Intel
  QuickSync). Video encoding should use the NVIDIA GPU (NVENC).
- **Ports 80 and 443 are already used by websites** on this server. Restreamer must not take them.
  Its built-in Let's Encrypt only works with port 80, so it stays off. HTTPS for the domain comes
  from the existing web server (reverse proxy), see step 6.
- I expect ports 8080 and 8181 to be free; check it.

## Background

- **`Robin-qwerty/restreamer`** (branch `2.x`) is the Docker bundle. It contains no application
  code. It combines the UI, the datarhei core (Go: API, process manager, RTMP/SRT/HLS server)
  and an FFmpeg runtime into one image.
  - `Dockerfile`: the image.
  - `scripts/build-local.sh`: builds the image on this machine.
  - `docker-compose.yml` and `.env.example`: run the container.
  - `docs/vertical-setup.md`: user guide.
  - `AGENTS.md`: repo notes.
- **`Robin-qwerty/restreamer-ui`** (branch `main`) is my fork of the React UI. On top of upstream
  datarhei it adds:
  - a **vertical layout editor**: it builds a 9:16 channel from parts of a horizontal channel, encoded with NVENC
  - a **dual view**: horizontal and vertical channel side by side, each with its own publications
  - a **channel list on the right** grouped by status (live / receiving / problems / inactive)
  - a foldable **activity log** with readable errors and input stability
- **Streaming flow:**
  - OBS (same server) → `rtmp://localhost:1935/<channel-id>.stream` → horizontal channel.
  - The horizontal channel uses passthrough, so it isn't re-encoded and costs no GPU.
  - Its publications go to YouTube, Twitch, etc.
  - The vertical channel reads the horizontal one internally, crops, scales and composes it on the CPU, encodes it with NVENC, and has its own publications (TikTok, Shorts, ...).

## Steps

### 0. Pre-checks (read only)
1. Run `lsb_release -a`, `nproc`, `free -h`, and `df -h` on the disk that will hold `INSTALL_DIR` (at least 15 GB free for the images).
2. Run `nvidia-smi` and note the driver version.
   - Driver 570 or newer: `cuda-ffmpeg8` is possible. 515 or newer: `cuda`.
   - Keep `cuda` unless I asked for FFmpeg 8.
   - If there is no driver, stop and tell me (installing one needs a reboot).
3. Run `docker --version` and `docker compose version` (Compose v2 is needed).
4. Check the ports: `sudo ss -tlnpu | grep -E ':(80|443|8080|8181|1935|1936|6000)\b'`. Tell me which of 8080 / 8181 / 1935 / 1936 / 6000 are taken and by what.
5. Find out what serves 80/443: nginx, Apache, Caddy, Traefik, or another container (`docker ps`). Also find out whether certificates come from certbot (`sudo certbot certificates`) or from that web server itself.
6. Check whether a firewall is active (`sudo ufw status`).

### 1. Docker and the NVIDIA Container Toolkit
- Install Docker with the official script (`curl -fsSL https://get.docker.com | sudo sh`) if it is missing.
- Install the NVIDIA Container Toolkit if it is missing:
  ```sh
  curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey | sudo gpg --dearmor -o /usr/share/keyrings/nvidia-container-toolkit-keyring.gpg
  curl -s -L https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list | \
    sed 's#deb https://#deb [signed-by=/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg] https://#g' | \
    sudo tee /etc/apt/sources.list.d/nvidia-container-toolkit.list
  sudo apt-get update && sudo apt-get install -y nvidia-container-toolkit
  sudo nvidia-ctk runtime configure --runtime=docker
  sudo systemctl restart docker
  ```
  Restarting Docker restarts other containers. If other containers run on this server, ask me first.
- Test: `sudo docker run --rm --gpus all ubuntu nvidia-smi` must show the GPU.

### 2. Get the code
```sh
sudo mkdir -p INSTALL_DIR/src && sudo chown -R "$USER" INSTALL_DIR
git clone -b 2.x  https://github.com/Robin-qwerty/restreamer.git    INSTALL_DIR/src/restreamer
git clone -b main https://github.com/Robin-qwerty/restreamer-ui.git INSTALL_DIR/src/restreamer-ui
```

### 3. Build the image
```sh
cd INSTALL_DIR/src/restreamer
scripts/build-local.sh VARIANT ../restreamer-ui
```
- This builds `restreamer-ui:local` and `restreamer:VARIANT-local`. The first build takes a few minutes.
- If Docker Hub rate-limits the base image download, wait or `docker login`.

### 4. Configure and start
```sh
cd INSTALL_DIR
cp src/restreamer/docker-compose.yml .
cp src/restreamer/.env.example .env
```
Edit `INSTALL_DIR/.env`:
- `RESTREAMER_IMAGE=restreamer:VARIANT-local`
- Ports:
  - With a reverse proxy (step 6, preferred), keep the UI off the network: `RESTREAMER_HTTP=127.0.0.1:8080` and `RESTREAMER_HTTPS=127.0.0.1:8181`.
  - `RESTREAMER_RTMP=127.0.0.1:1935` if only OBS on this server publishes. Use `1935` if remote encoders should be able to publish too.
- If a port from step 0 is taken, use another host port, e.g. `RESTREAMER_HTTP=127.0.0.1:8090`. Then use that port everywhere below.

Start it with `docker compose up -d`. Then check:
- `docker compose logs --tail 50`: no errors.
- `docker exec restreamer nvidia-smi`: shows the GPU.
- `docker exec restreamer ffmpeg -hide_banner -encoders | grep nvenc`: lists `h264_nvenc`. Skip this for the `default` variant.
- `curl -s localhost:8080/api | head -c 200`: answers with JSON (datarhei-core).

### 5. First login
Open the UI in a browser. Until step 6 is done, use an SSH tunnel: `ssh -L 8080:localhost:8080 user@server`, then `http://localhost:8080/ui`.
1. Create the admin user. Tell me which username you set; I will choose the password myself.
2. Settings:
   - **Network → Public domain/s:** add `DOMAIN`.
   - Leave **Let's Encrypt certification** off, because port 80 is not available to Restreamer.
   - **RTMP:** RTMP server **on**. RTMPS stays off.
   - An **RTMP token** is optional but recommended if port 1935 is reachable from outside.
   - SRT: only if I need it.
3. Save and restart the application when the UI asks for it.

### 6. Domain and HTTPS without ports 80/443

**6a. Preferred: reverse proxy on the existing web server.** It already owns 80/443 and the certificates.
- Add one site for `DOMAIN` that forwards everything to `http://127.0.0.1:8080`.
- Show me the config before you activate it, and test the config before reloading the web server: `nginx -t` or `apachectl configtest`.

nginx (e.g. `/etc/nginx/sites-available/restreamer`):
```nginx
server {
    listen 80;
    server_name DOMAIN;
    location / { return 301 https://$host$request_uri; }
}

server {
    listen 443 ssl http2;
    server_name DOMAIN;
    ssl_certificate     /etc/letsencrypt/live/DOMAIN/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/DOMAIN/privkey.pem;

    client_max_body_size 0;          # file uploads (player site, loop videos)

    location / {
        proxy_pass http://127.0.0.1:8080;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_buffering off;         # live HLS
        proxy_read_timeout 3600s;
    }
}
```
- Get the certificate the same way the other sites do, e.g. `sudo certbot --nginx -d DOMAIN`, or `certbot certonly --webroot ...` if that is how the server works.

Apache:
- Modules: `proxy proxy_http headers ssl`.
- Use `ProxyPreserveHost On`, `ProxyPass / http://127.0.0.1:8080/` and `ProxyPassReverse / http://127.0.0.1:8080/`.
- Add `RequestHeader set X-Forwarded-Proto "https"`, with the same certificate lines as the other vhosts.

Caddy: `DOMAIN { reverse_proxy 127.0.0.1:8080 }`. Caddy gets the certificate itself.

Traefik or another proxy container: add a router for `DOMAIN` to `http://<host>:8080`. On Linux, `host.docker.internal` needs `extra_hosts: ["host.docker.internal:host-gateway"]`. In that case, bind `RESTREAMER_HTTP` to the Docker bridge IP instead of 127.0.0.1.

Result: the UI is at `https://DOMAIN/ui`. The UI builds every public link (HLS, player, RTMP) from the address in the browser, so the links automatically use `https://DOMAIN` without a port.

**6b. Fallback, only if I don't want the web server touched:**
- `http://DOMAIN:8080/ui` (no encryption): set `RESTREAMER_HTTP=8080`.
- Or HTTPS on 8181 with a certificate that already exists for `DOMAIN`, for example from certbot (also possible via DNS challenge).
  - The UI only offers HTTPS through Let's Encrypt, so this is set with environment variables in `INSTALL_DIR/docker-compose.yml`:
    ```yaml
        volumes:
            # add next to the existing volumes (certbot's live/ files link into archive/)
            - /etc/letsencrypt:/etc/letsencrypt:ro
        environment:
            # add next to the existing variables
            CORE_TLS_ENABLE: 'true'
            CORE_TLS_AUTO: 'false'
            CORE_TLS_CERT_FILE: /etc/letsencrypt/live/DOMAIN/fullchain.pem
            CORE_TLS_KEY_FILE: /etc/letsencrypt/live/DOMAIN/privkey.pem
    ```
  - Set `RESTREAMER_HTTPS=8181`, run `docker compose up -d`, and open `https://DOMAIN:8181/ui`.
  - Settings set this way are locked in the UI (marked "ENV").
  - Restart the container after each certificate renewal, e.g. with a certbot deploy hook `docker restart restreamer`.

### 7. Firewall
Only open what is needed, and ask me before changing ufw rules.
- With 6a: nothing new (80/443 are already open).
- With 6b: 8080 or 8181.
- 1935 (RTMP), 1936 (RTMPS) and 6000/udp (SRT): only for encoders outside this server. OBS on this server doesn't need them open.

### 8. Channels (show me how, or set them up with me)
1. **Horizontal channel:**
   - Channel list (camera button) → **+** → name → wizard → **RTMP server**.
   - In OBS (Settings → Stream → Custom): Server `rtmp://localhost:1935/` and Stream Key `<channel-id>.stream`. If a token is set, use `<channel-id>.stream?token=<token>`.
   - Don't use `rtmps://localhost`: the certificate is for `DOMAIN`, so OBS rejects it.
   - Keep video and audio on passthrough (copy).
2. **Vertical channel:** on the horizontal channel's page, click **Create vertical channel**, arrange the regions, choose **NVIDIA NVENC**, and save.
3. **Publications:** **+** in the Publications box of each channel. For YouTube, set the audio of the publication to **AAC** (fixes audio glitches). Switch publications on and off in the list or in the **Dual view**.
4. The **Activity** panel on the left shows the input stability and readable errors for each channel and its publications.

### 9. Updates and backups
Create `INSTALL_DIR/update.sh` and tell me about it:
```sh
#!/bin/sh
set -e
cd INSTALL_DIR/src/restreamer-ui && git pull
cd INSTALL_DIR/src/restreamer && git pull && scripts/build-local.sh VARIANT ../restreamer-ui
cd INSTALL_DIR && docker compose up -d && docker image prune -f
```
- An update restarts all streams, so don't run it while live.
- **Backup:** `INSTALL_DIR/config` holds the settings and all channels and publications. Back it up, e.g. with a daily `tar` to another disk. `INSTALL_DIR/data` holds the player site and uploads.
- To get datarhei updates into my forks later:
  ```sh
  git remote add upstream https://github.com/datarhei/restreamer-ui.git
  git fetch upstream
  git merge upstream/main
  ```
  Then push and rebuild. Do the same for `datarhei/restreamer` (branch `2.x`).

### 10. Final checks and report
- [ ] `docker compose ps` shows `restreamer` running with `restart: unless-stopped`.
- [ ] `docker exec restreamer nvidia-smi` works; NVENC is in the encoder list.
- [ ] The UI loads at the final URL (6a or 6b), and the login works.
- [ ] Settings: public domain = `DOMAIN`, RTMP on, Let's Encrypt off.
- [ ] A test stream from OBS appears in the horizontal channel. A test publication works, for example to an unlisted YouTube stream.
- [ ] The existing websites on 80/443 still work.
- [ ] Give me the report: URLs, the ports used, the files you changed outside `INSTALL_DIR`, and open points.

## Appendix A: performance checklist (OBS and server)

Go through this with me and only change what I agree to.

**OBS (Settings → Output, Advanced mode)**
- Encoder: **NVIDIA NVENC H.264** (not x264), Rate control **CBR**.
  - Bitrate: Twitch about 6000 kbit/s. YouTube 1080p60: 9000–12000 kbit/s.
  - All platforms receive the same stream (passthrough), so pick the lowest limit among them.
- **Keyframe interval 2 s** (needed by YouTube and Twitch; also keeps the vertical channel in sync).
- Preset: P5 (slow, good quality) or P4 if the GPU is busy. Tuning: High quality. Multipass: two passes (quarter resolution). Profile: high.
- Look-ahead: off. Psycho-visual tuning: on. B-frames: 2.
- Video: base canvas = output resolution (no scaling) and integer FPS (30 or 60). If you do scale, use the Bilinear or Area filter (cheap).
- Audio: 48 kHz, AAC 160 kbit/s. This also prevents most YouTube audio problems at the source.
- **View → Stats dock:**
  - "Frames missed due to rendering lag": the GPU is overloaded (scenes, browser sources).
  - "Skipped frames due to encoding lag": NVENC is overloaded; use a faster preset.
  - "Dropped frames (network)" should be 0 for localhost.
- Other OBS tips:
  - Disable the preview when you don't need it (right-click → Enable Preview).
  - Few and light browser sources, with "Use hardware acceleration in browser sources" on (Settings → Advanced).
  - Process priority: OBS only has this setting on Windows. On Linux, start OBS with a higher priority, e.g. `nice -n -5 obs` (needs sudo, or a `limits.conf` entry for the user).
  - Recording at the same time costs an extra NVENC session. Choose "(Use stream encoder)" as the recording encoder if possible.

**GPU and server**
- NVENC sessions: GeForce cards allow up to 8 at the same time with current drivers. OBS stream + vertical channel (+ recording) = 2–3.
- Watch the encoder load live with `nvidia-smi dmon -s u` (the `enc` column). Keep the NVIDIA driver up to date.
- The vertical channel crops and scales on the CPU, which is cheap on 22 cores. If the GPU is ever full, switch the vertical channel to x264 (CPU) in the layout editor; the Xeon can handle 1080x1920 at 30 fps with x264.
- CPU governor: `performance` instead of `powersave`, e.g. `sudo apt install cpufrequtils` and `GOVERNOR="performance"` in `/etc/default/cpufrequtils`. Check: `cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor`.
- **Upload bandwidth** = the sum of all publications. Example: horizontal 6 Mbit/s to 2 platforms plus vertical 6 Mbit/s to 2 platforms = 24 Mbit/s. Keep about 30% spare; test with `speedtest`.
- Use Ethernet. If streams drop, check the Activity panel: "Input stability" and the events show restarts, dropped frames and errors per publication.

## Appendix B: useful commands and troubleshooting

```sh
cd INSTALL_DIR
docker compose ps                      # status
docker compose logs -f --tail 100      # core log (live)
docker compose restart                 # restart (stops all streams briefly)
docker exec -it restreamer bash        # shell in the container (ubuntu-based variants)
docker exec restreamer nvidia-smi      # GPU visible in the container?
nvidia-smi dmon -s u                   # GPU/encoder load on the host
docker image ls | grep restreamer      # built images
```

| Problem | Cause / fix |
|---|---|
| `could not select device driver "nvidia"` | The NVIDIA Container Toolkit is missing or Docker was not restarted (step 1). |
| NVENC error, "OpenEncodeSessionEx failed", "driver does not support the required nvenc API version" | The driver is too old for the variant: use `cuda` instead of `cuda-ffmpeg8`, or update the driver. |
| `port is already allocated` | Another service uses the port: change it in `.env` (step 4). |
| Channel shows "Waiting for input" | OBS isn't streaming, or uses the wrong stream key or token. The Activity panel shows the reason. |
| OBS can't connect to `rtmps://localhost:1936` | The TLS certificate is for the domain: use `rtmp://localhost:1935` on the same server. |
| Vertical channel has high delay | The RTMP server is off: enable it in the settings. The layout editor shows which input it uses. |
| Vertical channel error | The horizontal channel must run first. See the Activity panel or "Raw process log". |
| UI via the domain loads, but links show `:8080` | The page was opened via `:8080` instead of the domain: always open `https://DOMAIN/ui`. |
| YouTube audio crackles | Set the audio of that publication to AAC (48 kHz), or AAC 48 kHz in OBS. |
