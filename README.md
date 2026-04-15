# tg-seek

Seek forward/backward in Telegram Desktop music playback via MPRIS2/DBus.

Works with official Telegram Desktop on Linux — no patching, no injection.
Telegram exposes `org.mpris.MediaPlayer2.Player` on the session bus when playing audio.

## Requirements

- Linux with DBus session bus
- `gdbus` (usually pre-installed with GLib)
- Telegram Desktop running and playing a track

## Install

```bash
git clone <this-repo> ~/tg-seek
chmod +x ~/tg-seek/tg-seek.sh
```

## CLI usage

```bash
./tg-seek.sh forward 5      # seek forward 5 seconds
./tg-seek.sh backward 5     # seek backward 5 seconds
./tg-seek.sh to 90           # jump to 1:30
./tg-seek.sh status          # show current track info
```

Short aliases work too:

```bash
./tg-seek.sh f 10            # forward 10s
./tg-seek.sh b 10            # backward 10s
./tg-seek.sh + 5             # forward 5s
./tg-seek.sh - 5             # backward 5s
./tg-seek.sh s               # status
```

Default seek is 5 seconds when amount is omitted.

### Status output

```
Track:    tripperbeats — Feel Good Inc - DnB
Status:   Playing
Position: 0:29 / 2:19
CanSeek:  true
```

## xremap integration

Add to your xremap config (e.g. `config-i3.yml`) under the Telegram binding:

```yaml
- name: Telegram binding
  application:
    only: [TelegramDesktop]
  remap:
    C-Shift-i:
      launch: ["bash", "-c", "/path/to/tg-seek.sh backward 5"]
    C-Shift-o:
      launch: ["bash", "-c", "/path/to/tg-seek.sh forward 5"]
```

This gives you `Ctrl+Shift+I` / `Ctrl+Shift+O` for seek backward/forward,
pairing with typical `Ctrl+I` / `Ctrl+O` for prev/next track.

## sxhkd integration

```
# Telegram seek (global hotkeys)
super + bracketleft
    /path/to/tg-seek.sh backward 5

super + bracketright
    /path/to/tg-seek.sh forward 5
```

## i3/sway bindings

```
bindsym $mod+Shift+bracketleft  exec /path/to/tg-seek.sh backward 5
bindsym $mod+Shift+bracketright exec /path/to/tg-seek.sh forward 5
```

## How it works

Telegram Desktop implements the [MPRIS2](https://specifications.freedesktop.org/mpris-spec/latest/) spec
and registers as `org.mpris.MediaPlayer2.TelegramDesktop` on the DBus session bus.

The script calls:
- `Player.Seek(offset_µs)` for relative seeking (forward/backward)
- `Player.SetPosition(track_id, position_µs)` for absolute seeking

Internally, Telegram handles this by restarting its streaming instance at the new position
(`Instance::finishSeeking` → `Streaming::Player::play(options)` → `av_seek_frame`).

## License

Public domain. Do whatever you want.
