#!/bin/bash
# Common functions for plasma widget build/install scripts
# Version 1

### Colors
TC_Red='\033[31m'; TC_Orange='\033[33m';
TC_LightGray='\033[90m'; TC_LightRed='\033[91m'; TC_LightGreen='\033[92m'; TC_Yellow='\033[93m'; TC_LightBlue='\033[94m';
TC_Reset='\033[0m'; TC_Bold='\033[1m';
if [ ! -t 1 ]; then
	TC_Red=''; TC_Orange='';
	TC_LightGray=''; TC_LightRed=''; TC_LightGreen=''; TC_Yellow=''; TC_LightBlue='';
	TC_Bold=''; TC_Reset='';
fi

### Echo helpers
echoTC() { echo -e "${2}${1}${TC_Reset}"; }
echoGray() { echoTC "$1" "$TC_LightGray"; }
echoRed() { echoTC "$1" "$TC_Red"; }
echoGreen() { echoTC "$1" "$TC_LightGreen"; }
echoInfo() { echo -e "${TC_LightBlue}[info]${TC_Reset} $1"; }
echoError() { echo -e "${TC_Red}[error]${TC_Reset} $1"; }
echoWarn() { echo -e "${TC_Orange}[warning]${TC_Reset} $1"; }
echoSuccess() { echo -e "${TC_LightGreen}[success]${TC_Reset} $1"; }

### Detect package manager
detectPackageManager() {
	for pm in apt dnf zypper pacman; do
		command -v $pm &> /dev/null && echo "$pm" && return
	done
	echo "unknown"
}

### Suggest package installation command
suggestInstall() {
	local pkgManager="$1" aptPkg="$2" dnfPkg="$3" zypperPkg="$4" pacmanPkg="$5"
	case "$pkgManager" in
		apt)    echo -e "  ${TC_Bold}sudo apt install ${aptPkg}${TC_Reset}" ;;
		dnf)    echo -e "  ${TC_Bold}sudo dnf install ${dnfPkg}${TC_Reset}" ;;
		zypper) echo -e "  ${TC_Bold}sudo zypper install ${zypperPkg}${TC_Reset}" ;;
		pacman) echo -e "  ${TC_Bold}sudo pacman -S ${pacmanPkg}${TC_Reset}" ;;
		*)      echo "  Please install the equivalent package for your distribution." ;;
	esac
}

### Detect Plasma version
detectPlasmaVersion() {
	local v=""
	if command -v plasmashell &> /dev/null; then
		v=$(plasmashell --version 2>/dev/null | grep -oP '\d+' | head -1)
	fi
	if [ -z "$v" ]; then
		command -v kpackagetool6 &> /dev/null && v="6"
		command -v kpackagetool5 &> /dev/null && v="${v:-5}"
	fi
	echo "$v"
}

### Set tool names based on Plasma version
setPlasmaTools() {
	local v="${1:-5}"
	if [ "$v" == "6" ]; then
		KREADCONFIG="kreadconfig6"
		KPACKAGETOOL="kpackagetool6"
		KSTART="kstart"
	else
		KREADCONFIG="kreadconfig5"
		KPACKAGETOOL="kpackagetool5"
		KSTART="kstart5"
	fi
}

### Read package metadata key
readMetadata() {
	$KREADCONFIG --file="$PWD/package/metadata.desktop" --group="Desktop Entry" --key="$1"
}

### Convert metadata.desktop to metadata.json
convertMetadataToJson() {
	if command -v desktoptojson &> /dev/null; then
		desktoptojson --serviceType="plasma-applet.desktop" -i "$PWD/package/metadata.desktop" -o "$PWD/package/metadata.json" 2>&1 || true
		[ -f "$PWD/package/metadata.json" ] && sed -i '{s/ \{4\}/\t/g}' "$PWD/package/metadata.json"
	fi
}

### Check if a command exists, print error and install suggestion if not
requireCommand() {
	local cmd="$1" aptPkg="$2" dnfPkg="$3" zypperPkg="$4" pacmanPkg="$5" desc="${6:-$cmd}"
	if ! command -v "$cmd" &> /dev/null; then
		echoError "Missing: $desc"
		suggestInstall "$(detectPackageManager)" "$aptPkg" "$dnfPkg" "$zypperPkg" "$pacmanPkg"
		return 1
	fi
	return 0
}
