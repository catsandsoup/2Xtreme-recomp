import socket, json, time

def send_cmd(cmd):
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.connect(("127.0.0.1", 4370))
        s.sendall((json.dumps(cmd) + "\n").encode())
        res = s.recv(4096)
        print(res.decode())

print("Pressing Start button...")
send_cmd({"cmd": "set_input", "buttons": 0xF7FF})
time.sleep(0.1)
send_cmd({"cmd": "clear_input"})
print("Button released.")
