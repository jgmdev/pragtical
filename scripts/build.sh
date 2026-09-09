#!/bin/bash
set -e

if [ ! -e "src/api/api.h" ]; then
  echo "Please run this script from the root directory of Pragtical."; exit 1
fi

source scripts/common.sh

show_help() {
  echo
  echo "Usage: $0 <OPTIONS>"
  echo
  echo "Available options:"
  echo
  echo "-b --builddir DIRNAME         Sets the name of the build directory (not path)."
  echo "                              Default: '$(get_default_build_dir)'."
  echo "   --debug                    Debug this script."
  echo "-f --forcefallback            Force to build dependencies statically."
  echo "-h --help                     Show this help and exit."
  echo "-p --prefix PREFIX            Install directory prefix. Default: '/'."
  echo "-B --bundle                   Create an App bundle (macOS only)"
  echo "-P --portable                 Create a portable binary package."
  echo "-O --pgo                      Use profile guided optimizations (pgo)."
  echo "-L --lto                      Enables Link-Time Optimization (LTO)."
  echo "-r --release                  Compile in release mode."
  echo "   --cross-platform PLATFORM  Cross compile for this platform."
  echo "                              The script will find the appropriate"
  echo "                              cross file in 'resources/cross'."
  echo "   --cross-arch ARCH          Cross compile for this architecture."
  echo "                              The script will find the appropriate"
  echo "                              cross file in 'resources/cross'."
  echo "   --cross-file CROSS_FILE    Cross compile with the given cross file."
  echo
}

main() {
  local platform="$(get_platform_name)"
  local arch="$(get_platform_arch)"
  local build_dir="$(get_default_build_dir)"
  local build_type="debugoptimized"
  local prefix=/
  local force_fallback
  local bundle
  local portable
  local pgo
  local lto
  local cross
  local cross_platform
  local cross_arch
  local cross_file

  local lua_subproject_path

  for i in "$@"; do
    case $i in
      -h|--help)
        show_help
        exit 0
        ;;
      -b|--builddir)
        build_dir="$2"
        shift
        shift
        ;;
      --debug)
        set -x
        shift
        ;;
      -f|--forcefallback)
        force_fallback="--wrap-mode=forcefallback"
        shift
        ;;
      -p|--prefix)
        prefix="$2"
        shift
        shift
        ;;
      -B|--bundle)
        if [[ "$platform" != "macos" ]]; then
          echo "Warning: ignoring --bundle option, works only under macOS."
        else
          bundle="-Dbundle=true"
        fi
        shift
        ;;
      -P|--portable)
        portable="-Dportable=true"
        shift
        ;;
      -O|--pgo)
        pgo="-Db_pgo=generate"
        shift
        ;;
      -L|--lto)
        lto="-Db_lto=true"
        shift
        ;;
      --cross-arch)
        cross="true"
        cross_arch="$2"
        shift
        shift
        ;;
      --cross-platform)
        cross="true"
        cross_platform="$2"
        shift
        shift
        ;;
      --cross-file)
        cross="true"
        cross_file="$2"
        shift
        shift
        ;;
      -r|--release)
        build_type="release"
        shift
        ;;
      *)
        # unknown option
        ;;
    esac
  done

  if [[ -n $1 ]]; then
    show_help
    exit 1
  fi

  if [[ $platform == "macos" && -n $bundle && -n $portable ]]; then
      echo "Warning: \"bundle\" and \"portable\" specified; excluding portable package."
      portable=""
  fi

  # if CROSS_ARCH is used, it will be picked up
  cross="${cross:-$CROSS_ARCH}"
  if [[ -n "$cross" ]]; then
    if [[ -n "$cross_file" ]] && ([[ -z "$cross_arch" ]] || [[ -z "$cross_platform" ]]); then
      echo "Warning: --cross-platform or --cross-platform not set; guessing it from the filename."
      # remove file extensions and directories from the path
      cross_file_name="${cross_file##*/}"
      cross_file_name="${cross_file_name%%.*}"
      # cross_platform is the string before encountering the first hyphen
      if [[ -z "$cross_platform" ]]; then
        cross_platform="${cross_file_name%%-*}"
        echo "Warning: Guessing --cross-platform $cross_platform"
      fi
      # cross_arch is the string after encountering the first hyphen
      if [[ -z "$cross_arch" ]]; then
        cross_arch="${cross_file_name#*-}"
        echo "Warning: Guessing --cross-arch $cross_arch"
      fi
    fi
    platform="${cross_platform:-$platform}"
    arch="${cross_arch:-$arch}"
    cross_file=("--cross-file" "${cross_file:-resources/cross/$platform-$arch.ini}")
    # reload build_dir because platform and arch might change
    build_dir="$(get_default_build_dir "$platform" "$arch")"
  fi

  # arch and platform specific stuff
  if [[ "$platform" == "macos" ]]; then
    macos_version_min="10.11"
    if [[ "$arch" == "arm64" ]]; then
      macos_version_min="11.0"
    fi
    export MACOSX_DEPLOYMENT_TARGET="$macos_version_min"
    export MIN_SUPPORTED_MACOSX_DEPLOYMENT_TARGET="$macos_version_min"
    export CFLAGS="-mmacosx-version-min=$macos_version_min"
    export CXXFLAGS="-mmacosx-version-min=$macos_version_min"
    export LDFLAGS="-mmacosx-version-min=$macos_version_min"
  fi

  rm -rf "${build_dir}"

  # Download the subprojects so we can copy plugin manager,
  # this will prevent reconfiguring the project.
  if [[ $platform == "windows" ]]; then
    # on windows file locks can occur so 1 job at a time
    meson subprojects download -j 1
  else
    meson subprojects download
  fi

  # Enable ppm only for windows 32 Bits which binary download is not available
  local ppm="-Dppm=false"
  if [[ $platform == "windows" && $arch == "i686" ]]; then
    ppm="-Dppm=true"
  fi

  CFLAGS=$CFLAGS LDFLAGS=$LDFLAGS meson setup \
    --buildtype=$build_type \
    --prefix "$prefix" \
    $ppm \
    "${cross_file[@]}" \
    $force_fallback \
    $bundle \
    $portable \
    $pgo \
    $lto \
    -Doptimization=3 \
    "${build_dir}"

  local profile_dir
  if [[ -n $pgo ]]; then
    local compiler_id
    compiler_id=$(meson introspect --compilers "${build_dir}" | python3 -c \
      'import json, sys; print(json.load(sys.stdin)["host"]["c"]["id"])')
    if [[ $compiler_id == *clang* ]]; then
      # Capture both build tools and the editor, regardless of runtime chdir.
      profile_dir="$(cd "${build_dir}" && pwd)/pgo"
      mkdir -p "$profile_dir"
      export LLVM_PROFILE_FILE="$profile_dir/default_%m.profraw"
    fi
  fi

  meson compile -C "${build_dir}"

  if [[ $pgo != "" ]]; then
    echo "Generating Profiler Guided Optimizations data..."
    export SDL_VIDEO_DRIVER="dummy"
    local timeout_command=timeout
    if [[ $platform == "macos" ]]; then
      timeout_command=gtimeout
    fi
    # Let pgo.lua's five-minute limit quit cleanly so LLVM can flush profiles.
    if ! "$timeout_command" --kill-after=10s 330s ./scripts/run-local \
      -debug "${build_dir}" run -n scripts/lua/pgo.lua; then
      echo "Error: PGO training failed; refusing to build with incomplete profiles." >&2
      return 1
    fi
    if [[ -n $profile_dir ]]; then
      local profiles=("$profile_dir"/*.profraw)
      if [[ ! -f ${profiles[0]} ]]; then
        echo "Error: PGO training produced no LLVM profiles in $profile_dir." >&2
        return 1
      fi
      if [[ $platform == "macos" ]]; then
        xcrun llvm-profdata merge -output="${build_dir}"/default.profdata "${profiles[@]}"
      else
        if command -v llvm-profdata-14 ; then
          llvm-profdata-14 merge -output="${build_dir}"/default.profdata "${profiles[@]}"
        else
          llvm-profdata merge -output="${build_dir}"/default.profdata "${profiles[@]}"
        fi
      fi
      if [[ ! -s "${build_dir}/default.profdata" ]]; then
        echo "Error: LLVM profile merge did not produce default.profdata." >&2
        return 1
      fi
    fi
    meson configure -Db_pgo=use "${build_dir}"
    meson compile -C "${build_dir}"
  fi
}

main "$@"
