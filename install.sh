#!/bin/bash

set -e

# Default settings
NETDRIVE=${NETDRIVE:-~/.netdrive}

KERNEL_NDFUSE=${KERNEL_NDFUSE:-kernel-ndfuse}
KERNEL_NDFUSE_REPO=${KERNEL_NDFUSE_REPO:-netdrive/${KERNEL_NDFUSE}}
KERNEL_NDFUSE_REMOTE=${KERNEL_NDFUSE_REMOTE:-https://github.com/${KERNEL_NDFUSE_REPO}.git}
KERNEL_NDFUSE_BRANCH=${KERNEL_NDFUSE_BRANCH:-master}
KERNEL_DRIVER_PATH=/lib/modules/$(uname -r)/kernel/drivers/

INSTALLER=${INSTALLER:-installer}
INSTALLER_REPO=${INSTALLER_REPO:-netdrive/${INSTALLER}}
INSTALLER_REMOTE=${INSTALLER_REMOTE:-https://github.com/${INSTALLER_REPO}.git}
INSTALLER_BRANCH=${INSTALLER_BRANCH:-master}

command_exists() {
	command -v "$@" >/dev/null 2>&1
}

error() {
	echo ${RED}"Error: $@"${RESET} >&2
}

underline() {
	echo "$(printf '\033[4m')$@$(printf '\033[24m')"
}

setup_color() {
	# Only use colors if connected to a terminal
	if [ -t 1 ]; then
		RED=$(printf '\033[31m')
		GREEN=$(printf '\033[32m')
		YELLOW=$(printf '\033[33m')
		BLUE=$(printf '\033[34m')
		BOLD=$(printf '\033[1m')
		RESET=$(printf '\033[m')
	else
		RED=""
		GREEN=""
		YELLOW=""
		BLUE=""
		BOLD=""
		RESET=""
	fi
}

check_git() {
	command_exists git || {
		error "git is not installed"
		exit 1
	}
}

create_tmp_dir() {
	mkdir -p $NETDRIVE
	rm -rf $NETDRIVE/$KERNEL_NDFUSE
	rm -rf $NETDRIVE/$INSTALLER
}

clone_repo() {
	# Prevent the cloned repository from having insecure permissions. Failing to do
	# so causes compinit() calls to fail with "command not found: compdef" errors
	# for users with insecure umasks (e.g., "002", allowing group writability). Note
	# that this will be ignored under Cygwin by default, as Windows ACLs take
	# precedence over umasks except for filesystems mounted with option "noacl".
	umask g-w,o-w

	echo "${BLUE}Cloning Repositories...${RESET}"

	git clone -c core.eol=lf -c core.autocrlf=false \
		-c fsck.zeroPaddedFilemode=ignore \
		-c fetch.fsck.zeroPaddedFilemode=ignore \
		-c receive.fsck.zeroPaddedFilemode=ignore \
		--depth=1 --branch "$KERNEL_NDFUSE_BRANCH" "$KERNEL_NDFUSE_REMOTE" "$NETDRIVE"/${KERNEL_NDFUSE} || {
		error "git clone of netdrive ndfuse repo failed"
		exit 1
	}
	sudo cp -R "${NETDRIVE}"/${KERNEL_NDFUSE} ${KERNEL_DRIVER_PATH}

	git clone -c core.eol=lf -c core.autocrlf=false \
		-c fsck.zeroPaddedFilemode=ignore \
		-c fetch.fsck.zeroPaddedFilemode=ignore \
		-c receive.fsck.zeroPaddedFilemode=ignore \
		--depth=1 --branch "$INSTALLER_BRANCH" "$INSTALLER_REMOTE" "$NETDRIVE"/${INSTALLER} || {
		error "git clone of netdrive utility repo failed"
		exit 1
	}

	echo
}

setup_fuse() {

	if grep -qw "^ndfuse" /proc/modules; then
		echo -n "Unloading ndfuse module"
		if ! sudo rmmod ndfuse >/dev/null 2>&1; then
			echo " failed!"
			exit 1
		else
			echo "."
		fi
	else
		echo "ndfuse module not loaded."
	fi

	cd ${KERNEL_DRIVER_PATH}
	make clean
	make

	if ! grep -qw "^ndfuse" /etc/modules; then
		sudo sh -c 'echo "ndfuse" >> /etc/modules'
	fi

	sudo insmod ndfuse.ko
	sudo depmod -a
}

setup_libfuse() {
	sudo mkdir -p /usr/local/bin/
	sudo mkdir -p /usr/local/sbin/
	sudo cp -f ${NETDRIVE}/${INSTALLER}/libndfuse/util/fusermount3 /usr/local/bin/fusermount3
	sudo cp -f ${NETDRIVE}/${INSTALLER}/libndfuse/util/mount.fuse3 /usr/local/sbin/mount.fuse3
	sudo chmod 4755 /usr/local/bin/fusermount3
}

setup_netdrive() {
	if command_exists wget; then
		wget -O NetDrive.AppImage "https://www.netdrive.net/download/linux/?beta"
	elif command_exists curl; then
		curl -o NetDrive.AppImage -L "https://www.netdrive.net/download/linux/?beta"
	else
		echo "curl or wget is required to download NetDrive."
		return 1
	fi
	chmod +x NetDrive.AppImage
	return 0
}

main() {

    setup_color
	check_git

	create_tmp_dir
	clone_repo

	pushd .
	setup_fuse
	popd

	setup_libfuse

	if setup_netdrive; then
		printf "$GREEN"
		cat <<-'EOF'
			_   _      _   ____       _           
			| \ | | ___| |_|  _ \ _ __(_)_   _____ 
			|  \| |/ _ \ __| | | | '__| \ \ / / _ \
			| |\  |  __/ |_| |_| | |  | |\ V /  __/
			|_| \_|\___|\__|____/|_|  |_| \_/ \___|  now installed!
											
		EOF
		printf "$RESET"
	else
		echo "Failed to install NetDrive."
	fi
}

main "$@"
