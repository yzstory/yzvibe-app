#!/usr/bin/env python3
"""Package only explicitly approved public files; no credentials or repository data."""
from pathlib import Path
import hashlib
import tarfile

ROOT = Path(__file__).resolve().parent
FILES = ["index.html", "styles.css", "app.js", "assets/logo.png",
         "assets/sessions.png", "assets/chat.png", "assets/changes.jpg", "assets/android-qr.jpg"]

def main():
    destination = ROOT / "dist"
    destination.mkdir(exist_ok=True)
    archive = destination / "yzvibe-site.tar.gz"
    with tarfile.open(archive, "w:gz") as bundle:
        for name in FILES:
            source = ROOT / name
            if source.is_symlink() or not source.is_file():
                raise ValueError(f"Invalid public file: {name}")
            info = bundle.gettarinfo(str(source), arcname=name)
            info.uid = info.gid = 0
            info.uname = info.gname = ""
            info.mode = 0o644
            with source.open("rb") as stream:
                bundle.addfile(info, stream)
    digest = hashlib.sha256(archive.read_bytes()).hexdigest()
    (destination / "yzvibe-site.tar.gz.sha256").write_text(f"{digest}  {archive.name}\n")
    print(f"Packaged {len(FILES)} public files: {archive} ({archive.stat().st_size:,} bytes)")
    print(f"SHA256 {digest}")

if __name__ == "__main__":
    main()
