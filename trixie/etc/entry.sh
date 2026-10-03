#!/bin/bash
if [ -n "${STEAM_BETA_BRANCH}" ]; then
	echo "Loading Steam Beta Branch"
	APP="${STEAM_BETA_APP}"
	BRANCH="${STEAM_BETA_BRANCH}"
	BRANCH_ARGS=(-beta "${STEAM_BETA_BRANCH}" -betapassword "${STEAM_BETA_PASSWORD}")
else
	echo "Loading Steam Release Branch"
	APP="${STEAMAPPID}"
	BRANCH="public"
	BRANCH_ARGS=()
fi
MANIFEST="${STEAMAPPDIR}/steamapps/appmanifest_${APP}.acf"

# steamcmd isn't persisted, so it self-updates on every container start. The first
# app_update after a self-update often bails ("Timed out waiting for update to start")
# while still printing "Success!". Let it self-update in a throwaway run first.
bash "${STEAMCMDDIR}/steamcmd.sh" +quit

latest_buildid() {
	bash "${STEAMCMDDIR}/steamcmd.sh" +login anonymous +app_info_update 1 +app_info_print "${APP}" +quit 2>/dev/null \
		| sed -n '/"branches"/,$p' | sed -n "/\"${BRANCH}\"/,/}/p" | grep -m1 '"buildid"' | grep -oE '[0-9]+'
}
installed_buildid() {
	# StateFlags 4 = fully installed; anything else means a half-applied update
	grep -q '"StateFlags"[[:space:]]*"4"' "${MANIFEST}" 2>/dev/null || return
	grep -m1 '"buildid"' "${MANIFEST}" | grep -oE '[0-9]+'
}

TARGET="$(latest_buildid)"
echo "Target build for ${APP}/${BRANCH}: ${TARGET:-unknown}, installed: $(installed_buildid || echo none)"

for attempt in 1 2 3; do
	# Validate on retries: forces a checksum pass that repairs files a broken patch left behind
	VALIDATE=()
	(( attempt > 1 )) && VALIDATE=(validate)
	echo "Updating (attempt ${attempt}) ${VALIDATE[*]}"
	bash "${STEAMCMDDIR}/steamcmd.sh" +force_install_dir "${STEAMAPPDIR}" \
		+login anonymous \
		+app_update "${APP}" "${BRANCH_ARGS[@]}" "${VALIDATE[@]}" \
		+quit

	INSTALLED="$(installed_buildid)"
	if [ -z "${TARGET}" ]; then
		echo "Could not query latest build from Steam; starting with installed build ${INSTALLED:-none}"
		break
	fi
	if [ "${INSTALLED}" = "${TARGET}" ]; then
		echo "Install verified at build ${INSTALLED}"
		break
	fi
	echo "Installed build '${INSTALLED:-none}' != target '${TARGET}'"
	if (( attempt == 3 )); then
		echo "Update failed after 3 attempts, not starting an outdated server" >&2
		exit 1
	fi
	sleep 10
done

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
		"${STEAMCMDDIR}/steamcmd.sh" +force_install_dir "${STEAMAPPDIR}" +login anonymous +workshop_download_item "${WORKSHOPID}" "${MODID}" +quit

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
