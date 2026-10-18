# SPDX-License-Identifier: MIT
# frame-shot-sync が ssh で Frame に送って実行する、読むだけの一覧スクリプト（Frame 側には何も書かない）。
# 引数: base64 の JSON {"sources":[{"name":..,"path":..}], "ext":[".jpg",..]}
# 出力: ASCII だけの JSON {"now": 秒, "files": [{"p": パス, "s": サイズ, "m": 更新時刻, "src": 名前}]}
import base64, glob, json, os, sys, time
cfg = json.loads(base64.b64decode(sys.argv[1]).decode("utf-8"))
exts = tuple(e.lower() for e in cfg.get("ext", [".jpg", ".jpeg", ".png", ".webp"]))
files, seen = [], set()
for src in cfg["sources"]:
    for d in sorted(glob.glob(os.path.expanduser(src["path"]))):
        if not os.path.isdir(d):
            continue
        for e in os.scandir(d):
            n = e.name
            if n.startswith(".") or not n.lower().endswith(exts) or not e.is_file(follow_symlinks=False):
                continue
            real = os.path.realpath(e.path)
            if real in seen:
                continue
            seen.add(real)
            st = e.stat()
            files.append({"p": e.path, "s": st.st_size, "m": st.st_mtime, "src": src.get("name", "")})
print(json.dumps({"now": time.time(), "files": files}, ensure_ascii=True))
