import socket
import time
import sys

def read_all(s):
    res = b''
    while True:
        try:
            chunk = s.recv(4096)
            if not chunk:
                break
            res += chunk
        except socket.timeout:
            break
    return res.decode('utf-8', 'ignore')

def fix_network(vmid, pwd):
    print(f"--- Fixing Network for VM {vmid} ---")
    s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    try:
        s.connect(f'/var/run/qemu-server/{vmid}.serial0')
    except Exception as e:
        print(f"Failed to connect to VM {vmid} serial socket: {e}")
        return
        
    s.settimeout(0.5)
    
    # Read initial buffer
    read_all(s)
    
    # Send enters to prompt login screen
    s.sendall(b'\n\n')
    time.sleep(1)
    buf = read_all(s)
    
    # Log in if at login prompt
    if 'login:' in buf:
        print("Logging in...")
        s.sendall(b'debian\n')
        time.sleep(1)
        read_all(s)
        s.sendall(f'{pwd}\n'.encode())
        time.sleep(2)
        read_all(s)
    else:
        print("Already logged in or terminal active.")
        
    # Write systemd-networkd configuration
    print("Writing DHCP configuration file...")
    s.sendall(b"sudo sh -c \"echo '[Match]' > /etc/systemd/network/20-wire.network\"\n")
    time.sleep(0.5)
    s.sendall(b"sudo sh -c \"echo 'Name=ens18 enp0s18 eth0' >> /etc/systemd/network/20-wire.network\"\n")
    time.sleep(0.5)
    s.sendall(b"sudo sh -c \"echo '[Network]' >> /etc/systemd/network/20-wire.network\"\n")
    time.sleep(0.5)
    s.sendall(b"sudo sh -c \"echo 'DHCP=yes' >> /etc/systemd/network/20-wire.network\"\n")
    time.sleep(0.5)
    
    # Restart systemd-networkd
    print("Restarting systemd-networkd...")
    s.sendall(b"sudo systemctl restart systemd-networkd\n")
    time.sleep(3)
    read_all(s)
    
    # Query IPv4 address
    print("Checking IPv4 Address...")
    s.sendall(b"ip -4 addr show ens18\n")
    time.sleep(2)
    output = read_all(s)
    print(output)
    
    # Start/restart guest-agent to make sure it runs
    print("Starting QEMU Guest Agent...")
    s.sendall(b"sudo systemctl restart qemu-guest-agent || sudo systemctl start qemu-guest-agent\n")
    time.sleep(2)
    read_all(s)
    s.close()

if __name__ == '__main__':
    fix_network(200, 'gitlabdevops')
    fix_network(201, 'proddevops')
