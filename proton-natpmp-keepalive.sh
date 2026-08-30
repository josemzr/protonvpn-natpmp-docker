#!/bin/bash


#### Author
# github.com/blomstertj
#### Description
# natpmpc port forward map request loop
#
# based on Proton's support article here: https://protonvpn.com/support/port-forwarding-manual-setup#linux
# original command line from article: 
# while true ; do date ; natpmpc -a 1 0 udp 60 -g 10.2.0.1 && natpmpc -a 1 0 tcp 60 -g 10.2.0.1 || { echo -e "ERROR with natpmpc command \a" ; break ; } ; sleep 45 ; done
#
# this script is an enhanced version of the original command line from the article:
# pipes all natpmpc output to temp files and uses grep/awk to parse results and errors
# echos to console the public IP from ip.me, the public IP from natpmp, and the mapped ports if successful
# if any step fails then the script will output the command output for debugging and reduce loop wait time

umask 077

# NAT-PMP settings. Distinct private ports identify independent mappings when
# multiple instances share the same VPN connection.
protonGwIp="${NATPMP_GATEWAY:-10.2.0.1}"
natPmpPublicPort="${NATPMP_PUBLIC_PORT:-1}"
natPmpPrivatePort="${NATPMP_PRIVATE_PORT:-0}"
natPmpLifetime="${NATPMP_LIFETIME:-60}"
scriptSuccessWaitTime="${NATPMP_REFRESH_INTERVAL:-45}"
mappingName="${NATPMP_MAPPING_NAME:-default}"
runOnce="${NATPMP_RUN_ONCE:-false}"
portSyncTarget="${PORT_SYNC_TARGET:-}"
portSyncUrl="${PORT_SYNC_URL%/}"
portSyncUsername="${PORT_SYNC_USERNAME:-}"
portSyncPassword="${PORT_SYNC_PASSWORD:-}"
portSyncRestartProcess="${PORT_SYNC_RESTART_PROCESS:-}"
portPublishPort="${PORT_PUBLISH_PORT:-}"
portPublishDir='/tmp/natpmp-port'

validatePort() {
	local name="$1"
	local value="$2"
	if [[ ! "$value" =~ ^[0-9]+$ ]] || (( value < 0 || value > 65535 ))
	then
		echo "$name must be an integer between 0 and 65535; got '$value'." >&2
		exit 1
	fi
}

validatePositiveInteger() {
	local name="$1"
	local value="$2"
	if [[ ! "$value" =~ ^[0-9]+$ ]] || (( value < 1 ))
	then
		echo "$name must be a positive integer; got '$value'." >&2
		exit 1
	fi
}

validatePort 'NATPMP_PUBLIC_PORT' "$natPmpPublicPort"
validatePort 'NATPMP_PRIVATE_PORT' "$natPmpPrivatePort"
validatePositiveInteger 'NATPMP_LIFETIME' "$natPmpLifetime"
validatePositiveInteger 'NATPMP_REFRESH_INTERVAL' "$scriptSuccessWaitTime"

if (( scriptSuccessWaitTime >= natPmpLifetime ))
then
	echo 'NATPMP_REFRESH_INTERVAL must be lower than NATPMP_LIFETIME.' >&2
	exit 1
fi

if [[ -n "$portSyncTarget" && "$portSyncTarget" != 'qbittorrent' && "$portSyncTarget" != 'amule' ]]
then
	echo "PORT_SYNC_TARGET must be 'qbittorrent', 'amule', or empty; got '$portSyncTarget'." >&2
	exit 1
fi

if [[ -n "$portSyncTarget" && -z "$portSyncUrl" ]]
then
	echo 'PORT_SYNC_URL is required when PORT_SYNC_TARGET is set.' >&2
	exit 1
fi

if [[ "$portSyncTarget" == 'amule' && -z "$portSyncPassword" ]]
then
	echo 'PORT_SYNC_PASSWORD is required for aMule synchronization.' >&2
	exit 1
fi

if [[ -n "$portPublishPort" ]]
then
	validatePort 'PORT_PUBLISH_PORT' "$portPublishPort"
	if (( portPublishPort == 0 ))
	then
		echo 'PORT_PUBLISH_PORT must be greater than zero.' >&2
		exit 1
	fi
	mkdir -p "$portPublishDir"
	printf 'unavailable\n' > "$portPublishDir/index.html"
	httpd -p "0.0.0.0:$portPublishPort" -h "$portPublishDir"
fi

publishMappedPort() {
	local port="$1"
	[[ -z "$portPublishPort" ]] && return 0
	printf '%s\n' "$port" > "$portPublishDir/index.html.tmp" && \
		mv "$portPublishDir/index.html.tmp" "$portPublishDir/index.html"
}

restartSupervisedProcess() {
	local processName="$1"
	local commFile pid

	[[ -z "$processName" ]] && return 0
	for commFile in /proc/[0-9]*/comm
	do
		[[ -r "$commFile" ]] || continue
		if [[ "$(cat "$commFile")" == "$processName" ]]
		then
			pid="${commFile#/proc/}"
			pid="${pid%/comm}"
			kill -TERM "$pid"
			if [[ $verbose == true ]]
			then
				echo "Requested restart of supervised process: $processName"
			fi
			return 0
		fi
	done

	echo "Could not find process '$processName' to restart." >&2
	return 1
}

syncQbittorrentPort() {
	local port="$1"
	local cookieFile='/tmp/qbittorrent-cookie'
	local currentPort response
	local encodedUsername encodedPassword
	local -a curlArgs=(--silent --show-error --fail --compressed --connect-timeout 2 --max-time 5)

	rm -f "$cookieFile"
	trap 'rm -f "$cookieFile"; trap - RETURN' RETURN
	if [[ -n "$portSyncUsername" || -n "$portSyncPassword" ]]
	then
		encodedUsername=$(printf '%s' "$portSyncUsername" | jq -sRr @uri) || return 1
		encodedPassword=$(printf '%s' "$portSyncPassword" | jq -sRr @uri) || return 1
		response=$(printf 'username=%s&password=%s' "$encodedUsername" "$encodedPassword" | \
			curl "${curlArgs[@]}" --cookie-jar "$cookieFile" \
			--header "Referer: $portSyncUrl" \
			--header 'Content-Type: application/x-www-form-urlencoded' \
			--data-binary @- \
			"$portSyncUrl/api/v2/auth/login") || return 1
		[[ "$response" == 'Ok.' ]] || { echo 'qBittorrent authentication failed.' >&2; return 1; }
		curlArgs+=(--cookie "$cookieFile")
	fi

	currentPort=$(curl "${curlArgs[@]}" --header "Referer: $portSyncUrl" \
		"$portSyncUrl/api/v2/app/preferences" | jq -er '.listen_port') || return 1
	if [[ "$currentPort" == "$port" ]]
	then
		return 0
	fi

	curl "${curlArgs[@]}" --header "Referer: $portSyncUrl" \
		--data-urlencode "json={\"listen_port\":$port,\"random_port\":false,\"upnp\":false}" \
		"$portSyncUrl/api/v2/app/setPreferences" >/dev/null || return 1
	currentPort=$(curl "${curlArgs[@]}" --header "Referer: $portSyncUrl" \
		"$portSyncUrl/api/v2/app/preferences" | jq -er '.listen_port') || return 1
	[[ "$currentPort" == "$port" ]] || { echo 'qBittorrent port verification failed.' >&2; return 1; }
	if [[ $verbose == true ]]
	then
		echo "Updated qBittorrent listening port: $port"
	fi
}

syncAmulePort() {
	local port="$1"
	local loginResponse token currentTcpPort currentUdpPort preferences
	local bearerConfig='/tmp/amule-bearer.conf'
	local -a curlArgs=(--silent --show-error --fail --compressed --connect-timeout 2 --max-time 5)

	rm -f "$bearerConfig"
	trap 'rm -f "$bearerConfig"; trap - RETURN' RETURN
	loginResponse=$(printf '%s' "$portSyncPassword" | jq -Rs '{password:.}' | \
		curl "${curlArgs[@]}" --request POST \
		--header 'Content-Type: application/json' \
		--header 'Accept: application/jwt' \
		--data-binary @- \
		"$portSyncUrl/api/v0/auth/login") || return 1
	token=$(jq -er '.token' <<< "$loginResponse") || return 1
	printf 'header = "Authorization: Bearer %s"\n' "$token" > "$bearerConfig"
	chmod 600 "$bearerConfig"
	preferences=$(curl "${curlArgs[@]}" --config "$bearerConfig" \
		"$portSyncUrl/api/v0/preferences") || return 1
	currentTcpPort=$(jq -er '.connection.tcp_port' <<< "$preferences") || return 1
	currentUdpPort=$(jq -er '.connection.udp_port' <<< "$preferences") || return 1
	if [[ "$currentTcpPort" == "$port" && "$currentUdpPort" == "$port" ]]
	then
		if [[ -n "$portSyncRestartProcess" && "$amuleRestartedPort" != "$port" ]]
		then
			restartSupervisedProcess "$portSyncRestartProcess" || return 1
			amuleRestartedPort="$port"
		fi
		return 0
	fi

	preferences=$(curl "${curlArgs[@]}" --config "$bearerConfig" --request PATCH \
		--header 'Content-Type: application/json' \
		--data "{\"connection\":{\"tcp_port\":$port,\"udp_port\":$port}}" \
		"$portSyncUrl/api/v0/preferences") || return 1
	currentTcpPort=$(jq -er '.connection.tcp_port' <<< "$preferences") || return 1
	currentUdpPort=$(jq -er '.connection.udp_port' <<< "$preferences") || return 1
	[[ "$currentTcpPort" == "$port" && "$currentUdpPort" == "$port" ]] || {
		echo 'aMule port verification failed.' >&2
		return 1
	}
	if [[ $verbose == true ]]
	then
		echo "Updated aMule TCP/UDP ports: $port"
	fi
	restartSupervisedProcess "$portSyncRestartProcess" || return 1
	amuleRestartedPort="$port"
}

syncApplicationPort() {
	local port="$1"
	case "$portSyncTarget" in
		'') return 0 ;;
		qbittorrent) syncQbittorrentPort "$port" ;;
		amule) syncAmulePort "$port" ;;
	esac
}
# the key name for the public IP returned by natpmpc
readNatPmpRespPublicIpStr='Public IP'
# if a NAT response returns a success then the output will have the following format
readNatPmpRespSuccessRegex='readnatpmpresponseorretry returned [0-9]+ \((OK|SUCCESS)\)'
# if port mapping is successful then the output will have the following format for UDP/TCP
readNatPmpPortMapRespRegex='Mapped public port [0-9]+ protocol (UDP|TCP)'
# divider for natpmpc output if errors
cmdOutputDivider='================================================'
# divider between loop iterations
outputDivider='================================================================================================'
# verbose output
checkCompactOutputEnv=$(printenv COMPACT_OUTPUT)
if [[ $checkCompactOutputEnv == 'true' ]]
then
	verbose=false
else
	verbose=true
fi
# skip ip.me check
checkSkipIpMeEnv=$(printenv SKIP_IPME_CHECK)
if [[ $checkSkipIpMeEnv == 'true' ]]
then
	skipIpMeCheck=true
else
	skipIpMeCheck=false
fi


amuleRestartedPort=''
while true; do
	echo "$outputDivider"
	loopStartedAt=$SECONDS
	if [[ $verbose == true ]]
	then
		echo "Mapping: $mappingName (public request: $natPmpPublicPort, private: $natPmpPrivatePort)"
	fi
	#### initialize variables for this loop iteration
	curlPublicIp=''
	natPmpPublicIp=''
	testNatPmpAllowed=''
	testUdpPortMap=''
	mappedUdpPort=''
	testTcpPortMap=''
	mappedTcpPort=''
	echo '' > /tmp/natpmpc_allowed
	echo '' > /tmp/natpmpc_udp_output
	echo '' > /tmp/natpmpc_tcp_output
	scriptWaitTime="$scriptSuccessWaitTime"
	
	#### get public IP from curl to Proton operated ip.me
	if [[ $skipIpMeCheck == false ]]
	then
		# this should always match what natpmp returns
		# should only be different if we're not connected to VPN
		curlPublicIp=$(curl --silent ip.me)
		echo "Public IP (ip.me): $curlPublicIp"
	fi
	#### test if the gateway allows port forwarding
	# this will take a long time if we're not connected to VPN
	# or not on a P2P enabled server
	if [[ $verbose == true ]]
	then
		echo "Target Gateway IP: $protonGwIp"
		echo 'Testing if the gateway allows port forwarding...'
	fi
	# test if this server allows port forwarding
	natpmpc -g "$protonGwIp" &> /tmp/natpmpc_allowed
	# grab the read response/retry lines
	testNatPmpAllowed=$(grep -E "$readNatPmpRespSuccessRegex" /tmp/natpmpc_allowed)
	natPmpPublicIp=$(grep "$readNatPmpRespPublicIpStr" /tmp/natpmpc_allowed | cut -d ':' -f 2 | xargs)
	echo "Public IP (natpmp): $natPmpPublicIp"
	#### if the gateway allows port forwarding then request ports
	# if not allowed or test error then warn user and reduce wait time
	if [[ -z "$testNatPmpAllowed" ]]
	then
		echo 'NAT PMP test failed. Make sure your chosen server is P2P enabled. Make sure this containers traffic is routed through the VPN tunnel. Command output:'
		echo "$cmdOutputDivider"
		cat /tmp/natpmpc_allowed
		echo "$cmdOutputDivider"
		scriptWaitTime=10
	#### if allowed then request port fowarding for UDP/TCP for 60 second lifetime
	else
		#### UDP port forward request
		if [[ $verbose == true ]]
		then
			echo 'Sending UDP port forward request...'
		fi
		natpmpc -a "$natPmpPublicPort" "$natPmpPrivatePort" udp "$natPmpLifetime" -g "$protonGwIp" &> /tmp/natpmpc_udp_output
		# grab the read response/retry lines
		testUdpPortMap=$(grep -E "$readNatPmpRespSuccessRegex" /tmp/natpmpc_udp_output)
		# if test failed then warn user and reduce wait time
		if [[ -z "$testUdpPortMap" ]]
		then
			echo 'UDP port mapping failed. Command output:'
			echo "$cmdOutputDivider"
			cat /tmp/natpmpc_udp_output
			echo "$cmdOutputDivider"
			scriptWaitTime=10
		# if mapping was successful then display port
		else
			mappedUdpPort=$(grep -E "$readNatPmpPortMapRespRegex" /tmp/natpmpc_udp_output | awk '{print $4}')
			echo "Forwarded port (UDP): $mappedUdpPort"
		fi
		#### TCP port forward request
		if [[ $verbose == true ]]
		then
			echo 'Sending TCP port forward request...'
		fi
		natpmpc -a "$natPmpPublicPort" "$natPmpPrivatePort" tcp "$natPmpLifetime" -g "$protonGwIp" &> /tmp/natpmpc_tcp_output
		# grab the read response/retry lines
		testTcpPortMap=$(grep -E "$readNatPmpRespSuccessRegex" /tmp/natpmpc_tcp_output)
		# if test failed then warn user and reduce wait time
		if [[ -z "$testTcpPortMap" ]]
		then
			echo 'TCP port mapping failed. Command output:'
			echo "$cmdOutputDivider"
			cat /tmp/natpmpc_tcp_output
			echo "$cmdOutputDivider"
			scriptWaitTime=10
		# if mapping was successful then display port
		else
			mappedTcpPort=$(grep -E "$readNatPmpPortMapRespRegex" /tmp/natpmpc_tcp_output | awk '{print $4}')
			echo "Forwarded port (TCP): $mappedTcpPort"
		fi
		if [[ -n "$mappedUdpPort" && "$mappedUdpPort" == "$mappedTcpPort" ]]
		then
			if ! syncApplicationPort "$mappedTcpPort" || ! publishMappedPort "$mappedTcpPort"
			then
				echo "Failed to synchronize or publish port $mappedTcpPort; retrying next loop." >&2
				scriptWaitTime=10
			fi
		elif [[ -n "$portSyncTarget" ]]
		then
			echo 'TCP and UDP mappings differ; application port was not changed.' >&2
			scriptWaitTime=10
		fi
	fi
	#### loop complete
	# delay next iteration by 10 or 45 seconds
	if [[ $verbose == true ]]
	then
		echo "Waiting $scriptWaitTime seconds before next port forward request..."
	fi
	echo "$outputDivider"
	if [[ "$runOnce" == 'true' ]]
	then
		break
	fi
	maxWaitTime=$((natPmpLifetime - 5 - (SECONDS - loopStartedAt)))
	(( maxWaitTime < 1 )) && maxWaitTime=1
	if (( scriptWaitTime > maxWaitTime ))
	then
		scriptWaitTime=$maxWaitTime
	fi
	sleep $scriptWaitTime
done
