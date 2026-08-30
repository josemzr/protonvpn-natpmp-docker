Source code: https://github.com/blomstertj/protonvpn-natpmp-docker

Runs the NATPMP loop from the ProtonVPN manual port forward guide in a nice script. This process is detailed in Proton's support article here: https://protonvpn.com/support/port-forwarding-manual-setup#linux

The purpose of the container is to spit out the port numbers to put in your other applications like a BitTorrent client. You don't need to run natpmpc on the same device, the ports will work for all devices that use the VPN.

I connect to ProtonVPN using WireGuard with my router. This configuration does not support port forwarding unless you have a loop running all the time to keep the port forwards open. I decided to create my own light weight container based on Alpine to run this natpmpc loop with some cleaned up console output. I use Portainer to view the console logs but you can run "docker logs ContainerName" to view the console.

- This "microservice" container is:
    - lightweight and secure (based on Alpine Docker hardened image and uses nonroot user)
    - uses basic Linux tools (bash, curl, and libnatpmp)
    - relies on an external device/service/container to direct the traffic through VPN
        - Routers and firewalls can send traffic from specific IP addresses and/or MAC addresses through the VPN

- Environment vars
    - COMPACT_OUTPUT
        - only outputs public IP(s) and forwarded ports on successful loop run
    - SKIP_IPME_CHECK
        - skips the public IP check to Proton operated https://ip.me
    - NATPMP_GATEWAY
        - NAT-PMP gateway address (default: `10.2.0.1`)
    - NATPMP_PUBLIC_PORT
        - requested public port; Proton normally allocates a random port (default: `1`)
    - NATPMP_PRIVATE_PORT
        - private mapping identifier (default: `0`)
        - use a different non-zero value for each helper sharing one VPN connection
    - NATPMP_LIFETIME
        - mapping lifetime in seconds (default: `60`)
    - NATPMP_REFRESH_INTERVAL
        - successful renewal interval in seconds; must be lower than the lifetime (default: `45`)
    - NATPMP_MAPPING_NAME
        - descriptive name included in verbose logs (default: `default`)
    - TZ
        - Set timezone for correct log timestamps

## Multiple mappings

Run one helper per application and give every helper a unique private mapping
identifier. For example:

```yaml
services:
  natpmp-qbittorrent:
    image: protonvpn-natpmp
    environment:
      NATPMP_MAPPING_NAME: qbittorrent
      NATPMP_PRIVATE_PORT: 1

  natpmp-amule:
    image: protonvpn-natpmp
    environment:
      NATPMP_MAPPING_NAME: amule
      NATPMP_PRIVATE_PORT: 2
```

Both helpers must be routed through the same NAT-PMP-enabled Proton VPN tunnel.
Configure each application with the public port shown by its helper. Whether
multiple simultaneous ports are granted is ultimately controlled by the VPN
server and account policy.

<br>
Example console output:
<br>
<img alt="Console Output Example" src="https://raw.githubusercontent.com/blomstertj/protonvpn-natpmp-docker/refs/heads/main/console-output-example.png">
<br>
Example console error output:
<br>
<img alt="Console Output Example" src="https://raw.githubusercontent.com/blomstertj/protonvpn-natpmp-docker/refs/heads/main/console-output-error-example.png">
