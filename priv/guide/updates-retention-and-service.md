---
title: Updates, retention & running as a service
part: Operating it
slug: updates-retention-and-service
order: 19
---
The last things to know are operational: how the app updates itself, how it keeps its own
database from growing forever, and how it runs as a background service on your machine.

## Updates

After the first install, you never touch the installer again. The app checks GitHub for new
releases on a schedule (and on demand from Settings → System), and tells you when one's
available. Updating downloads the release for your platform, verifies its checksum, swaps it
into place, and restarts the service — so an update is a button, not a chore. Tags are
validated and download URLs are fixed templates, so a bad release name can't redirect the
update somewhere else.

You can turn on automatic checking, and automatic installing. Auto-install is considerate:
it waits until nothing is playing before it applies an update, so it never interrupts a
viewing. Manual checks always just present the update and let you decide.

## Retention

Left alone, an app like this would accumulate forever — finished download records, resolved
error reports, diagnostic logs, stale queue entries. Media Centaur runs a daily sweep that
ages those out on stated schedules, so the database stays bounded. Each subsystem declares
its own policy, and you can see them on the Status page: what's kept, for how long, when the
last sweep ran, and how much it removed.

The deliberate exception is your **watch history**, which is kept forever — see
[Watch history & progress](/guide/watch-history-and-progress). Everything else is swept;
history is yours to prune by hand, one entry at a time.

## Running as a service

The recommended setup runs the app as a systemd *user* service. It starts with your session,
restarts on crash, and logs to the journal. The everyday commands:

```sh
systemctl --user status media-centaur     # is it running?
systemctl --user restart media-centaur    # restart (e.g. after a TOML change)
journalctl --user -u media-centaur -f     # follow the logs
```

Settings → System also has Restart and Stop buttons if you'd rather not use a terminal.

One thing matters for playback: the service needs your desktop session's display environment
so mpv can open a window. The unit imports it automatically and starts after the graphical
session — but if you upgraded an old install and mpv won't open, restart the service once so
it picks that up.

> [!TIP]
> Two operational details worth knowing. To keep the app running when you're *not* logged in,
> enable lingering once: `loginctl enable-linger $USER`. And the app binds to localhost only,
> with **no authentication** — if you want to reach it from another room, put a reverse proxy
> in front and add your own access control (a VPN or LAN-only firewall); don't expose it raw.

In short: updates are a verified, one-button download-and-restart (optionally automatic when
idle) after the first install; a daily sweep keeps the database bounded with everything but
watch history aging out on schedules you can see; and it runs as a systemd user service —
localhost-only, so add your own front door if you reach it remotely. Full details in the
[Running as a Service](https://github.com/media-centaur/media-centaur/wiki/Running-as-a-Service)
wiki page.
