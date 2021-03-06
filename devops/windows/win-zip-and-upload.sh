#!/bin/bash

set -e
set -x

if [ "$1" = "--help" ] ; then
  echo "Usage: <version> <key> <type> <suffix>"
  return
fi

version="$1"
key="$2"
type="$3"
suffix="$4"

[ -z $version ] && exit 1
[ -z $key ] && exit 2
[ -z $type ] && exit 3
[ -z $suffix ] && exit 4

PACKAGE_NAME="libsovtoken"
TEMP_ARCH_DIR=./${PACKAGE_NAME}-zip

mkdir ${TEMP_ARCH_DIR}

cp ./target/release/*.dll ${TEMP_ARCH_DIR}/
cp ./target/release/*.dll.lib ${TEMP_ARCH_DIR}/

pushd ${TEMP_ARCH_DIR}
    zip -r ${PACKAGE_NAME}_${version}.zip ./*
    mv ${PACKAGE_NAME}_${version}.zip ..
popd

rm -rf ${TEMP_ARCH_DIR}

cat <<EOF | sftp -v -oStrictHostKeyChecking=no -i $key repo@$SOVRIN_REPO_HOST
mkdir /var/repository/repos/windows/$PACKAGE_NAME/$type/$version$suffix
cd /var/repository/repos/windows/$PACKAGE_NAME/$type/$version$suffix
put -r ${PACKAGE_NAME}_"${version}".zip
ls -l /var/repository/repos/windows/$PACKAGE_NAME/$type/$version$suffix
EOF
