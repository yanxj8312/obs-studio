#!/bin/bash

##############################################################################
# macOS build function
##############################################################################
#
# This script file can be included in build scripts for macOS or run directly
#
##############################################################################

# Halt on errors
set -eE

build_obs() {
    status "Build OBS"
    trap "caught_error 'build app'" ERR

    if [ -z "${CI}" ]; then
        _backup_artifacts
    fi
    step "Configure OBS..."
    _configure_obs

    ensure_dir "${CHECKOUT_DIR}/"
    step "Build OBS targets..."

    if [ "${PRESET}" != "macos-ci-${ARCH}" ]; then
        export NSUnbufferedIO=YES

        set -o pipefail && cmake --build --preset macos-${ARCH} --parallel 2>&1 | xcbeautify

        unset NSUnbufferedIO
    else
        cmake --build --preset macos-${ARCH}
    fi
}

bundle_obs() {
    status "Create relocatable macOS application bundle"
    trap "caught_error 'package app'" ERR

    ensure_dir "${CHECKOUT_DIR}"

    step "Install OBS application bundle..."

    find "build_${ARCH}/UI/${BUILD_CONFIG}" -type d -name "OBS.app" | xargs -I{} cp -r {} "build_${ARCH}"/
}

# Function to configure OBS build
_configure_obs() {
    if [ "${CODESIGN}" ]; then
        read_codesign_ident
    fi

    ensure_dir "${CHECKOUT_DIR}"
    status "Configure OBS build system..."
    trap "caught_error 'configure build'" ERR
    check_ccache

    if [ "${TWITCH_CLIENTID}" -a "${TWITCH_HASH}" ]; then
        TWITCH_OPTIONS="-DTWITCH_CLIENTID='${TWITCH_CLIENTID}' -DTWITCH_HASH='${TWITCH_HASH}'"
    fi

    if [ "${RESTREAM_CLIENTID}" -a "${RESTREAM_HASH}" ]; then
        RESTREAM_OPTIONS="-DRESTREAM_CLIENTID='${RESTREAM_CLIENTID}' -DRESTREAM_HASH='${RESTREAM_HASH}'"
    fi

    if [ "${YOUTUBE_CLIENTID}" -a "${YOUTUBE_CLIENTID_HASH}" -a "${YOUTUBE_SECRET}" -a "{YOUTUBE_SECRET_HASH}" ]; then
        YOUTUBE_OPTIONS="-DYOUTUBE_CLIENTID='${YOUTUBE_CLIENTID}' -DYOUTUBE_CLIENTID_HASH='${YOUTUBE_CLIENTID_HASH}' -DYOUTUBE_SECRET='${YOUTUBE_SECRET}' -DYOUTUBE_SECRET_HASH='${YOUTUBE_SECRET_HASH}'"
    fi

    if [ "${SPARKLE_APPCAST_URL}" -a "${SPARKLE_PUBLIC_KEY}" ]; then
        SPARKLE_OPTIONS="-DSPARKLE_APPCAST_URL=\"${SPARKLE_APPCAST_URL}\" -DSPARKLE_PUBLIC_KEY=\"${SPARKLE_PUBLIC_KEY}\""
    fi

    PRESET="macos-${ARCH}"

    if [ "${CI}" ]; then
        case "${GITHUB_EVENT_NAME}" in
            schedule) PRESET="macos-${ARCH}" ;;
            push)
                if [ "${GITHUB_REF_TYPE}" == 'tag' ]; then
                    PRESET="macos-release-${ARCH}"
                else
                    PRESET="macos-ci-${ARCH}"
                fi
                ;;
            pull_request)
                if [ "${SEEKING_TESTERS}" == '1' ]; then
                    PRESET="macos-${ARCH}"
                else
                    PRESET="macos-ci-${ARCH}"
                fi
                ;;
            *) PRESET="macos-ci-${ARCH}" ;;
        esac
    fi

    cmake -S . --preset ${PRESET} \
        -DCMAKE_INSTALL_PREFIX=${BUILD_DIR}/install \
        -DCMAKE_BUILD_TYPE=${BUILD_CONFIG} \
        -DOBS_CODESIGN_IDENTITY="${CODESIGN_IDENT:--}" \
        ${YOUTUBE_OPTIONS} \
        ${TWITCH_OPTIONS} \
        ${RESTREAM_OPTIONS} \
        ${SPARKLE_OPTIONS} \
        ${QUIET:+-Wno-deprecated -Wno-dev --log-level=ERROR}
}

# Function to backup previous build artifacts
_backup_artifacts() {
    ensure_dir "${CHECKOUT_DIR}"
    if [ -d "${BUILD_DIR}" ]; then
        status "Backup old OBS build artifacts"

        CUR_DATE=$(/bin/date +"%Y-%m-%d@%H%M%S")
        NIGHTLY_DIR="${CHECKOUT_DIR}/nightly-${CUR_DATE}"
        PACKAGE_NAME=$(/usr/bin/find "${BUILD_DIR}" -name "*.dmg" -depth 1 | sort -rn | head -1)

        if [ -d "${BUILD_DIR}/install/OBS.app" ]; then
            step "Back up OBS.app..."
            ensure_dir "${NIGHTLY_DIR}"
            /bin/mv "${CHECKOUT_DIR}/${BUILD_DIR}/install/OBS.app" "${NIGHTLY_DIR}/"
            info "You can find OBS.app in ${NIGHTLY_DIR}"
        fi

        if [ "${PACKAGE_NAME}" ]; then
            step "Back up $(basename "${PACKAGE_NAME}")..."
            ensure_dir "${NIGHTLY_DIR}"
            /bin/mv "../${BUILD_DIR}/$(basename "${PACKAGE_NAME}")" "${NIGHTLY_DIR}/"
            info "You can find ${PACKAGE_NAME} in ${NIGHTLY_DIR}"
        fi
    fi
}

build-obs-standalone() {
    CHECKOUT_DIR="$(/usr/bin/git rev-parse --show-toplevel)"
    PRODUCT_NAME="OBS-Studio"
    DEPS_BUILD_DIR="${CHECKOUT_DIR}/../obs-build-dependencies"
    source "${CHECKOUT_DIR}/CI/include/build_support.sh"
    source "${CHECKOUT_DIR}/CI/include/build_support_macos.sh"

    check_archs
    check_macos_version
    build_obs

    if [ "${BUNDLE}" ]; then
        bundle_obs
    fi
}

print_usage() {
    echo -e "Usage: ${0}\n" \
            "-h, --help                     : Print this help\n" \
            "-q, --quiet                    : Suppress most build process output\n" \
            "-v, --verbose                  : Enable more verbose build process output\n" \
            "-a, --architecture             : Specify build architecture (default: x86_64, alternative: arm64)\n" \
            "-c, --codesign                 : Codesign OBS and all libraries (default: ad-hoc only)\n" \
            "-b, --bundle                   : Create relocatable OBS application bundle in build directory (default: build/install/OBS.app)\n"
}

build-obs-main() {
    if [ -z "${_RUN_OBS_BUILD_SCRIPT}" ]; then
        while true; do
            case "${1}" in
                -h | --help ) print_usage; exit 0 ;;
                -q | --quiet ) export QUIET=TRUE; shift ;;
                -v | --verbose ) export VERBOSE=TRUE; shift ;;
                -a | --architecture ) ARCH="${2}"; shift 2 ;;
                -c | --codesign ) CODESIGN=TRUE; shift ;;
                -b | --bundle ) BUNDLE=TRUE; shift ;;
                -- ) shift; break ;;
                * ) break ;;
            esac
        done

        build-obs-standalone
    fi
}

build-obs-main $*
