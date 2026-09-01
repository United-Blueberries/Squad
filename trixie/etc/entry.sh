#!/bin/bash

run_steamcmd() {
	local attempt
	for attempt in 1 2 3; do
		if bash "${STEAMCMDDIR}/steamcmd.sh" "$@"; then
			return 0
		fi
		echo "steamcmd command failed (attempt ${attempt}/3), retrying..." >&2
		sleep 5
	done
	return 1
}

if [ -n "${STEAM_BETA_BRANCH}" ]
then
	echo "Loading Steam Beta Branch"
	run_steamcmd +force_install_dir "${STEAMAPPDIR}" \
					+login anonymous \
					+app_update "${STEAM_BETA_APP}" \
					-beta "${STEAM_BETA_BRANCH}" \
					-betapassword "${STEAM_BETA_PASSWORD}" \
					validate \
					+quit
else
	echo "Loading Steam Release Branch"
	run_steamcmd +force_install_dir "${STEAMAPPDIR}" \
					+login anonymous \
					+app_update "${STEAMAPPID}" \
					validate \
					+quit
fi || { echo "steamcmd failed to update Squad after 3 attempts, aborting" >&2; exit 1; }

# Change rcon port on first launch, because the default config overwrites the commandline parameter (you can comment this out if it has done it's purpose)
sed -i -e 's/Port=21114/'"Port=${RCONPORT}"'/g' "${STEAMAPPDIR}/SquadGame/ServerConfig/Rcon.cfg"

if [[ -n "${SERVER_NAME}" ]]; then
	echo "Setting server name in Server.cfg"
	sed -i -e "s/^ServerName=.*/ServerName=\"${SERVER_NAME}\"/" "${STEAMAPPDIR}/SquadGame/ServerConfig/Server.cfg"
fi

echo "Clearing Mods..."
# Clear all workshop mods:
# find all folders / files in mods folder which are numeric only;
# remove the workshop mods
find "${MODPATH}"/* -maxdepth 0 -regextype posix-egrep -regex ".*/[[:digit:]]+" | xargs -0 -d"\n" rm -R 2>/dev/null

# Install mods (if defined)
declare -a MODS="${MODS}"
if (( ${#MODS[@]} ))
then
	echo "Installing Mods..."
	for MODID in "${MODS[@]}"; do
		echo "> Install mod '${MODID}'"
		run_steamcmd +force_install_dir "${STEAMAPPDIR}" +login anonymous +workshop_download_item "${WORKSHOPID}" "${MODID}" +quit \
			|| echo "Warning: failed to download mod '${MODID}', continuing..." >&2

		echo -e "\n> Link mod content '${MODID}'"
		ln -s "${STEAMAPPDIR}/steamapps/workshop/content/${WORKSHOPID}/${MODID}" "${MODPATH}/${MODID}"
	done
fi

if [[ -n "${MULTIHOME}" && "${MULTIHOME}" != "0.0.0.0" && "${MULTIHOME}" != "127.0.0.1" ]]; then
	MULTIHOME_PARAM="MULTIHOME=\"${MULTIHOME}\""
else
	MULTIHOME_PARAM=""
fi

bash "${STEAMAPPDIR}/SquadGameServer.sh" \
			"${MULTIHOME_PARAM}" \
			Port="${PORT}" \
			QueryPort="${QUERYPORT}" \
			RCONPORT="${RCONPORT}" \
			FIXEDMAXPLAYERS="${FIXEDMAXPLAYERS}" \
			FIXEDMAXTICKRATE="${FIXEDMAXTICKRATE}" \
			beaconport="${BEACONPORT}" \
			RANDOM="${RANDOM}" \
			-useperfthreads
