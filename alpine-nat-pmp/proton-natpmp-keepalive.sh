#!/bin/bash

# based on Proton's support article here:
# https://protonvpn.com/support/port-forwarding-manual-setup#linux

protonGwIp='10.2.0.1'
readNatPmpRespPublicIpStr='Public IP'
natPmpRespSuccessRegex='readnatpmpresponseorretry returned [0-9]+ \((OK|SUCCESS)\)'
natPmpTcpPortMapRespRegex='Mapped public port [0-9]+ protocol TCP'
natPmpUdpPortMapRespRegex='Mapped public port [0-9]+ protocol UDP'
outputDivider='================================================================================================='

while true; do
	echo "$outputDivider"
	scriptWaitTime=45
	# get public IP from curl
	# this should always match what natpmp returns
	# should only be different if we're not connected to VPN
	curlPublicIp=$(curl --silent ip.me)
	echo "Public IP (ip.me): $curlPublicIp"
	echo "Target Gateway IP: $protonGwIp"

	# this will take a long time if we're not connected to VPN
	# or not on a P2P enabled server
	echo 'Testing if the gateway allows port forwarding...'
	# test if this server allows port forwarding
	natpmpc -g "$protonGwIp" &> /tmp/natpmpc_allowed
	# grab the read response/retry lines
	testNatPmpAllowed=$(grep -E "$natPmpRespSuccessRegex" /tmp/natpmpc_allowed)
	natPmpPublicIp=$(grep "$readNatPmpRespPublicIpStr" /tmp/natpmpc_allowed | cut -d ':' -f 2 | xargs)
	echo "Public IP (natpmp): $natPmpPublicIp"

	if [[ -z "$testNatPmpAllowed" ]]
	then
		echo 'NAT PMP test failed. Make sure your chosen server is P2P. Make sure this containers traffic is routed through the VPN tunnel. Command output:'
		echo "$outputDivider"
		cat /tmp/natpmpc_allowed
		echo "$outputDivider"
		scriptWaitTime=10
	else
		# request port forwarding for TCP and UDP for 60 seconds
		echo 'Sending UDP port forward request...'
		natpmpc -a 1 0 udp 60 -g "$protonGwIp" &> /tmp/natpmpc_udp_output
		testUdpPortMap=$(grep -E "$natPmpRespSuccessRegex" /tmp/natpmpc_udp_output)
		if [[ -z "$testUdpPortMap" ]]
		then
			echo 'UDP port mapping failed. Command output:'
			echo "$outputDivider"
			cat /tmp/natpmpc_udp_output
			echo "$outputDivider"
			scriptWaitTime=10
		else
			mappedUdpPort=$(grep -E "$natPmpUdpPortMapRespRegex" /tmp/natpmpc_udp_output | awk '{print $4}')
			echo "Forwarded port (UDP): $mappedUdpPort"
		fi
		echo 'Sending TCP port forward request...'
		natpmpc -a 1 0 tcp 60 -g "$protonGwIp" &> /tmp/natpmpc_tcp_output
		testTcpPortMap=$(grep -E "$natPmpRespSuccessRegex" /tmp/natpmpc_tcp_output)
		if [[ -z "$testTcpPortMap" ]]
		then
			echo 'TCP port mapping failed. Command output:'
			echo "$outputDivider"
			cat /tmp/natpmpc_tcp_output
			echo "$outputDivider"
			scriptWaitTime=10
		else
			mappedTcpPort=$(grep -E "$natPmpTcpPortMapRespRegex" /tmp/natpmpc_tcp_output | awk '{print $4}')
			echo "Forwarded port (TCP): $mappedTcpPort"
		fi
	fi
	echo "Waiting $scriptWaitTime seconds before next port forward request..."
	sleep $scriptWaitTime
	echo "$outputDivider"
done
