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


# NAT-PMP settings. Distinct private ports identify independent mappings when
# multiple instances share the same VPN connection.
protonGwIp="${NATPMP_GATEWAY:-10.2.0.1}"
natPmpPublicPort="${NATPMP_PUBLIC_PORT:-1}"
natPmpPrivatePort="${NATPMP_PRIVATE_PORT:-0}"
natPmpLifetime="${NATPMP_LIFETIME:-60}"
scriptSuccessWaitTime="${NATPMP_REFRESH_INTERVAL:-45}"
mappingName="${NATPMP_MAPPING_NAME:-default}"

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

while true; do
	echo "$outputDivider"
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
	fi
	#### loop complete
	# delay next iteration by 10 or 45 seconds
	if [[ $verbose == true ]]
	then
		echo "Waiting $scriptWaitTime seconds before next port forward request..."
	fi
	echo "$outputDivider"
	sleep $scriptWaitTime
done
