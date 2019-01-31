Arch Linux reinstall
====================

This provides a "simple" way to (re)install my Arch Linux Laptop(s).

## Warning

The disk you say to setup to will be completely formatted.

## Steps

### Prepare

- download [the iso](https://www.archlinux.org/download/) somewhere
- put the iso on a usb or cd
- boot your system with the iso

### Basic live env setup

#### keyboard setup

If you need to change your keyboard layout like me, first thing to run is

```
$ loadkeys be-latin1
```

Or `loadkeys` with your keymap.

#### wifi

Configure wifi if needed

```
$ wifi-menu
```
#### prepare usb 'key' device

If you have an empty device you also have to format it.

```
$ mkfs.ext2 -L keydrive /dev/sdb1
```

Make the `/media/usb` directory.

```
$ mkdir -p /media/usb
```

And then mount the usb 'key' device to `/media/usb`

```
$ mount /dev/sdb1 /media/usb
```

#### get the archlinux-reinstall repo

We need git to get the archlinux-reinstall repo

```
$ pacman -Sy git
```

clone the repo

```
$ git clone https://github.com/BlackIkeEagle/archlinux-reinstall.git
```

Go into the new folder and run 'a' installer

```
$ cd archlinux-reinstall
$ ./install.sh
```

If you run as described above you will get a minimal install of archlinux with my preferred kernel and configuration.

#### reboot and post install

Reboot and remove the installation medium.

when logged in as root, first run `./post-install-first-run.sh`. And then continue configuring whatever you want.

### installer types

- install.sh: minimal install
- install-plasma.sh: installation with common packages for plasma desktop
- install-deepin.sh: installation with common packages for deepin desktop
- install-i3.sh: installation with common packages for i3 wm
- install-fluxbox.sh: installation with common packages for fluxbox wm

By default there is a user 'ike', this you have to change manually in the `post-install-first-run.sh` script.
