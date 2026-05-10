#!/bin/bash


#### Author
# github.com/blomstertj
#### Description
# natpmpc port forward map request loop
# based on Proton's support article here: https://protonvpn.com/support/port-forwarding-manual-setup#linux


# the PMP gateway for ProtonVPN from the article
protonGwIp='10.2.0.1'
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

while true; do
	echo "$outputDivider"
	scriptWaitTime=45
	#### get public IP from curl to Proton operated ip.me
	# this should always match what natpmp returns
	# should only be different if we're not connected to VPN
	curlPublicIp=$(curl --silent ip.me)
	echo "Public IP (ip.me): $curlPublicIp"
	echo "Target Gateway IP: $protonGwIp"

	#### test if the gateway allows port forwarding
	# this will take a long time if we're not connected to VPN
	# or not on a P2P enabled server
	echo 'Testing if the gateway allows port forwarding...'
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
		echo 'Sending UDP port forward request...'
		natpmpc -a 1 0 udp 60 -g "$protonGwIp" &> /tmp/natpmpc_udp_output
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
		echo 'Sending TCP port forward request...'
		natpmpc -a 1 0 tcp 60 -g "$protonGwIp" &> /tmp/natpmpc_tcp_output
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
	echo "Waiting $scriptWaitTime seconds before next port forward request..."
	echo "$outputDivider"
	sleep $scriptWaitTime
done
