# protonvpn-natpmp-docker
Runs the NATPMP from the ProtonVPN manual port forward guide in a nice script. This process is detailed in Proton's support article here: https://protonvpn.com/support/port-forwarding-manual-setup#linux

I connect to ProtonVPN using WireGuard with my router. This configuration does not support port forwarding unless you have a loop running all the time to keep the port forwards open. I decided to create my own light weight container based on Alpine to run this natpmpc loop with some cleaned up console output.

The purpose of the container is to spit out the port numbers to put in your other applications like a BitTorrent client.

The container expects that it's outbound traffic will be tunneled through the VPN by some upstream device. My router will send traffic matching specific IP/MAC addresses through the VPN.

