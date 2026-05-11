Source code: https://github.com/blomstertj/protonvpn-natpmp-docker

Runs the NATPMP loop from the ProtonVPN manual port forward guide in a nice script. This process is detailed in Proton's support article here: https://protonvpn.com/support/port-forwarding-manual-setup#linux

The purpose of the container is to spit out the port numbers to put in your other applications like a BitTorrent client. You don't need to run natpmpc on the same device, the ports will work for all devices that use the VPN.

I connect to ProtonVPN using WireGuard with my router. This configuration does not support port forwarding unless you have a loop running all the time to keep the port forwards open. I decided to create my own light weight container based on Alpine to run this natpmpc loop with some cleaned up console output.
I designed this to be a "microservice" of sorts so it

- is lightweight and secure (based on Alpine Docker hardened image and uses nonroot user)
- uses basic Linux tools (bash, curl, and libnatpmp)
- relies on an external device/service to direct the traffic through VPN (1)

(1) Routers and firewalls can send traffic from specific IP addresses and/or MAC addresses through the VPN. That's why it has no VPN connectivity itself.

Example console output:
<img alt="Console Output Example" src="https://raw.githubusercontent.com/blomstertj/protonvpn-natpmp-docker/refs/heads/main/console-output-example.png">
<br>
Example console error output:
<img alt="Console Output Example" src="https://raw.githubusercontent.com/blomstertj/protonvpn-natpmp-docker/refs/heads/main/console-output-error-example.png">
