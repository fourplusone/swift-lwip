#!/bin/sh
set -ne

TEMPDIR=`mktemp -d`

LWIP_SOURCE_ARCHIVE="lwip-STABLE-2_1_2_RELEASE"
LWIP_SOURCE_ARCHIVE_PATH="`pwd`/scripts/$LWIP_SOURCE_ARCHIVE.tar.gz"

LWIP_CONTRIB_SOURCE_ARCHIVE="lwip-contrib-STABLE-2_1_0_RELEASE"
LWIP_CONTRIB_ARCHIVE_PATH="`pwd`/scripts/$LWIP_CONTRIB_SOURCE_ARCHIVE.tar.gz"

DESTINATION_DIR="`pwd`/Sources/CLwIP"

rm -r "$DESTINATION_DIR/src"
mkdir "$DESTINATION_DIR/src"

rm -r "$DESTINATION_DIR/port"
mkdir "$DESTINATION_DIR/port"

rm -r "$DESTINATION_DIR/include"
mkdir "$DESTINATION_DIR/include"


pushd "$TEMPDIR"
tar -xf "$LWIP_SOURCE_ARCHIVE_PATH"
tar -xf "$LWIP_CONTRIB_ARCHIVE_PATH"

cp -r "$LWIP_SOURCE_ARCHIVE/src/api" "$DESTINATION_DIR/src"
cp -r "$LWIP_SOURCE_ARCHIVE/src/core" "$DESTINATION_DIR/src"


cp -r "$LWIP_SOURCE_ARCHIVE/src/include/lwip" "$DESTINATION_DIR/include"
cp -r "$LWIP_SOURCE_ARCHIVE/src/include/netif" "$DESTINATION_DIR/include"

cp "$LWIP_CONTRIB_SOURCE_ARCHIVE/ports/unix/port/"*.c "$DESTINATION_DIR/port"
cp -r "$LWIP_CONTRIB_SOURCE_ARCHIVE/ports/unix/port/include/arch" "$DESTINATION_DIR/include"
popd



pushd "$DESTINATION_DIR/include/lwip/"

rm init.h.cmake.in
rm -r apps

sed 's/#define LWIP_HDR_ARCH_H/#define LWIP_HDR_ARCH_H\n#include "opt.h"/' arch.h > arch_mod.h
rm arch.h
mv arch_mod.h arch.h

sed 's/#include "lwipopts\.h"/#include "..\/config\/lwipopts.h"/g' opt.h > opt_mod.h
rm opt.h
mv opt_mod.h opt.h

echo "#ifdef LWIP_MEMPOOL\n\n$(cat priv/memp_std.h)\n#endif /* LWIP_MEMPOOL */" > priv/memp_std_mod.h
rm priv/memp_std.h
mv priv/memp_std_mod.h priv/memp_std.h

sed -e '/#include "lwip\/priv\/memp_std\.h"/ { r priv/memp_std.h'  -e 'd' -e '}' memp.h > memp_mod.h
rm memp.h
mv memp_mod.h memp.h
popd

rm -rf "$TEMPDIR"
