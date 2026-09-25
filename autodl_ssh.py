import os
import sys
import paramiko

sys.stdout.reconfigure(encoding="utf-8", errors="replace")
sys.stderr.reconfigure(encoding="utf-8", errors="replace")

def load_env():
    env_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), ".env")
    if os.path.isfile(env_path):
        with open(env_path, encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if line and not line.startswith("#") and "=" in line:
                    k, v = line.split("=", 1)
                    os.environ.setdefault(k.strip(), v.strip())

load_env()

HOST = os.environ.get("AUTODL_SSH_HOST", "")
PORT = int(os.environ.get("AUTODL_SSH_PORT", "22"))
USER = os.environ.get("AUTODL_SSH_USER", "root")
PASSWORD = os.environ.get("AUTODL_SSH_PASSWORD") or sys.exit("缺少密码：请设置环境变量 AUTODL_SSH_PASSWORD 或在 .env 中配置")

cmd = sys.argv[1]
timeout = int(sys.argv[2]) if len(sys.argv) > 2 else 60

client = paramiko.SSHClient()
client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
client.connect(HOST, port=PORT, username=USER, password=PASSWORD, timeout=30)

stdin, stdout, stderr = client.exec_command(cmd, timeout=timeout, get_pty=True)
out = stdout.read().decode("utf-8", errors="replace")
err = stderr.read().decode("utf-8", errors="replace")
code = stdout.channel.recv_exit_status()
print(out)
if err.strip():
    print("[STDERR]", err, file=sys.stderr)
sys.exit(code)
