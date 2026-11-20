#!/usr/bin/env python3
"""Server SFTP locale con credenziali sintetiche per prove via adb reverse.

Richiede paramiko in un ambiente Python separato. Espone soltanto --root;
non usare con file o credenziali personali. Non è un server di produzione.
"""
import argparse
import base64
import hashlib
import os
from pathlib import Path
import socket
import threading

import paramiko


class Authentication(paramiko.ServerInterface):
    def __init__(self, authorized_key=None):
        self.authorized_key = authorized_key

    def get_allowed_auths(self, username):
        return "password,publickey" if self.authorized_key else "password"

    def check_auth_password(self, username, password):
        return (paramiko.AUTH_SUCCESSFUL
                if username == "demo" and password == "sftp-demo"
                else paramiko.AUTH_FAILED)

    def check_auth_publickey(self, username, key):
        expected = self.authorized_key
        actual = base64.b64encode(key.asbytes()).decode()
        return (paramiko.AUTH_SUCCESSFUL if username == "demo" and expected == actual
                else paramiko.AUTH_FAILED)

    def check_channel_request(self, kind, channel_id):
        return (paramiko.OPEN_SUCCEEDED if kind == "session"
                else paramiko.OPEN_FAILED_ADMINISTRATIVELY_PROHIBITED)


class SftpServer(paramiko.SFTPServer):
    def _send_packet(self, packet_type, message):
        if packet_type == paramiko.sftp.CMD_VERSION:
            message.add_string("posix-rename@openssh.com")
            message.add_string("1")
        return super()._send_packet(packet_type, message)


class Handle(paramiko.SFTPHandle):
    def stat(self):
        stream = getattr(self, "readfile", None) or self.writefile
        return paramiko.SFTPAttributes.from_stat(os.fstat(stream.fileno()))


class Files(paramiko.SFTPServerInterface):
    def __init__(self, server, *, root):
        super().__init__(server)
        self.root = Path(root).resolve()

    def path(self, path):
        result = (self.root / path.lstrip("/")).resolve()
        if not result.is_relative_to(self.root):
            raise PermissionError()
        return result

    @staticmethod
    def failure(error):
        return paramiko.SFTPServer.convert_errno(error.errno or 13)

    def list_folder(self, path):
        try:
            result = []
            for child in self.path(path).iterdir():
                attr = paramiko.SFTPAttributes.from_stat(child.stat())
                attr.filename = child.name
                result.append(attr)
            return result
        except OSError as error:
            return self.failure(error)

    def stat(self, path):
        try:
            return paramiko.SFTPAttributes.from_stat(self.path(path).stat())
        except OSError as error:
            return self.failure(error)

    lstat = stat

    def open(self, path, flags, attr):
        try:
            fd = os.open(self.path(path), flags, 0o600)
            handle = Handle(flags)
            mode = "r+b" if flags & os.O_RDWR else "wb" if flags & os.O_WRONLY else "rb"
            stream = os.fdopen(fd, mode)
            if flags & os.O_RDWR or not flags & os.O_WRONLY:
                handle.readfile = stream
            if flags & os.O_RDWR or flags & os.O_WRONLY:
                handle.writefile = stream
            return handle
        except OSError as error:
            return self.failure(error)

    def remove(self, path):
        try:
            self.path(path).unlink()
            return paramiko.SFTP_OK
        except OSError as error:
            return self.failure(error)

    def rename(self, oldpath, newpath):
        try:
            target = self.path(newpath)
            if target.exists():
                return paramiko.SFTP_FAILURE
            os.rename(self.path(oldpath), target)
            return paramiko.SFTP_OK
        except OSError as error:
            return self.failure(error)

    def posix_rename(self, oldpath, newpath):
        try:
            os.replace(self.path(oldpath), self.path(newpath))
            return paramiko.SFTP_OK
        except OSError as error:
            return self.failure(error)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", required=True)
    parser.add_argument("--host-key", required=True)
    parser.add_argument("--port", type=int, default=18445)
    parser.add_argument("--authorized-key")
    args = parser.parse_args()
    authorized_key = (Path(args.authorized_key).read_text().split()[1]
                      if args.authorized_key else None)
    root = Path(args.root).resolve(strict=True)
    key_path = Path(args.host_key)
    if not key_path.exists():
        key = paramiko.RSAKey.generate(2048)
        key.write_private_key_file(str(key_path))
        key_path.chmod(0o600)
    key = paramiko.RSAKey.from_private_key_file(str(key_path))
    fingerprint = base64.b64encode(hashlib.sha256(key.asbytes()).digest()).decode().rstrip("=")
    print(f"SFTP 127.0.0.1:{args.port} — ssh-rsa SHA256:{fingerprint}", flush=True)

    def serve(connection):
        transport = paramiko.Transport(connection)
        try:
            transport.add_server_key(key)
            transport.set_subsystem_handler("sftp", SftpServer, Files, root=root)
            transport.start_server(server=Authentication(authorized_key))
            while transport.is_active():
                transport.join(0.2)
        except (EOFError, OSError, paramiko.SSHException):
            pass
        finally:
            transport.close()

    with socket.socket() as listener:
        listener.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        listener.bind(("127.0.0.1", args.port))
        listener.listen()
        while True:
            connection, _ = listener.accept()
            threading.Thread(target=serve, args=(connection,), daemon=True).start()


if __name__ == "__main__":
    main()
