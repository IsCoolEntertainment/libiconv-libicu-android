#!/bin/sh

export BUILDDIR=`pwd`

if [ -z "$NCPU" ]
then
    NCPU=4
    uname -s | grep -i "linux" \
        && NCPU=`cat /proc/cpuinfo | grep -c -i processor`
fi

if [ -z "$NDK_ROOT" ]
then
    NDK_ROOT=`which ndk-build`
    NDK_ROOT=`dirname $NDK`
    NDK_ROOT=`readlink -f $NDK`
fi

if [ -z "$NDK_ROOT" ]
then
    echo "NDK_ROOT must be set to the directory containing Android's NDK"
    exit 1
fi

: ${ARCHS="armeabi armeabi-v7a x86 mip"}

for ARCH in $ARCHS; do

cd $BUILDDIR
mkdir -p $ARCH
cd $BUILDDIR/$ARCH

# =========== libandroid_support.a ===========

[ -e libandroid_support.a ] || {
mkdir -p android_support
cd android_support
ln -sf $NDK_ROOT/sources/android/support jni

ndk-build -j$NCPU APP_ABI=$ARCH || exit 1
cp -f obj/local/$ARCH/libandroid_support.a ../

} || exit 1

cd $BUILDDIR/$ARCH

# =========== libiconv.so ===========

[ ${ENABLE_ICONV=1} = 0 ] || [ -e libiconv.so ] || {

	[ -e ../libiconv-1.14.tar.gz ] || curl -L http://ftp.gnu.org/pub/gnu/libiconv/libiconv-1.14.tar.gz -o ../libiconv-1.14.tar.gz || exit 1

	tar xvf ../libiconv-1.14.tar.gz

	cd libiconv-1.14

	cp -f $BUILDDIR/config.sub build-aux/
	cp -f $BUILDDIR/config.guess build-aux/
	cp -f $BUILDDIR/config.sub libcharset/build-aux/
	cp -f $BUILDDIR/config.guess libcharset/build-aux/

	env CFLAGS="-I$NDK_ROOT/sources/android/support/include" \
		LDFLAGS="-L$BUILDDIR/$ARCH -landroid_support" \
		$BUILDDIR/setCrossEnvironment-$ARCH.sh \
		./configure \
		--host=arm-linux-androideabi \
		--prefix=`pwd`/.. \
		--enable-static --enable-shared \
		|| exit 1

	env PATH=`pwd`:$PATH \
		$BUILDDIR/setCrossEnvironment-$ARCH.sh \
		make -j$NCPU V=1 || exit 1

	env PATH=`pwd`:$PATH \
		$BUILDDIR/setCrossEnvironment-$ARCH.sh \
		make V=1 install || exit 1

	cd ..

	for f in libiconv libcharset; do
		cp -f lib/$f.so ./
		$BUILDDIR/setCrossEnvironment-$ARCH.sh \
			sh -c '$STRIP'" $f.so"
	done

} || exit 1

cd $BUILDDIR/$ARCH

# =========== libicuXX.so ===========

[ ${ENABLE_ICU=1} = 0 ] || [ -e libicuuc.so ] || {

	[ -e ../icu4c-52_1-src.tgz ] || curl http://pkgs.fedoraproject.org/repo/pkgs/icu/icu4c-52_1-src.tgz/9e96ed4c1d99c0d14ac03c140f9f346c/icu4c-52_1-src.tgz -o ../icu4c-52_1-src.tgz || exit 1

	tar xvf ../icu4c-52_1-src.tgz

	cd icu/source

	cp -f $BUILDDIR/config.sub .
	cp -f $BUILDDIR/config.guess .

	[ -d cross ] || {
		mkdir cross
		cd cross
		../configure || exit 1
		make -j$NCPU VERBOSE=1 || exit 1
		cd ..
	} || exit 1

	sed -i "s@LD_SONAME *=.*@LD_SONAME =@g" config/mh-linux
	sed -i "s%ln -s *%cp -f \$(dir \$@)/%g" config/mh-linux

	env CFLAGS="-I$NDK_ROOT/sources/android/support/include -frtti -fexceptions" \
		LDFLAGS="-frtti -fexceptions" \
		LIBS="-L$BUILDDIR/$ARCH -landroid_support -lgnustl_static -lstdc++" \
		$BUILDDIR/setCrossEnvironment-$ARCH.sh \
		./configure \
		--host=arm-linux-androideabi \
		--prefix=`pwd`/../../ \
		--with-cross-build=`pwd`/cross \
		--enable-static --enable-shared \
		--with-data-packaging=archive \
		|| exit 1

	sed -i "s@^prefix *= *.*@prefix = .@" icudefs.mk || exit 1

	env PATH=`pwd`:$PATH \
		$BUILDDIR/setCrossEnvironment-$ARCH.sh \
		make -j$NCPU VERBOSE=1 || exit 1

	sed -i "s@^prefix *= *.*@prefix = `pwd`/../../@" icudefs.mk || exit 1

	env PATH=`pwd`:$PATH \
		$BUILDDIR/setCrossEnvironment-$ARCH.sh \
		make V=1 install || exit 1

	for f in libicudata libicutest libicui18n libicuio libicule libiculx libicutu libicuuc; do
		cp -f -H ../../lib/$f.so ../../
		cp -f ../../lib/$f.a ../../
		$BUILDDIR/setCrossEnvironment-$ARCH.sh \
			sh -c '$STRIP'" ../../$f.so"
	done

} || exit 1

done # for ARCH in armeabi armeabi-v7a

exit 0
