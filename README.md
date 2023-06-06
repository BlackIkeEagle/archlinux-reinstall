Arch Linux reinstall
====================

This provides a "simple" way to (re)install my Arch Linux Laptop(s).

## Warning

The selected disk for installation will be completely wiped.

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

#### network

https://wiki.archlinux.org/title/Installation_guide#Connect_to_the_internet

#### get the archlinux-reinstall repo

We need git to get the archlinux-reinstall repo

```
$ pacman -Sy git
```

clone the repo

```
$ git clone https://github.com/BlackIkeEagle/archlinux-reinstall.git
```

Go into the new folder and run 'a' installer (see [installer types](#installer-types))

```
$ cd archlinux-reinstall
$ ./install.sh
```

If you run as described above you will get a minimal install of archlinux with my preferred kernel and configuration.

#### reboot and post install

When you have chosen to install with a root user and by doing so want to make
use of `systemd-homed` you can use the `./create-admin-user.sh` or
`./create-user.sh` scripts to generate a normal user for you to use.

### installer types

- install.sh: minimal install
- install-plasma.sh: installation with common packages for plasma desktop
