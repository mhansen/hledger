#!/bin/bash -e
# Easy hledger installation script for POSIX systems.
# Uses cabal if installed and stack is not, 
# or stack, which it will install if needed (or if --force is used).
# Requires bash and some other POSIX tools.
# This is based on get-stack.sh which is copyright (c) 2015-2017, Stack contributors.

usage() {
  cat <<HERE
hledger-install.sh [-f|--force] [-v|--verbose] [-s|--status] [--version] [-h|--help]

Installs the current release of hledger and related tools as reliably and 
quickly as possible on any POSIX system, using cabal (if installed and 
stack is not) or stack (installing it when needed or if --force is used). 
With --status, just lists the currently installed hledger tools.
Usage:

 curl -sSLO http://hledger.org/hledger-install.sh  # or wget -qO- ...
 less hledger-install.sh       # security review
 bash [-x] hledger-install.sh  # to see commands being run, add -x 

or if you prefer convenience to security:

 curl -sSL http://hledger.org/hledger-install.sh | bash

Once hledger is installed, if you keep hledger-install.sh in \$PATH
(and upgrade it periodically - currently this must be done manually):

 hledger install        # upgrades other hledger tools
 hledger install -- -s  # shows installation status

Note this can require significant time (minutes to hours), memory (~2G),
and disk space (megabytes to a gigabyte) depending on your connection, 
machine and past installations. You can kill and rerun it without losing progress.

Version $HLEDGER_INSTALL_VERSION, installs hledger $HLEDGER_VERSION
HERE
}

HLEDGER_INSTALL_TOOL=hledger-install.sh
  # ^ this script's name (can't use $0 when it's piped into bash)
HLEDGER_INSTALL_VERSION=20170727
RESOLVER="--resolver=lts-8"
  # ^ lts-8 selects the latest lts-8.x snapshot for stack. You can specify another, 
  # or comment out this line to use your current global resolver, which might 
  # avoid some unnecessary building. lts-6 or 7 probably require tweaking the 
  # hledger install commands below. OSX Sierra+ requires at least lts-8.0+. 
HLEDGER_VERSION=1.3
HLEDGER_DIFF_VERSION=0.2.0.10
HLEDGER_IADD_VERSION=1.2.3
HLEDGER_INTEREST_VERSION=1.5.1
HLEDGER_IRR_VERSION=0.1.1.11
HLEDGER_MAIN_TOOLS="\
hledger \
hledger-ui \
hledger-web \
hledger-api \
"
HLEDGER_OTHER_TOOLS="\
hledger-diff \
hledger-iadd \
hledger-interest \
hledger-irr \
"

# start of (most of) get-stack.sh, https://github.com/commercialhaskell/stack/blob/master/etc/scripts/get-stack.sh
# modified at CHANGED markers

HOME_LOCAL_BIN="$HOME/.local/bin"
USR_LOCAL_BIN="/usr/local/bin"
QUIET=""
FORCE=""
STACK_TEMP_DIR=

# creates a temporary directory, which will be cleaned up automatically
# when the script finishes
make_temp_dir() {
  STACK_TEMP_DIR="$(mktemp -d 2>/dev/null || mktemp -d -t stack)"
}

# cleanup the temporary directory if it's been created.  called automatically
# when the script exits.
cleanup_temp_dir() {
  if [ -n "$STACK_TEMP_DIR" ] ; then
    rm -rf "$STACK_TEMP_DIR"
    STACK_TEMP_DIR=
  fi
}

# print a message to stderr and exit with error code
die() {
  echo "$@" >&2
  exit 1
}

# print a message to stdout unless '-q' passed to script
info() {
  if [ -z "$QUIET" ] ; then
    echo "$@"
  fi
}

# print a separator for post-install messages
post_install_separator() {
  info ""
  info "-------------------------------------------------------------------------------"
  info ""
}

# determines the the CPU's instruction set
get_isa() {
  if arch | grep -q arm ; then
    echo arm
  else
    echo x86
  fi
}

# exits with code 0 if arm ISA is detected as described above
is_arm() {
  test "$(get_isa)" = arm
}


# determines 64- or 32-bit architecture
# if getconf is available, it will return the arch of the OS, as desired
# if not, it will use uname to get the arch of the CPU, though the installed
# OS could be 32-bits on a 64-bit CPU
get_arch() {
  if has_getconf ; then
    if getconf LONG_BIT | grep -q 64 ; then
      echo 64
    else
      echo 32
    fi
  else
    case "$(uname -m)" in
      *64)
        echo 64
        ;;
      *)
        echo 32
        ;;
    esac
  fi
}

# exits with code 0 if a 64-bit architecture is detected as described above
is_64_bit() {
  test "$(get_arch)" = 64
}

# prints a generic bindist notice
print_bindist_notice() {
  if [ -z "$1" ] ; then
    info ""
    info "Using generic bindist..."
    info ""
  else
    info ""
    info "Using generic $1 bindist..."
    info ""
  fi
}

# Adds a `sudo` prefix if sudo is available to execute the given command
# If not, the given command is run as is
sudocmd() {
  $(command -v sudo) "$@"
}

# Install dependencies for distros that use Apt
apt_install_dependencies() {
    info "Installing dependencies..."
    info ""
    apt_get_install_pkgs "$@"
}

# Attempts an install on Ubuntu via apt, if possible
# Expects the version (in Major.Minor format, with any sub-minor removed)
# as the first and only argument
# If the version of Ubuntu is unsupported, it attempts to copy the binary
# and install the necessary dependencies explicitly.
do_ubuntu_install() {

  install_dependencies() {
    apt_install_dependencies g++ gcc libc6-dev libffi-dev libgmp-dev make xz-utils zlib1g-dev git gnupg
  }

  if is_arm ; then
    install_dependencies
    print_bindist_notice
    install_arm_binary
  elif is_64_bit ; then
    install_dependencies
    print_bindist_notice
    install_64bit_static_binary
  else
    install_dependencies
    print_bindist_notice
    install_32bit_standard_binary
  fi

}

# Attempts an install on Debian.
# Expects the single-number version as the first and only argument
# If the version of Debian is unsupported, it attempts to copy the binary
# and install the necessary dependencies explicitly.
do_debian_install() {

  install_dependencies() {
    apt_install_dependencies g++ gcc libc6-dev libffi-dev libgmp-dev make xz-utils zlib1g-dev
  }

  if is_arm ; then
    install_dependencies
    print_bindist_notice
    install_arm_binary
  elif is_64_bit ; then
    install_dependencies
    print_bindist_notice
    install_64bit_static_binary
  else
    install_dependencies
    print_bindist_notice
    install_32bit_standard_binary
  fi
}

# Attempts an install on Fedora.
# Expects the single-number version as the first and only argument
# If the version of Fedora is unsupported, it attempts to copy the binary
# and install the necessary dependencies explicitly.
do_fedora_install() {
  install_dependencies() {
    dnf_install_pkgs perl make automake gcc gmp-devel libffi zlib xz tar
  }

  if is_64_bit ; then
    install_dependencies "$1"
    print_bindist_notice
    install_64bit_static_binary
  else
    install_dependencies "$1"
    print_bindist_notice
    install_32bit_standard_binary
  fi
}

# Attempts an install on CentOS.
# Expects the single-number version as the first and only argument
# If the version of CentOS is unsupported, it attempts to copy the binary
# and install the necessary dependencies explicitly.
do_centos_install() {
  install_dependencies() {
    yum_install_pkgs perl make automake gcc gmp-devel libffi zlib xz tar
  }

  if is_64_bit ; then
    install_dependencies
    print_bindist_notice
    install_64bit_static_binary
  else
    install_dependencies
    case "$1" in
      "6")
        print_bindist_notice "libgmp4"
        install_32bit_gmp4_linked_binary
        ;;
      *)
        print_bindist_notice
        install_32bit_standard_binary
        ;;
    esac
  fi
}

# Attempts to install on macOS.
# If 'brew' exists, installs using Homebrew.  Otherwise, installs
# the generic bindist.
do_osx_install() {
  info "Using generic bindist..."
  info ""
  install_64bit_osx_binary
  info "NOTE: You may need to run 'xcode-select --install' to set"
  info "      up the Xcode command-line tools, which Stack uses."
  info ""
}

# Attempts to insall on FreeBSD.  Installs dependencies with
# 'pkg install' and then downloads bindist.
do_freebsd_install() {
  install_dependencies() {
    pkg_install_pkgs devel/gmake perl5 lang/gcc misc/compat8x misc/compat9x converters/libiconv ca_root_nss
  }
  if is_64_bit ; then
    install_dependencies
    install_64bit_freebsd_binary
  else
    die "Sorry, there is currently no 32-bit FreeBSD binary available."
  fi
}

# Alpine distro install
do_alpine_install() {
  install_dependencies() {
    apk_install_pkgs gmp libgcc xz make
  }
  install_dependencies
  if is_64_bit ; then
    install_64bit_static_binary
  else
    die "Sorry, there is currently no 32-bit Alpine Linux binary available."
  fi
}

# Attempts to install on unsupported Linux distribution by downloading
# the bindist.
do_sloppy_install() {
  info "This installer doesn't support your Linux distribution, trying generic"
  info "bindist..."
  info ""

  if is_arm ; then
      install_arm_binary
  elif is_64_bit ; then
      install_64bit_static_binary
  else
      install_32bit_standard_binary
  fi
  info "Since this installer doesn't support your Linux distribution,"
  info "there is no guarantee that 'stack' will work at all!  You may"
  info "need to manually install some system info dependencies for GHC:"
  info "  gcc, make, libffi, zlib, libgmp and libtinfo"
  info "Please see http://docs.haskellstack.org/en/stable/install_and_upgrade/"
  info "Pull requests to add support for this distro would be welcome!"
  info ""
}

# Attempts to determine the running Linux distribution.
# Prints "DISTRO;VERSION" (distribution name and version)"."
distro_info() {
  parse_lsb() {
    lsb_release -a 2> /dev/null | perl -ne "$1"
  }

  try_lsb() {
    if has_lsb_release ; then
      TL_DIST="$(parse_lsb 'if(/Distributor ID:\s+([^ ]+)/) { print "\L$1"; }')"
      TL_VERSION="$(parse_lsb 'if(/Release:\s+([^ ]+)/) { print "\L$1"; }')"
      echo "$TL_DIST;$TL_VERSION"
    else
      return 1
    fi
  }

  try_release() {
    parse_release() {
      perl -ne "$1" /etc/*release 2>/dev/null
    }

    parse_release_id() {
      parse_release 'if(/^(DISTRIB_)?ID\s*=\s*"?([^"]+)/) { print "\L$2"; exit 0; }'
    }

    parse_release_version() {
      parse_release 'if(/^(DISTRIB_RELEASE|VERSION_ID)\s*=\s*"?([^"]+)/) { print $2; exit 0; }'
    }

    TR_RELEASE="$(parse_release_id);$(parse_release_version)"

    if [ ";" = "$TR_RELEASE" ] ; then
      if [ -e /etc/arch-release ] ; then
        # /etc/arch-release exists but is often empty
        echo "arch;"
      elif [ -e /etc/centos-release ] && grep -q "\<6\>" /etc/centos-release ; then
        # /etc/centos-release has a non-standard format before version 7
        echo "centos;6"
      else
        return 1
      fi
    else
      echo "$TR_RELEASE"
    fi
  }

  try_issue() {
    case "$(cat /etc/issue 2>/dev/null)" in
      "Arch Linux"*)
        echo "arch;" # n.b. Version is not available in /etc/issue on Arch
        ;;
      "Ubuntu"*)
        echo "ubuntu;$(perl -ne 'if(/Ubuntu (\d+\.\d+)/) { print $1; }' < /etc/issue)"
        ;;
      "Debian"*)
        echo "debian;$(perl -ne 'if(/Debian GNU\/Linux (\d+(\.\d+)?)/) { print $1; }' < /etc/issue)"
        ;;
      *"SUSE"*)
        echo "suse;$(perl -ne 'if(/SUSE\b.* (\d+\.\d+)/) { print $1; }' < /etc/issue)"
        ;;
      *"NixOS"*)
        echo "nixos;$(perl -ne 'if(/NixOS (\d+\.\d+)/) { print $1; }' < /etc/issue)"
        ;;
      "CentOS"*)
        echo "centos;$(perl -ne 'if(/^CentOS release (\d+)\./) { print $1; }' < /etc/issue)"
        ;;
      *)
    esac
    # others do not output useful info in issue, return empty
  }

  try_lsb || try_release || try_issue
}

# Attempt to install on a Linux distribution
do_distro() {
  if ! has_perl ; then
    if ! try_install_pkgs perl ; then
      #TODO: remove dependence on 'perl', which is not installed by default
      #on some distributions (Fedora and RHEL, in particular).
      die "This script requires 'perl', please install it to continue."
    fi
  fi

  IFS=";" read -r DISTRO VERSION <<GETDISTRO
$(distro_info)
GETDISTRO

  if [ -n "$DISTRO" ] ; then
    info "Detected Linux distribution: $DISTRO"
    info ""
  fi

  case "$DISTRO" in
    ubuntu)
      do_ubuntu_install "$VERSION"
      ;;
    debian|kali|raspbian)
      do_debian_install "$VERSION"
      ;;
    fedora)
      do_fedora_install "$VERSION"
      ;;
    centos|rhel)
      do_centos_install "$VERSION"
      ;;
    alpine)
      do_alpine_install "$VERSION"
      ;;
    *)
      do_sloppy_install
  esac
}

# Determine operating system and attempt to install.
do_os() {
  case "$(uname)" in
    "Linux")
      do_distro
      ;;
    "Darwin")
      do_osx_install
      ;;
    "FreeBSD")
      do_freebsd_install
      ;;
    *)
      die "Sorry, this installer does not support your operating system: $(uname).
See http://docs.haskellstack.org/en/stable/install_and_upgrade/"
  esac
}

# Download a URL to file using 'curl' or 'wget'.
dl_to_file() {
  if has_curl ; then
    if ! curl ${QUIET:+-sS} -L -o "$2" "$1"; then
      die "curl download failed: $1"
    fi
  elif has_wget ; then
    if ! wget ${QUIET:+-q} "-O$2" "$1"; then
      die "wget download failed: $1"
    fi
  else
    # should already have checked for this, otherwise this message will probably
    # not be displayed, since dl_to_stdout will be part of a pipeline
    die "Neither wget nor curl is available, please install one to continue."
  fi
}

# Check for 'curl' or 'wget' and attempt to install 'curl' if neither found,
# or fail the script if that is not possible.
check_dl_tools() {
  if ! has_curl && ! has_wget ; then
    if ! try_install_pkgs curl ; then
      die "Neither wget nor curl is available, please install one to continue."
    fi
  fi
}

# Download a Stack bindst and install it in /usr/local/bin/stack.
install_from_bindist() {
    IFB_URL="https://www.stackage.org/stack/$1"
    check_dl_tools
    make_temp_dir

    dl_to_file "$IFB_URL" "$STACK_TEMP_DIR/$1.bindist"
    mkdir -p "$STACK_TEMP_DIR/$1"
    if ! tar xzf "$STACK_TEMP_DIR/$1.bindist" -C "$STACK_TEMP_DIR/$1"; then
      die "Extract bindist failed"
    fi
#CHANGED
#    if ! sudocmd install -c -o 0 -g 0 -m 0755 "$STACK_TEMP_DIR/$1"/*/stack "$USR_LOCAL_BIN/stack"; then
#      die "Install to $USR_LOCAL_BIN/stack failed"
    if ! install -m 0755 "$STACK_TEMP_DIR/$1"/*/stack "$HOME_LOCAL_BIN/stack"; then
      die "Install to $HOME_LOCAL_BIN/stack failed"
    fi

    post_install_separator
#CHANGED
#    info "Stack has been installed to: $USR_LOCAL_BIN/stack"
    echo "Stack has been installed to: $HOME_LOCAL_BIN/stack"
    info ""

    check_usr_local_bin_on_path
}

install_arm_binary() {
  install_from_bindist "linux-arm"
}

install_32bit_standard_binary() {
  install_from_bindist "linux-i386"
}

install_64bit_static_binary() {
  install_from_bindist "linux-x86_64-static"
}

install_32bit_gmp4_linked_binary() {
  install_from_bindist "linux-i386-gmp4"
}

install_64bit_osx_binary() {
  install_from_bindist "osx-x86_64"
}

install_64bit_freebsd_binary() {
  install_from_bindist "freebsd-x86_64"
}

# Attempt to install packages using whichever of apt-get, dnf, yum, or apk is
# available.
try_install_pkgs() {
  if has_apt_get ; then
    apt_get_install_pkgs "$@"
  elif has_dnf ; then
    dnf_install_pkgs "$@"
  elif has_yum ; then
    yum_install_pkgs "$@"
  elif has_apk ; then
    apk_install_pkgs "$@"
  else
    return 1
  fi
}

# Install packages using apt-get
apt_get_install_pkgs() {
  if ! sudocmd apt-get install -y ${QUIET:+-qq} "$@"; then
    die "Installing apt packages failed.  Please run 'apt-get update' and try again."
  fi
}

# Install packages using dnf
dnf_install_pkgs() {
  if ! sudocmd dnf install -y ${QUIET:+-q} "$@"; then
    die "Installing dnf packages failed.  Please run 'dnf check-update' and try again."
  fi
}

# Install packages using yum
yum_install_pkgs() {
  if ! sudocmd yum install -y ${QUIET:+-q} "$@"; then
    die "Installing yum packages failed.  Please run 'yum check-update' and try again."
  fi
}

# Install packages using apk
apk_install_pkgs() {
  if ! sudocmd apk add --update ${QUIET:+-q} "$@"; then
    die "Installing apk packages failed.  Please run 'apk update' and try again."
  fi
}

# Install packages using pkg
pkg_install_pkgs() {
    if ! sudocmd pkg install -y "$@"; then
        die "Installing pkg packages failed.  Please run 'pkg update' and try again."
    fi
}

# Get installed Stack version, if any
stack_version() {
  stack --version | grep -o 'Version \([[:digit:]]\|\.\)\+'
}

# Get installed Stack's path
stack_location() {
  command -v stack
}

# Check whether 'stack' command exists
has_stack() {
  has_cmd stack
}

# Check whether 'wget' command exists
has_wget() {
  has_cmd wget
}

# Check whether 'curl' command exists
has_curl() {
  has_cmd curl
}

# Check whether 'lsb_release' command exists
has_lsb_release() {
  has_cmd lsb_release
}

# Check whether 'sudo' command exists
has_sudo() {
  has_cmd sudo
}

# Check whether 'getconf' command exists
has_getconf() {
  has_cmd getconf
}

# Check whether 'brew' command exists
#has_brew() {
#  has_cmd brew
#}

# Check whether 'perl' command exists
has_perl() {
  has_cmd perl
}

# Check whether 'apt-get' command exists
has_apt_get() {
  has_cmd apt-get
}

# Check whether 'yum' command exists
has_yum() {
  has_cmd yum
}

# Check whether 'apk' command exists
has_apk() {
  has_cmd apk
}

# Check whether 'dnf' command exists
has_dnf() {
  has_cmd dnf
}

# Check whether the given command exists
has_cmd() {
  command -v "$1" > /dev/null 2>&1
}

# Check whether the given path is listed in the PATH environment variable
on_path() {
  echo ":$PATH:" | grep -q :"$1":
}

# Check whether ~/.local/bin is on the PATH, and print a warning if not.
check_home_local_bin_on_path() {
  if ! on_path "$HOME_LOCAL_BIN" ; then
    #TODO: offer to add it for the user (pull requests welcome!)
    info "WARNING: '$HOME_LOCAL_BIN' is not on your PATH."
    info "    For best results, please add it to the beginning of PATH in your profile."
    info ""
  fi
}

# Check whether /usr/local/bin is on the PATH, and print a warning if not.
check_usr_local_bin_on_path() {
  if ! on_path "$USR_LOCAL_BIN" ; then
    info "WARNING: '$USR_LOCAL_BIN' is not on your PATH."
    info ""
  fi
}

# Check whether Stack is already installed, and print an error if it is.
check_stack_installed() {
  if [ "$FORCE" != "true" ] && has_stack ; then
    die "Stack $(stack_version) already appears to be installed at:
  $(stack_location)
Use 'stack upgrade' or your OS's package manager to upgrade,
or pass --force to this script to install anyway."
  fi
}

trap cleanup_temp_dir EXIT

# end of (most of) get-stack.sh

# hledger routines

# install stack if needed, or always with --force, in $HOME/.local/bin
ensure_stack() {
  if ! $(has_stack) || [[ "$FORCE" == "true" ]] ; then
    echo "Installing stack"
    do_os
  fi
}

# get a sed command that supports EREs
if sed -r </dev/null >/dev/null 2>&1 ; then
  SED="sed -r"
else
  SED="sed -E"
fi

# Get the given command's location, or empty string if it's not in $PATH.
cmd_location() {
  command -v "$1"
}

# Get the given command's version, ie the first number in its --version output, 
# or empty string if there's a problem.
cmd_version() {
  (command "$1" --version 2>/dev/null | grep -E '[0-9]' | $SED -e 's/[^0-9]*([0-9][0-9.]*).*/\1/') || ""
}

# Check whether the given command exists with given version
has_cmd_version() {
  [[ $(cmd_version "$1") == "$2" ]] 
}

# Show a command's presence in $PATH, and its version if present.
print_cmd_version() {
  if [[ $(cmd_location "$1") ]]; then
    echo "$1" $(cmd_version "$1") is installed at $(cmd_location "$1")
  else
    echo "$1 not found"
  fi
}

# Show the installation status of the $HLEDGER_MAIN_TOOLS and $HLEDGER_OTHER_TOOLS. 
print_hledger_versions() {
  for cmd in $HLEDGER_MAIN_TOOLS $HLEDGER_OTHER_TOOLS $HLEDGER_INSTALL_TOOL ; do print_cmd_version $cmd; done
}

# Run a command, but first log it with "Trying" prepended.
try_info() {
  echo Trying "$@"
  $@
}

# start

# process command-line flags

HELPFLAG=""
STATUSFLAG=""
VERBOSEFLAG=""
VERSIONFLAG=""

while [ $# -gt 0 ]; do
  case "$1" in
    -f|--force)
      FORCE="true"
      shift
      ;;
    -v|--verbose)
      VERBOSEFLAG="true"
      shift
      ;;
    -s|--status)
      STATUSFLAG="true"
      shift
      ;;
    --version)
      VERSIONFLAG="true"
      shift
      ;;
    -h|--help)
      HELPFLAG="true"
      shift
      ;;
    *)
      echo "Invalid argument: $1" >&2
      exit 1
      ;;
  esac
done

if [[ $HELPFLAG ]] ; then
  usage
  exit 0
fi

if [[ $VERSIONFLAG ]] ; then
  echo $HLEDGER_INSTALL_TOOL $HLEDGER_INSTALL_VERSION
  exit 0
fi

if [[ $VERBOSEFLAG ]]; then
  CABAL_VERBOSITY=1       # 0-3
  STACK_VERBOSITY=info    # silent, error, warn, info, debug
else
  CABAL_VERBOSITY=0
  STACK_VERBOSITY=error
  QUIET="true"
fi

# show current installed hledger packages
print_hledger_versions

if [[ $STATUSFLAG ]] ; then
  exit 0
fi

# select main hledger packages to install
#TOOLS_TO_INSTALL=""
## packages of main tools which are missing or older than latest version
#for t in $HLEDGER_MAIN_TOOLS; do
#  if [[ $(cmd_version $t) < $HLEDGER_VERSION ]]; then 
#    TOOLS_TO_INSTALL="$TOOLS_TO_INSTALL $t-$HLEDGER_VERSION"
#  fi
#done
## any depended-on hledger packages so that stack can pull those too from hackage when needed  
#PACKAGES_TO_INSTALL=$TOOLS_TO_INSTALL
#if [[ $PACKAGES_TO_INSTALL ]]; then
#  # most packages depend on hledger, add it if not already added
#  if [[ ! $PACKAGES_TO_INSTALL =~ hledger-$HLEDGER_VERSION ]]; then
#    PACKAGES_TO_INSTALL="hledger-$HLEDGER_VERSION $PACKAGES_TO_INSTALL"
#  fi
#  # and most depend on hledger-lib
#  PACKAGES_TO_INSTALL="hledger-lib-$HLEDGER_VERSION $PACKAGES_TO_INSTALL"
#fi

# try installing each package that needs installing, in turn

# Try to install the executables of the given package(s) to $HOME/.local/bin, 
# trying several methods, generally from quickest to most reliable, continuing on failure.
# Current the installation methods are:
# - if stack is not installed and cabal is, try cabal install
# - otherwise install stack if needed and try stack install with specific resolver and ghc
# For the stack method, it's necessary to provide not only the package(s) you want to
# install but also all dependencies which are not in the specified stackage $RESOLVER.
try_install() {
  (cd  # avoid any project-specific stack/cabal config, install at user level
   (! has_cmd stack && has_cmd cabal && try_info cabal install "$@" --verbose=$CABAL_VERBOSITY ) ||
   (ensure_stack && (
    #(try_info stack install --install-ghc "$@" --verbosity=$STACK_VERBOSITY ) ||        # existing resolver
    (try_info stack install --install-ghc $RESOLVER "$@" --verbosity=$STACK_VERBOSITY )  # specific resolver
    )
   ) ||
   echo Failed to install "$@"
  )
}

echo ----------
if [[ $(cmd_version hledger) < $HLEDGER_VERSION ]]; then
  echo Installing hledger
  try_install hledger-$HLEDGER_VERSION hledger-lib-$HLEDGER_VERSION
  echo
fi
if [[ $(cmd_version hledger-ui) < $HLEDGER_VERSION ]]; then 
  echo Installing hledger-ui
  try_install hledger-ui-$HLEDGER_VERSION hledger-$HLEDGER_VERSION hledger-lib-$HLEDGER_VERSION
    # brick-0.19 data-clist-0.1.2.0
    # ^ when hledger-iadd requires a non-stack brick, use the same version here to avoid rebuilding
  echo
fi
if [[ $(cmd_version hledger-web) < $HLEDGER_VERSION ]]; then 
  echo Installing hledger-web
  try_install hledger-web-$HLEDGER_VERSION hledger-$HLEDGER_VERSION hledger-lib-$HLEDGER_VERSION
  echo
fi
if [[ $(cmd_version hledger-api) < $HLEDGER_VERSION ]]; then 
  echo Installing hledger-api
  try_install hledger-api-$HLEDGER_VERSION hledger-$HLEDGER_VERSION hledger-lib-$HLEDGER_VERSION
  echo
fi
if [[ $(cmd_version hledger-diff) < $HLEDGER_DIFF_VERSION ]]; then 
  echo Installing hledger-diff
  try_install hledger-diff-$HLEDGER_DIFF_VERSION hledger-lib-$HLEDGER_VERSION
  echo
fi
if [[ $(cmd_version hledger-iadd) < $HLEDGER_IADD_VERSION ]]; then 
  echo Installing hledger-iadd
  try_install hledger-iadd-$HLEDGER_IADD_VERSION hledger-lib-$HLEDGER_VERSION
  echo
fi
if [[ $(cmd_version hledger-interest) < $HLEDGER_INTEREST_VERSION ]]; then 
  echo Installing hledger-interest
  try_install hledger-interest-$HLEDGER_INTEREST_VERSION hledger-lib-$HLEDGER_VERSION
  echo
fi
if [[ $(cmd_version hledger-irr) < $HLEDGER_IRR_VERSION ]]; then 
  echo Installing hledger-irr
  try_install hledger-irr-$HLEDGER_IRR_VERSION hledger-lib-$HLEDGER_VERSION
  echo
fi
echo ----------

# show new installation status
print_hledger_versions

# warn if $HOME/.local/bin isn't in $PATH
check_home_local_bin_on_path

# TODO
# check/require ghc-8.0.2+/lts-8+ on osx sierra+
# automate testing
# install hledger experimental tools
# help install c libs
# try installing system packages
# help with logging & reporting successes/failures
# detect latest hledger version & resolver ?
# detect latest installer version, self upgrade ?
