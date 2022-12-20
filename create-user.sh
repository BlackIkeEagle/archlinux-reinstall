#!/usr/bin/env bash

if [[ -n "$1" ]]; then
    name="$1"
    shift
fi

if [[ -n "$1" ]]; then
    fullname="$1"
    shift
fi

if [[ -z "$name" ]]; then
    name=ike
fi
if [[ -z "$fullname" ]]; then
    fullname="Ike Devolder"
fi

# groups
groups="--member-of=wheel"
if which docker > /dev/null 2>&1; then
    groups="$groups --member-of=docker"
fi
if which virtualbox > /dev/null 2>&1; then
    groups="$groups --member-of=vboxusers"
fi

homectl create "$name" \
    --real-name="$fullname" \
    --shell="/usr/bin/zsh" \
    $groups \

ssh_auth_key=''
if [[ "$name" == "vagrant" ]]; then
    ssh_auth_key=$(curl --location https://raw.github.com/mitchellh/vagrant/master/keys/vagrant.pub)
    homectl update "$name" \
        --ssh-authorized-keys="$ssh_auth_key"
fi

homectl passwd "$name"

# subuid / subgid
touch /etc/subuid
touch /etc/subgid
usermod --add-subuids 100000-165535 "$name"
usermod --add-subgids 100000-165535 "$name"

if [[ "$name" == "vagrant" ]]; then
    echo "$name ALL=(root) NOPASSWD: ALL" > /etc/sudoers.d/$name
else
    echo "$name ALL=(ALL) ALL" > /etc/sudoers.d/$name
fi
chmod u=rw,g=r,o= /etc/sudoers.d/$name
