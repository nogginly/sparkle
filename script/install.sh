#!/bin/sh
# Installs Sparkle into one directory, or removes it again:
#
#   script/install.sh install PREFIX PONY_HOME
#   script/install.sh uninstall PREFIX
#
# PREFIX/bin/sparkle is the compiler, PREFIX/lib/pony the Pony standard
# library and runtime it builds against, PREFIX/share/sparkle/stdlib the
# Sparkle library, when the repository has one, PREFIX/share/sparkle/skills
# the language skill and its reference, and PREFIX/.sparkle-install the
# marker that lets a later install or uninstall replace the whole directory.
# A PREFIX that exists without the marker, and is not empty, is left alone.
# SPARKLE_VERSION and PONYC_VERSION, when set, are written into the marker.
set -eu

MARK=.sparkle-install
action=${1:-}
prefix=${2:-}

case $prefix in
  "" | / | "$HOME" | "$HOME/") echo "sparkle: refusing to use '$prefix' as PREFIX" >&2; exit 1 ;;
esac
if [ -e "$prefix" ] && [ ! -f "$prefix/$MARK" ] && [ -n "$(ls -A "$prefix" 2>/dev/null || echo x)" ]; then
  echo "sparkle: $prefix exists and is not a Sparkle install; choose another PREFIX" >&2
  exit 1
fi

case $action in
  uninstall)
    rm -rf "$prefix"
    echo "removed $prefix"
    ;;
  install)
    home=${3:-}
    if [ ! -d "$home/packages/builtin" ] || [ ! -x bin/sparkle ]; then
      echo "sparkle: run 'make ponyc' and 'make build' first" >&2
      exit 1
    fi
    # Steps: build the new install beside PREFIX, then swap it in, so a failed
    # copy leaves any earlier install untouched.
    mkdir -p "$(dirname "$prefix")"
    stage="$prefix.new.$$"
    trap 'rm -rf "$stage"' EXIT
    mkdir -p "$stage/bin" "$stage/lib/pony" "$stage/share/sparkle"
    cp bin/sparkle "$stage/bin/"
    cp -R "$home/packages" "$home/lib" "$stage/lib/pony/"
    rm -f "$stage"/lib/pony/lib/*/libponyc*.a
    cp -R skills "$stage/share/sparkle/"
    if [ -d stdlib ]; then cp -R stdlib "$stage/share/sparkle/"; fi
    printf 'sparkle %s\nponyc %s\n' "${SPARKLE_VERSION:-unknown}" "${PONYC_VERSION:-unknown}" > "$stage/$MARK"
    rm -rf "$prefix"
    mv "$stage" "$prefix"
    trap - EXIT
    echo "installed Sparkle in $prefix"
    echo "add it to your PATH, for example in ~/.profile:"
    echo "  export PATH=\"$prefix/bin:\$PATH\""
    echo "the language skill for coding agents is in $prefix/share/sparkle/skills/sparkle"
    ;;
  *)
    echo "usage: $0 install PREFIX PONY_HOME | uninstall PREFIX" >&2
    exit 1
    ;;
esac
