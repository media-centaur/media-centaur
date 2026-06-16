---
title: Updates, retention & running as a service
nav_label: Updates & service
part: Operating it
slug: updates-retention-and-service
order: 21
---
The operational essentials: how the app updates itself, how it keeps its database from
growing forever, and how it runs as a background service.

## Updates

After the first install you never touch the installer again. The app checks GitHub for new
releases on a schedule and on demand (Settings → System). Updating downloads the release for
your platform, verifies its checksum, swaps it into place, and restarts the service — so an
update is a button, not a chore.

You can enable automatic checking and automatic installing. Auto-install waits until nothing
is playing before applying, so it never interrupts a viewing; manual checks always just
present the update and let you decide.

## Retention

A daily sweep ages out data on stated schedules so the database stays bounded. Each subsystem
declares its own policy, visible on the Status page (what's kept, last run, how much removed):

| Data | Kept |
|---|---|
| Update staging files | 2 days |
| Completed image-download queue entries | 7 days |
| Diagnostic events | 30 days |
| Pursuit & tracking activity logs | 90 days |
| Resolved error incidents | 90 days after resolving |
| **Watch history** | **Forever** |

Watch history is the deliberate exception — kept forever, pruned only by you, one entry at a
time (see [Watch history & progress](/guide/watch-history-and-progress)).

## Running as a service

The recommended setup runs the app as a systemd *user* service — it starts with your session,
restarts on crash, and logs to the journal.

```sh
systemctl --user status media-centaur     # is it running?
systemctl --user restart media-centaur    # restart (e.g. after a TOML change)
journalctl --user -u media-centaur -f      # follow the logs
```

Settings → System also has Restart and Stop buttons. For playback, the service needs your
desktop session's display environment so mpv can open a window; the unit imports it
automatically and starts after the graphical session. If you upgraded an old install and mpv
won't open, restart the service once so it picks that up.

> [!TIP]
> Two details worth knowing. To keep the app running when you're *not* logged in, enable
> lingering once: `loginctl enable-linger $USER`. And the app binds to localhost with **no
> authentication** — to reach it from another room, put a reverse proxy in front and add your
> own access control (a VPN or LAN-only firewall); don't expose it raw. Full setup in the
> [Running as a Service](https://github.com/media-centaur/media-centaur/wiki/Running-as-a-Service)
> wiki page.
