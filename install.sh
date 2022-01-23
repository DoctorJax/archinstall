#!/bin/bash

clear
echo -ne "
-------------------------------------
     ▛▀▖      ▐         ▜▘
     ▌ ▌▞▀▖▞▀▖▜▀ ▞▀▖▙▀▖ ▐▝▀▖▚▗▘
     ▌ ▌▌ ▌▌ ▖▐ ▖▌ ▌▌  ▌▐▞▀▌▗▚
     ▀▀ ▝▀ ▝▀  ▀ ▝▀ ▘  ▝▘▝▀▘▘ ▘
-------------------------------------
Yes, I definitely know what I'm doing
-------------------------------------
"
# Making downloads faster
pacman --noconfirm -Sy reflector
reflector --latest 20 --sort rate --save /etc/pacman.d/mirrorlist --protocol https --download-timeout 5
sed -i "s/^#ParallelDownloads = 5$/ParallelDownloads = 15/" /etc/pacman.conf
pacman --noconfirm -Sy archlinux-keyring

# Setting keymap and time stuff
loadkeys us
timedatectl set-ntp true

# Drive selection
clear
lsblk
echo -ne "Drive to install to: "
read -r drive
cfdisk "$drive"

# Partition slection
clear
lsblk "$drive"

echo -ne "Enter EFI partition: "
read -r efipartition

read -r -p "Should we format the EFI partition? [y/n]: " answer
if [[ $answer = y ]]; then
    echo "There it goes then"
    mkfs.fat -F 32 "$efipartition"
else
    echo "Alright, skipping EFI partition formatting"
fi

echo -ne "Enter swap partition: "
read -r swappartition
mkswap "$swappartition"

echo -ne "Enter root/home partition: "
read -r rootpartition
mkfs.ext4 "$rootpartition"

# Mounting filesystems
mount "$rootpartition" /mnt
mkdir -p /mnt/boot
mount "$efipartition" /mnt/boot
swapon "$swappartition"

# Initial Install
pacstrap /mnt base base-devel linux linux-firmware
genfstab -U /mnt > /mnt/etc/fstab

# Moving the rest of the script to the install and chrooting
sed '1,/^###part2$/d' install.sh > /mnt/install2.sh
chmod +x /mnt/install2.sh
arch-chroot /mnt ./install2.sh
exit



###part2



#!/bin/bash

# Setting things so things are faster
pacman -S --noconfirm sed
sed -i "s/^#ParallelDownloads = 5$/ParallelDownloads = 15/" /etc/pacman.conf

makej=$(nproc)
makel=$(expr "$(nproc)" + 1)
sed -i "s/^#MAKEFLAGS=\"-j2\"$/MAKEFLAGS=\"-j$makej -l$makel\"" /etc/makepkg.conf

# Setting timezone stuff
ln -sf /usr/share/zoneinfo/US/Eastern /etc/localtime
hwclock --systohc

# Setting language stuff
echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf
echo "KEYMAP=us" > /etc/vconsole.conf

# Setting hostname
clear
echo -ne "Enter your desired hostname: "
read -r hostname
echo "$hostname" > /etc/hostname

echo "127.0.0.1      localhost" >> /etc/hosts
echo "::1            localhost" >> /etc/hosts
echo "127.0.1.1      $hostname.localdomain $hostname" >> /etc/hosts

# First making of initcpio
mkinitcpio -P

# Installing systemd-boot instead of grub for speed
bootctl install

# Systemd-boot pacman hook
mkdir -p /etc/pacman.d/hooks

echo "[Trigger]" >> /etc/pacman.d/hooks/100-systemd-boot.hook
echo "Type = Package" >> /etc/pacman.d/hooks/100-systemd-boot.hook
echo "Operation = Upgrade" >> /etc/pacman.d/hooks/100-systemd-boot.hook
echo "Target = systemd" >> /etc/pacman.d/hooks/100-systemd-boot.hook
echo "" >> /etc/pacman.d/hooks/100-systemd-boot.hook
echo "[Action]" >> /etc/pacman.d/hooks/100-systemd-boot.hook
echo "Description = Gracefully upgrading systemd-boot..." >> /etc/pacman.d/hooks/100-systemd-boot.hook
echo "When = PostTransaction" >> /etc/pacman.d/hooks/100-systemd-boot.hook
echo "Exec = /usr/bin/systemctl restart systemd-boot-update.service" >> /etc/pacman.d/hooks/100-systemd-boot.hook

# Setting loader and entry files for systemd-boot
mkdir -p /boot/loader/entries

echo "timeout 0" >> /boot/loader/loader.conf
echo "default arch" >> /boot/loader/loader.conf
echo "editor 0" >> /boot/loader/loader.conf

clear
lsblk
echo -ne "Enter root partition: "
read -r rootpart

echo "title Arch Linux" >> /boot/loader/entries/arch.conf
echo "linux /vmlinuz-linux" >> /boot/loader/entries/arch.conf
echo "initrd /initramfs-linux.img" >> /boot/loader/entries/arch.conf
echo "options root=$(blkid | grep $rootpart | awk '{print $2}' | sed 's/"//g') loglevel=3 audit=0 quiet rw" >> /boot/loader/entries/arch.conf

# Installing everything I think I need
pacman -S xorg-server xorg-xinit xorg-xkill xorg-xsetroot xorg-xbacklight xorg-xprop xorg-xrandr xorg-xinput \
    bspwm sxhkd dunst pavucontrol acpi lxappearance papirus-icon-theme arc-gtk-theme rofi python-pywal nitrogen \
    zsh zsh-syntax-highlighting zsh-autosuggestions alacritty ranger nnn mpd playerctl mpc ncmpcpp nemo \
    neofetch lolcat htop bashtop keepassxc yubioath-desktop vim neovim emacs nodejs libreoffice \
    hunspell hunspell-en_us hyphen hyphen-en libmythes mythes-en gimp krita feh firefox starship dust bat exa \
    xfce4-clipman-plugin discord-canary rclone rsync maim xdotool noto-fonts noto-fonts-emoji \
    ttf-joypixels ttf-font-awesome sxiv mpv numlockx imagemagick fzf gzip p7zip libzip zip unzip yt-dlp xclip \
    dhcpcd networkmanager pamixer paprefs pulseaudio pulseaudio-alsa sudo man-db git base-devel krita kdenlive inkscape

systemctl enable NetworkManager.service
echo "%wheel ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers

# Settings up a user
clear
echo -ne "Enter username for new user: "
read -r username
useradd -m -g users -G wheel -s /bin/zsh "$username"
passwd "$username"

# Setting up my dotfiles for that user
sed '1,/^###part3$/d' install2.sh > /home/$username/installdots.sh
chown $username:users /home/$username/installdots.sh
chmod +x /home/$username/installdots.sh
su -c /home/$username/installdots.sh -s /bin/bash $username
exit



###part3



#!/bin/bash

cd $HOME

git clone --separate-git-dir=$HOME/.dotfiles https://github.com/DoctorJax/.dotfiles.git tmpdotfiles
rsync --recursive --verbose --exclude '.git' tmpdotfiles/ $HOME/
rm -r tmpdotfiles
/usr/bin/git --git-dir=$HOME/.dotfiles/ --work-tree=$HOME config --local status.showUntrackedFiles no

git clone https://gitlab.com/dwt1/wallpapers.git

git clone https://aur.archlinux.org/paru.git
cd paru
makepkg -si

paru -S polybar awesome-git awesome-freedesktop-git picom-jonaburg-git mpd-mpris pfetch nerd-fonts-complete brave-bin mailspring

exit
