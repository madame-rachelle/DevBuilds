#!/usr/local/bin/bash-4.4
# shellcheck disable=SC1090,SC2155

set -o pipefail

# Ensure that critical variables are set in the config
check_config() {
	if [[ -z $MacDeveloperID ]]; then
		echo 'ERROR: MacDeveloperID (Developer ID Application creator) not set in config.' >&2
		return 1
	fi

	if [[ -z $MacDevelopmentTeam ]]; then
		echo 'ERROR: MacDevelopmentTeam (Xcode DEVELOPMENT_TEAM) is not set in config.' >&2
		return 1
	fi
	return 0
}

nproc() {
	sysctl -n hw.ncpu
}

mac_target() {
	declare MacOSVersion=$1
	shift

	export MACOSX_DEPLOYMENT_TARGET="$MacOSVersion"
}

make_dmg() {
	declare VolumeName=$1
	shift
	declare Output=$1
	shift

	declare Ret=0
	if mkdir image; then
		rm -f "$Output"
		if hdiutil create -size 300m -srcfolder ./image -volname "$VolumeName" -fs HFS+ -format UDRW "$Output" &&
		   hdiutil attach -readwrite -noverify -noautoopen "$Output" -mountpoint image; then
			cp -a "$@" ./image &&
			hdiutil detach ./image
			Ret=$?
		fi
		rmdir image
	fi

	if (( Ret == 0 )); then
		hdiutil convert "$Output" -format UDBZ -o "tmp$Output" &&
		mv "tmp$Output" "$Output" &&
		hdiutil internet-enable -yes "$Output"
		return
	fi

	return "$Ret"
}

mount_dmg() {
	declare Image=$1
	shift
	declare Cmd=$1
	shift

	declare Ret=1
	if TempDir=$(mktemp -d); then
		if hdiutil attach -readonly -noverify -noautoopen "$Image" -mountpoint "$TempDir"; then
			declare OrigPwd=$(pwd)
			pushd "$TempDir" &>/dev/null &&
			call "$Cmd" "$OrigPwd" "$@"
			Ret=$?

			popd &> /dev/null || Ret=$?
			hdiutil detach "$TempDir"
		fi
		rmdir "$TempDir"
	fi
	return "$Ret"
}

sign_app() {
	declare Bundle=$1
	shift

	codesign -s "Developer ID Application: $MacDeveloperID" -f --deep "$Bundle"
}

main() {
	# Load modules and configuration
	cd "${0%/*}" || return

	. ~/Library/Preferences/BuildServer/config.sh

	check_config || return

	declare Module
	for Module in modules/*.sh mac/*.sh; do
		. "$Module"
	done

	cd ..
	# shellcheck disable=SC2034
	declare -g BaseWorkingDir=$(pwd)

	# Start building
	parse_args "$@"
	shift $((OPTIND-1))

	run_builds
}

main "$@" || exit
