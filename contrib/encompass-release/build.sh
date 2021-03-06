#!/bin/bash -l
set -xeo pipefail


sign_release () {
         sha1sum ${release} > ${1}.sha1
         md5sum ${release} > ${1}.md5
         gpg --sign --armor --detach  ${1}
         gpg --sign --armor --detach  ${1}.md5
         gpg --sign --armor --detach  ${1}.sha1
}

build_win32trezor() {
 ./helpers/build-hidapi.sh
}
get_archpkg (){
  thisdir=$(pwd)
  if [ "${TYPE}" = "SIGNED" ]
  then 
     archbranch="v${VERSION}"
  else
     archbranch="\"check_repo_for_correct_branch\""
  fi
  test -d ../../contrib/ArchLinux || mkdir -v ../../contrib/ArchLinux
  cd ../../contrib/ArchLinux
  wget https://aur.archlinux.org/packages/en/encompass-git/encompass-git.tar.gz
  tar -xpzvf encompass-git.tar.gz
  sed -e 's/_gitbranch\=.*/_gitbranch='${archbranch}'/g' encompass-git/PKGBUILD > encompass-git/PKGBUILD.new
  mv encompass-git/PKGBUILD.new encompass-git/PKGBUILD
  rm encompass-git.tar.gz
  cd ${thisdir}
}
build_osx (){
  if [ "$(uname)" = "Darwin" ];
   then
  
  if [ ! -f /opt/local/bin/python2.7 ]
  then 
    echo "This build requires macports python2.7 and pyqt4"
    exit 5
  fi
  VER="$1"
  sed 's/ELECTRUM_VERSION/'${VER}'/g' Makefile.in > Makefile
  cd repo
  /opt/local/bin/python2.7 setup-release.py py2app
  test -d ../src || mkdir ../src 
  mv dist/Encompass.app ../src/ 
  cd ..
  #make  -  makes the unneeded dmg
  test -d helpers/release-packages/OSX || mkdir -pv helpers/release-packages/OSX
  #mv Encompass-${VER}.dmg helpers/release-packages/OSX
  mv src/Encompass.app helpers/release-packages/OSX
  cp helpers/make_OSX-installer.sh helpers/release-packages/OSX
  thisdir=$(pwd)
  cd helpers/release-packages/OSX
  ./make_OSX-installer.sh $VERSION
  cd ${thisdir}
 else
  echo "OSX Build Requires OSX build host!"
 fi
}
prepare_repo(){
  if [ ${TYPE} = "local" ]
  then
    echo "Setting up Local build"
    test -d repo || mkdir -pv repo
    sudo tar -C ../../ -cpv --exclude=contrib/* . |sudo  tar -C repo -xpf -
  fi
  cp -av python-trezor/trezorctl helpers/trezorctl.py
}
buildBinary(){
  test -d releases || mkdir -pv $(pwd)/releases
  # echo "Making locales" 
  # $DOCKERBIN run --rm -it --privileged -e MKPKG_VER=${VERSION} -v $(pwd)/helpers:/root  -v $(pwd)/repo:/root/repo  -v $(pwd)/source:/opt/wine-electrum/drive_c/encompass/ -v $(pwd):/root/encompass-release mazaclub/encompass-release:${VERSION} /bin/bash
  echo "Making Release packages for $VERSION"
  $DOCKERBIN run --rm -it --privileged -e MKPKG_VER=${VERSION} -v $(pwd)/releases:/releases -v $(pwd)/helpers:/root  -v $(pwd)/repo:/root/repo  -v $(pwd)/source:/opt/wine-electrum/drive_c/encompass/ -v $(pwd):/root/encompass-release mazaclub/encompass-release:${VERSION} /root/make_release $VERSION $TYPE \
   && echo "Making Windows EXEs for $VERSION" \
   && $DOCKERBIN run --rm -it --privileged -e MKPKG_VER=${VERSION} -v $(pwd)/helpers:/root  -v $(pwd)/repo:/root/repo  -v $(pwd)/source:/opt/wine-electrum/drive_c/encompass/ -v $(pwd):/root/encompass-release mazaclub/encompass-winbuild:${VERSION} /root/build-binary $VERSION \
   && ls -la $(pwd)/helpers/release-packages/Windows/Encompass-${VERSION}-Windows-setup.exe \
   && echo "Attempting OSX Build: Requires Darwin Buildhost" \
   && build_osx ${VERSION} \
   && echo "Linux Packaging" \
   && $DOCKERBIN run --rm -it --privileged -e MKPKG_VER=${VERSION} -v $(pwd)/helpers:/root  -v $(pwd)/repo:/root/repo  -v $(pwd)/source:/opt/wine-electrum/drive_c/encompass/ -v $(pwd):/root/encompass-release mazaclub/encompass-release:${VERSION} /root/make_linux ${VERSION}
##   && $DOCKERBIN run --rm -it --privileged -e MKPKG_VER=${VERSION} -v $(pwd)/helpers:/root  -v $(pwd)/repo:/root/repo  -v $(pwd)/source:/opt/wine-electrum/drive_c/encompass/ -v $(pwd):/root/encompass-release mazaclub/encompass-release:${VERSION} /root/make_debian ${VERSION} amd64 
  if [[ $? = 0 ]]; then
    echo "Build successful."
  else
    echo "Seems like the build failed. Exiting."
    exit
  fi
  #mv $(pwd)/source/Encompass-${VERSION}/dist/encompass.exe $(pwd)/releases/Windows/Encompass-$VERSION.exe
  #mv $(pwd)/source/Encompass-${VERSION}/dist/encompass-setup.exe $(pwd)/releases/Windows/Encompass-$VERSION-setup.exe
  mv $(pwd)/helpers/release-packages/* $(pwd)/releases/
  if [ "${TYPE}" = "rc" ]; then export TYPE=SIGNED ; fi
  if [ "${TYPE}" = "SIGNED" ] ; then
    ${DOCKERBIN} push mazaclub/encompass-winbuild:${VERSION}
    ${DOCKERBIN} push mazaclub/encompass-release:${VERSION}
    ${DOCKERBIN} push mazaclub/encompass32-release:${VERSION}
    ${DOCKERBIN} tag -f ogrisel/python-winbuilder mazaclub/python-winbuilder:${VERSION}
    ${DOCKERBIN} push mazaclub/python-winbuilder:${VERSION}
    cd releases
    for release in * 
    do
      if [ ! -d ${release} ]; then
         sign_release ${release}
      else
         cd ${release}
         for i in * 
         do 
           if [ ! -d ${i} ]; then
              sign_release ${i}
	   fi
         done
         cd ..
      fi
    done
  fi
  echo "You can find your Encompasss $VERSION binaries in the releases folder."

}

buildImage(){
  echo "Building image"
  case "${1}" in 
  winbuild) $DOCKERBIN build -t mazaclub/encompass-winbuild:${VERSION} .
         ;;
   release) $DOCKERBIN build -f Dockerfile-release -t  mazaclub/encompass-release:${VERSION} .
         ;;
  esac
}


buildLtcScrypt() {
## this will be integrated into the main build in a later release
   wget https://pypi.python.org/packages/source/l/ltc_scrypt/ltc_scrypt-1.0.tar.gz
   tar -xpzvf ltc_scrypt-1.0.tar.gz
   docker run -ti --rm \
    -e WINEPREFIX="/wine/wine-py2.7.8-32" \
    -v $(pwd)/ltc_scrypt-1.0:/code \
    -v $(pwd)/helpers:/helpers \
    ogrisel/python-winbuilder wineconsole --backend=curses  Z:\\helpers\\ltc_scrypt-build.bat
   cp -av ltc_scrypt-1.0/build/lib.win32-2.7/ltc_scrypt.pyd helpers/ltc_scrypt.pyd
   echo "Building ltc_scrypt for Linux/Android"
   #docker run -ti --rm \
   # -v $(pwd)/ltc_scrypt-1.0:/code \
   # -v $(pwd)/helpers:/helpers \
   # mazaclub/encompass-release:${VERSION} /bin/sh -c "cd /code ;python setup.py build" 
   #cp -av ltc_scrypt-1.0/build/lib.linux-x86_64-2.7/ltc_scrypt.so helpers/ltc_scrypt.so

#   echo "Building ltc_scrypt module for OSX"
#   docker run -it --rm \
#    -e LDFLAGS="-L/usr/x86_64-apple-darwin14/SDK/MacOSX10.10.sdk/usr/lib/ -L/usr/x86_64-apple-darwin14/lib" \
#    -e PYTHONXCPREFIX="/usr/x86_64-apple-darwin14/" \
#    -e MAC_SDK_VERSION="10.10" \
#    -e LD_LIBRARY_PATH="/usr/lib/llvm-3.4/lib:/usr/x86_64-apple-darwin14/lib" \
#    -e PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/x86_64-apple-darwin14/bin" \
#    -e CROSS_TRIPLE="x86_64-apple-darwin14" \
#    -e LDSHARED="x86_64-apple-darwin14-cc -shared" \
#    -e CROSS_ROOT="/usr/x86_64-apple-darwin14" \
#    -e CC="x86_64-apple-darwin14-cc" \
#    -e CROSS_COMPILE="x86_64-apple-darwin14-" \
#    -v $(pwd)/ltc_scrypt-1.0:/code \
#    -v $(pwd)/helpers/build-darwin-ltc_scrypt.sh:/build-darwin-ltc_scrypt.sh \
#    mazaclub/cross-compiler:darwin-x64 /build-darwin-ltc_scrypt.sh
#    cp -v ltc_scrypt-1.0/build/lib.darwin-x64/ltc_scrypt.dylib helpers/ltc_scrypt.dylib

}
buildDarkcoinHash() {
## this will be integrated into the main build in a later release
  echo "Building Darkcoin_hash for Windows"
   wget https://github.com/guruvan/darkcoin_hash/archive/1.1.tar.gz
   tar -xpzvf 1.1.tar.gz
   docker run -ti --rm \
    -e WINEPREFIX="/wine/wine-py2.7.8-32" \
    -v $(pwd)/darkcoin_hash-1.1:/code \
    -v $(pwd)/helpers:/helpers \
    ogrisel/python-winbuilder wineconsole --backend=curses  Z:\\helpers\\darkcoin_hash-build.bat
   cp darkcoin_hash-1.1/build/lib.win32-2.7/darkcoin_hash.pyd helpers/darkcoin_hash.pyd
   #echo "Building darkcoin_hash for Linux/Android"
   #docker run -ti --rm \
   # -v $(pwd)/darkcoin_hash-1.1:/code \
   # -v $(pwd)/helpers:/helpers \
   # mazaclub/encompass-release:${VERSION} /bin/sh -c "cd /code ;python setup.py build" 
   #cp -av darkcoin_hash-1.1/build/lib.linux-x86_64-2.7/darkcoin_hash.so helpers/darkcoin_hash.so

   #echo "Building darkcoin_hash module for OSX"
   #docker run -it --rm \
   # -e LDFLAGS="-L/usr/x86_64-apple-darwin14/SDK/MacOSX10.10.sdk/usr/lib/ -L/usr/x86_64-apple-darwin14/lib -L/usr/x86_64-apple-darwin14/SDK/MacOSX10.10.sdk/usr/libexec/" \
  # -e PYTHONXCPREFIX="/usr/x86_64-apple-darwin14/" \
  #  -e MAC_SDK_VERSION="10.10" \
  #  -e LD_LIBRARY_PATH="/usr/lib/llvm-3.4/lib:/usr/x86_64-apple-darwin14/lib" \
  #  -e PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/x86_64-apple-darwin14/bin" \
  #  -e CROSS_TRIPLE="x86_64-apple-darwin14" \
  #  -e LDSHARED="x86_64-apple-darwin14-cc -shared" \
  #  -e CROSS_ROOT="/usr/x86_64-apple-darwin14" \
  #  -e CC="x86_64-apple-darwin14-cc" \
  #  -e CROSS_COMPILE="x86_64-apple-darwin14-" \
  #  -v $(pwd)/darkcoin_hash-1.1:/code \
  #  -v $(pwd)/helpers/build-darwin-darkcoin_hash.sh:/build-darwin-darkcoin_hash.sh \
  #  mazaclub/cross-compiler:darwin-x64 /build-darwin-darkcoin_hash.sh
  #  cp -v darkcoin_hash-1.1/build/lib.darwin-x64/darkcoin_hash.dylib helpers/darkcoin_hash.dylib

}

prepareFile(){
  echo "Preparing file for Encompass version $VERSION"
  if [ -e "$TARGETPATH" ]; then
    echo "Version tar already downloaded."
  else
   wget https://github.com/mazaclub/encompass/archive/v${VERSION}.zip -O $TARGETPATH
  fi

  if [ -d "$TARGETFOLDER" ]; then
    echo "Version is already extracted"
  else
     unzip -d $(pwd)/source ${TARGETPATH} 
   # tar -xvf $TARGETPATH -C $(pwd)/source
  fi
}

if [[ $# -gt 0 ]]; then
  VERSION=$1
  TYPE=${2:-tagged}
  FILENAME=Encompass-$VERSION.zip
  TARGETPATH=$(pwd)/source/$FILENAME
  TARGETFOLDER=$(pwd)/source/Encompass-$VERSION
  echo "Building Encompass $VERSION from $FILENAME"
else
  echo "Usage: ./build <version>."
  echo "For example: ./build 1.9.8"
  exit
fi

which docker || echo "docker" not found
if [[ $? = 0 ]]; then
  DOCKERBIN=$(which docker)
fi

#which docker.io || echo "docker.io not found" 
#if [[ $? = 0 ]]; then
  #DOCKERBIN=$(which docker.io)
#fi

if [[ -z "$DOCKERBIN" ]]; then
        echo "Could not find docker binary, exiting"
        exit
else
        echo "Using docker at $DOCKERBIN"
fi
if [ "${TYPE}" = "rc" -o "${TYPE}" = "SIGNED" ]
then 
   ./clean
fi
 git clone https://github.com/mazaclub/python-trezor
prepare_repo
get_archpkg
build_win32trezor
test -f helpers/ltc_scrypt.pyd || buildLtcScrypt
test -f helpers/darkcoin_hash.pyd || buildDarkcoinHash
# Build docker image
$DOCKERBIN images|awk '{print $1":"$2}'|grep "mazaclub/encompass-winbuild:${VERSION}" || buildImage winbuild
$DOCKERBIN images|awk '{print $1":"$2}'|grep "mazaclub/encompass-release:${VERSION}" || buildImage release
test -f FORCE_IMG_BUILD &&  buildImage winbuild
test -f FORCE_IMG_BUILD &&  buildImage release

# Prepare host file system
#prepareFile

# Build files
buildBinary
