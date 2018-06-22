#!/bin/bash

RUST_DIR=".."
MODE="build"
DOCKERFILE="ubuntu.dockerfile"
DOCKERIMAGE="libsovtoken"
APT_INSTALL="stable"
INDY_CHECKOUT_URL=""
INDY_GIT_CHECKOUT_DIR="/tmp/indy-sdk"
INDY_GIT_CHECKOUT_OVERWRITE=0
INDY_LOCAL_DIR=""
GIT_SHALLOW_CLONE=0
GIT_BRANCH="master"
REBUILD=0

__usage() {
    cat <<EOT
    Usage: $0 [options]

    Options:
        -h  Display this message
        -a  Install libindy using apt package manager from a specific channel. Default: '${APT_INSTALL}'.
            Can be 'master|stable|rc'. This is the default method for install libindy.
            Options -i or -g will cause this option to be ignored.
        -b  Use named branch for git clone. Default: '${GIT_BRANCH}'
            Can be 'master|tags/v1.4|stable'.
        -c  Run a custom command instead of cargo \$mode.
            This is useful when you need to use more options with cargo
            like 'cargo test -- --nocapture' or 'cargo build --verbose'
        -d  Directory to find libsovtoken/src/Cargo.toml. Default: '${RUST_DIR}'
        -D  Local directory where to clone libindy. Default: '${INDY_GIT_CHECKOUT_DIR}'
            This option will be selected over -g if both are used.
        -f  Dockerfile to use to for building docker instance. Default: '${DOCKERFILE}'
        -g  Use git to clone libindy from this URL and compile from source.
            Example: https://github.com/hyperledger/indy-sdk.git.
        -i  Compile libindy from local source directory.
        -m  The mode to run cargo inside docker. Default: '${MODE}'.
            Valid options are 'build|release|test'.
        -n  Name to give the built docker image. Default: '${DOCKERIMAGE}'
        -o  When combined with -g, force git clone in existing directory overwriting existing contents.
            Default: '${INDY_GIT_CHECKOUT_OVERWRITE}'
        -r  Combined with -i or -g, will force rebuilding of libindy. Default: '${REBUILD}'
        -s  Shallow cloning libindy git installations
EOT
}


while getopts ':a:b:c:d:D:f:g:hi:m:n:ors' opt
do
    case "${opt}" in
        a) APT_INSTALL="${OPTARG}" ;;
        b) GIT_BRANCH="${OPTARG}" ;;
        c) COMMANDS="${OPTARG}" ;;
        d) RUST_DIR="${OPTARG}" ;;
        D) INDY_GIT_CHECKOUT_DIR="${OPTARG}" ;;
        f) DOCKERFILE="${OPTARG}" ;;
        g) INDY_CHECKOUT_URL="${OPTARG}" ;;
        h) __usage; exit 0 ;;
        i) INDY_LOCAL_DIR="${OPTARG}" ;;
        m) MODE="${OPTARG}" ;;
        n) DOCKERIMAGE="${OPTARG}" ;;
        o) INDY_GIT_CHECKOUT_OVERWRITE=1 ;;
        r) REBUILD=1 ;;
        s) GIT_SHALLOW_CLONE=1 ;;
        \?) echo STDERR "Option does not exist: ${OPTARG}"
            exit 1
            ;;
    esac
done
shift $((OPTIND-1))

if [ ! -z "${COMMANDS}" ] ; then
    echo "Running custom command ${COMMANDS}"
    CMD="${COMMANDS}"
else
    case "${MODE}" in
        test) CMD="cargo test --color=always -- --nocapture" ;;
        build) CMD="cargo build --color=always" ;;
        release) CMD="cargo build --color=always --release" ;;
        \?) echo STDERR "Unknown MODE specified"
            exit 1
            ;;
    esac
fi


INDY_INSTALL_METHOD="package"

if [ ! -z "${INDY_LOCAL_DIR}" ] ; then
    INDY_INSTALL_METHOD="build"

    if [ ! -d "${INDY_LOCAL_DIR}" ] ; then
        echo STDERR "${INDY_LOCAL_DIR} does not exist"
        exit 1
    fi
elif [ ! -z "${INDY_CHECKOUT_URL}" ] ; then
    INDY_INSTALL_METHOD="build"

    CLONE=1
    CHECK_REV=1
    if [ -d "${INDY_GIT_CHECKOUT_DIR}" ] ; then
        echo "${INDY_GIT_CHECKOUT_DIR} exists"

        if [ ${INDY_GIT_CHECKOUT_OVERWRITE} -eq 1 ] ; then
            echo "Overwriting ${INDY_GIT_CHECKOUT_DIR}"
            rm -rf ${INDY_GIT_CHECKOUT_DIR}
        else
            CLONE=0
        fi
    fi

    if [ ${CLONE} -eq 1 ] ; then
        CHECK_REV=0
        REBUILD=1
        if [ ${GIT_SHALLOW_CLONE} -eq 1 ] ; then
            echo "Shallow cloning indy-sdk repo ${INDY_CHECKOUT_URL} branch ${GIT_BRANCH}"
            git clone --depth 1 --branch ${GIT_BRANCH} ${INDY_CHECKOUT_URL} ${INDY_GIT_CHECKOUT_DIR}
        else
            echo "Cloning indy-sdk repo ${INDY_CHECKOUT_URL} branch ${GIT_BRANCH}"
            git clone --branch ${GIT_BRANCH} ${INDY_CHECKOUT_URL} ${INDY_GIT_CHECKOUT_DIR}
        fi
    fi

    if [ ${CHECK_REV} -eq 1 ] ; then
        GIT_REV=$(git --git-dir "${INDY_GIT_CHECKOUT_DIR}/.git" branch | head -n 1 | sed -e 's/^..//g')
        echo "Current indy-sdk branch set to ${GIT_REV}"
        MATCH=$(echo ${GIT_REV} | egrep "${GIT_BRANCH}")

        if [ -z "${MATCH}" ] ; then
            echo "Changing branch to ${GIT_BRANCH}"
            git --git-dir "${INDY_GIT_CHECKOUT_DIR}/.git" checkout ${GIT_BRANCH}
            REBUILD=1

            if [ $? -ne 0 ] ; then
                echo STDERR "Could not change branch to ${GIT_BRANCH}"
                exit 1
            fi
        fi
    fi
    INDY_LOCAL_DIR=${INDY_GIT_CHECKOUT_DIR}
fi

if [ ! -z "$@" ] ; then
    echo STDERR "Ignoring other parameters $@"
fi

DOCKER_IMAGE_ID=$(docker image ls | grep ${DOCKERIMAGE} | perl -pe 's/\s+/ /g' | cut -d ' ' -f 3)

if [ "${RUST_DIR:0:1}" = '/' ] ; then
    BUILD_DIR=${RUST_DIR}
else
    BUILD_DIR="${PWD}/${RUST_DIR}"
fi

echo "Using libsovtoken in ${BUILD_DIR}"

if [ -z "${DOCKER_IMAGE_ID}" ] ; then
    echo "Docker image ${DOCKERIMAGE} does not exist"
    echo "Docker image will be built with ${DOCKERFILE}"
    APT_CMD=""
    INDY_PKG=""
    if [ "${INDY_INSTALL_METHOD}" == "package" ] ; then
        APT_CMD="apt-key adv --keyserver keyserver.ubuntu.com --recv-keys 68DB5E88 && add-apt-repository -y \"deb https://repo.sovrin.org/sdk/deb xenial ${apt_install}\" &&"
        INDY_PKG="libindy"
    fi
    echo "docker build -f ${DOCKERFILE} -t ${DOCKERIMAGE}:latest ${BUILD_DIR}/ci --build-arg apt_cmd=${APT_CMD} --build-arg indy_pkg=${INDY_PKG}"
    docker build -f ${DOCKERFILE} -t ${DOCKERIMAGE}:latest ${BUILD_DIR}/ci --build-arg apt_cmd=${APT_CMD} --build-arg indy_pkg=${INDY_PKG}
else
    echo "Using existing docker image ${DOCKERIMAGE}:latest"
fi

echo "Running ${CMD} in docker"
if [ "${INDY_INSTALL_METHOD}" == "build" ] ; then
    CLEAN_CMD=""
    if [ ${REBUILD} -eq 1 ] ; then
        CLEAN_CMD="cargo clean"
    fi
    cat > "${BUILD_DIR}/build.sh" << EOF
pushd /indy-sdk/libindy
${CLEAN_CMD}
cargo build --release
popd
echo "token" | sudo -S cp /indy-sdk/libindy/target/release/libindy.so /usr/lib
export LIBINDY_DIR=/usr/lib
${CMD}
EOF
    echo "Running 'docker run --rm -w /data -v ${INDY_LOCAL_DIR}:/indy-sdk -v "${BUILD_DIR}:/data" -t ${DOCKERIMAGE}:latest bash build.sh'"
    docker run --rm -w /data -v ${INDY_LOCAL_DIR}:/indy-sdk -v "${BUILD_DIR}:/data" -t ${DOCKERIMAGE}:latest bash build.sh
    rm -f "${BUILD_DIR}/build.sh"
else
    echo "Running 'docker run --rm -w /data -v "${BUILD_DIR}:/data" -t ${DOCKERIMAGE}:latest ${CMD}'"
    docker run --rm -w /data -v "${BUILD_DIR}:/data" -t ${DOCKERIMAGE}:latest ${CMD}
fi