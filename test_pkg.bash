#!/bin/bash
if [[ -z "$1" || "$1" == "" ]]; then
  echo "You need to run this script with the debian directory you want to test"
  exit 1
fi

if [ ! -d "$1" ]; then
  echo "$1: Not a directory."
  exit 1
fi

if ! git status $1 2>&1 > /dev/null; then
  echo "$1: Not a directory/repository."
  exit 1
fi

if [ ! -e "$(which pbuilder)" ]; then
  apt-get install pbuilder || exit 1
fi

tmp="$(mktemp -d)"
cwd="$(pwd)"

cachedir="/var/cache/cfpkg"
mkdir -p "$cachedir"
cfver="3.4.4"
debver="+nmu1"

echo -n "Building in $tmp ... "

dobuild() {
  if [ ! -e /var/cache/pbuilder/base.tgz ]; then
    pbuilder create --distribution stable --mirror http://http.debian.net/debian/ --debootstrapopts "--variant=buildd" || return 1
  fi

  if [ ! -f "$cachedir/cfengine-$cfver.tar.gz" ]; then
    if ! wget -O "$cachedir/cfengine-$cfver.tar.gz" "http://cfengine.com/source-code/download?file=cfengine-$cfver.tar.gz"; then
      rm "$cachedir/cfengine-$cfver.tar.gz"
      return 1
    fi
  fi

  if [ ! -d "$cachedir/cfengine-$cfver" ]; then
    tar xzf "$cachedir/cfengine-$cfver.tar.gz" -C "$cachedir" || return 1
  fi

  cp -a "$cachedir/cfengine-$cfver" "$tmp" || return 1

  cp -r $1 "$tmp/cfengine-$cfver/debian" || return 1

  cd "$tmp" || return 1
  cp "$cachedir/cfengine-$cfver.tar.gz" ./cfengine3_${cfver}${debver}.orig.tar.gz || return 1

  cd "cfengine-$cfver" || return 1
  dpkg-source -b . || return 1

  cd .. || return 1
  mkdir "$tmp/result" || return 1
  pbuilder build --buildresult "$tmp/result" *.dsc || return 1

  tar cjf "$tmp/result.tar.bz2" result/ log err || return 1
}
(
  dobuild $1 || touch "$tmp/fail"
  cd "$cwd"
  touch "$tmp/done"
) > >(tee "$tmp/log") 2> >(tee "$tmp/err") | while dd of=/dev/null bs=256b count=1 &> /dev/null; do
    [ -e "$tmp/done" ] && break
    if [[ -z $prev || $prev = "" ]]; then
      prev="|"
      echo -n $prev
    else
      prev="$(echo -n $prev |sed 's,\\,|,; s,\-,\\,; s,/,-,; s,|,/,;')"
      echo -n -e "\b$prev"
    fi
  done

echo " ... done"
[ -e "$tmp/fail" ] && tail "$tmp/log" "$tmp/err"
