#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""逐点残差验证：把本库的转换结果和官方公布的坐标对齐比较。

为什么要这个脚本，而不是在 `moon test` 里断言几条：

  `moon test` 里的断言是"我记得的期望值"，适合守回归，不适合证明精度。
  审稿要看的是"实地址上到底差多少米"，那必须拿官方发布的成对坐标逐点算，
  并且把每一点的误差都摊开给人看，而不是给一个"全部通过"。

数据从哪来：

  verification/data/dhdn_bkg_points.csv
    德国 BKG（联邦制图与大地测量局）BETA2007testdaten.csv 的 31 个点，
    经 PROJ 的 test/gie/DHDN_ETRS89.gie 转载，数值未改动。

网格文件不入库（版权与体积），先用下面这条命令取：

  curl -L -o docs/BETA2007.gsb \\
    https://raw.githubusercontent.com/OSGeo/PROJ/master/data/tests/BETA2007.gsb

用法：

  python verification/run_verification.py            # 用 docs/BETA2007.gsb
  python verification/run_verification.py --grid 路径  # 指定网格
  python verification/run_verification.py --no-grid    # 只跑 7 参数
"""

import argparse
import csv
import io
import json
import math
import os
import subprocess
import sys

# ── 常量 ────────────────────────────────────────────────────────────────
WGS84_A = 6378137.0
WGS84_F = 1.0 / 298.257223563

# 注册表里对应的运算标识与标称精度（米）。改这里必须同时改 operation/registry.mbt，
# 否则报告里的"标称"和代码里的"实际"会脱节——那正是初审挑的毛病。
OPS = {
    "seven": {
        "code": "LOCAL:DHDN_ETRS89_7P",
        "accuracy_m": 3.0,
        "label": "7 参数（Helmert）",
    },
    "grid": {
        "code": "EPSG:15948",
        "accuracy_m": 0.1,
        "label": "BETA2007 网格（NTv2）",
    },
}

# ED50 → ETRS89 的官方点，来自 ICGC（加泰罗尼亚制图与地质研究所）的网格测试，
# 经 PROJ 的 test/gie/epsg_grid.gie 转载。
# 源坐标是 ED50 (EPSG:4230)，目标坐标是 ETRS89 (EPSG:4258)。
ED50_POINTS = [
    {
        "id": "ICGC01",
        "lon_ed50": 2.17,
        "lat_ed50": 41.4,
        "lon_etrs89": 2.168850772,
        "lat_etrs89": 41.398875399,
        "note": "Catalonia，官方网格 es_cat_icgc_100800401 的结果",
    },
]


def metres_per_degree(lat_deg):
    """该纬度上一度经差、一度纬差对应的地面距离（米）。"""
    s = math.sin(math.radians(lat_deg))
    n = WGS84_A / math.sqrt(1.0 - (2 * WGS84_F - WGS84_F**2) * s * s)
    m = WGS84_A * (1 - (2 * WGS84_F - WGS84_F**2)) / (1.0 - (2 * WGS84_F - WGS84_F**2) * s * s) ** 1.5
    return math.radians(1.0) * n * math.cos(math.radians(lat_deg)), math.radians(1.0) * m


def delta_m(lon_out, lat_out, lon_ref, lat_ref):
    """输出与参照之间的东向、北向偏差（米）。以参照点的纬度取曲率半径。"""
    kx, ky = metres_per_degree(lat_ref)
    dx = (lon_out - lon_ref) * kx
    dy = (lat_out - lat_ref) * ky
    return dx, dy


def find_cli(repo_root):
    """优先用已编译的 js 产物，避免每次都触发 moon 的构建检查。"""
    js = os.path.join(repo_root, "_build", "js", "debug", "build", "cmd", "main", "main.js")
    if os.path.exists(js):
        return ["node", js]
    native = os.path.join(
        repo_root, "_build", "native", "debug", "build", "cmd", "main", "main.exe"
    )
    if os.path.exists(native):
        return [native]
    return None


def run_cli(cli, args):
    proc = subprocess.run(cli + args, capture_output=True, text=True, encoding="utf-8")
    return proc.returncode, proc.stdout, proc.stderr


def transform_points(cli, source, target, points, grid_args=None):
    """一次调用转完所有点。返回 [(lon, lat), ...]；任一点失败则抛出。"""
    args = ["transform"]
    if grid_args:
        args += grid_args
    args += [source, target]
    for lon, lat in points:
        args += [repr(float(lon)), repr(float(lat))]
    code, out, err = run_cli(cli, args)
    lines = [ln.strip() for ln in out.splitlines() if ln.strip()]
    if len(lines) != len(points):
        raise RuntimeError(
            "期望 %d 行输出，实际 %d 行。stderr: %s\nstdout: %s"
            % (len(points), len(lines), err.strip()[:400], out.strip()[:400])
        )
    result = []
    for ln in lines:
        parts = ln.split()
        if len(parts) != 2:
            raise RuntimeError("无法解析输出行：%r" % ln)
        result.append((float(parts[0]), float(parts[1])))
    return result


def stats(values):
    if not values:
        return {}
    vs = sorted(values)
    n = len(vs)

    def pct(p):
        idx = min(n - 1, max(0, int(round(p * (n - 1)))))
        return vs[idx]

    return {
        "n": n,
        "min": vs[0],
        "median": pct(0.5),
        "p95": pct(0.95),
        "max": vs[-1],
        "mean": sum(vs) / n,
    }


def load_dhdn_points(path):
    rows = []
    with io.open(path, encoding="utf-8") as fh:
        for line in fh:
            if line.startswith("#") or not line.strip():
                continue
            rows.append(line)
    reader = csv.DictReader(rows)
    out = []
    for r in reader:
        out.append(
            {
                "id": r["id"],
                "lon_dhdn": float(r["lon_dhdn"]),
                "lat_dhdn": float(r["lat_dhdn"]),
                "lon_etrs89": float(r["lon_etrs89"]),
                "lat_etrs89": float(r["lat_etrs89"]),
            }
        )
    return out


def evaluate(points, outputs, lon_key, lat_key):
    """把输出与参照逐点比，返回明细列表。"""
    rows = []
    for p, (lon_out, lat_out) in zip(points, outputs):
        dx, dy = delta_m(lon_out, lat_out, p[lon_key], p[lat_key])
        rows.append(
            {
                "id": p["id"],
                "lon_out": lon_out,
                "lat_out": lat_out,
                "dx_m": dx,
                "dy_m": dy,
                "d_m": math.hypot(dx, dy),
            }
        )
    return rows


def fmt(v, nd=3):
    return ("%." + str(nd) + "f") % v


def main():
    here = os.path.dirname(os.path.abspath(__file__))
    repo = os.path.dirname(here)

    ap = argparse.ArgumentParser()
    ap.add_argument("--grid", default=os.path.join(repo, "docs", "BETA2007.gsb"))
    ap.add_argument("--no-grid", action="store_true")
    ap.add_argument("--data", default=os.path.join(here, "data", "dhdn_bkg_points.csv"))
    ap.add_argument("--out", default=os.path.join(here, "results"))
    args = ap.parse_args()

    cli = find_cli(repo)
    if cli is None:
        print("找不到可执行产物。先跑：moon build --target js")
        return 2

    os.makedirs(args.out, exist_ok=True)
    points = load_dhdn_points(args.data)
    print("数据点：%d（来源 %s）" % (len(points), os.path.relpath(args.data, repo)))

    src = "+proj=longlat +ellps=bessel +datum=potsdam"
    dst = "EPSG:4258"
    lon_key, lat_key = "lon_etrs89", "lat_etrs89"

    report = {"points": points, "runs": {}, "grid_file": None}

    # ── 路径一：7 参数 ────────────────────────────────────────────────
    plain = [(p["lon_dhdn"], p["lat_dhdn"]) for p in points]
    out7 = transform_points(cli, src, dst, plain)
    rows7 = evaluate(points, out7, lon_key, lat_key)
    report["runs"]["seven"] = rows7

    # ── 路径二：网格 ──────────────────────────────────────────────────
    rowsg = None
    grid_file = args.grid
    if not args.no_grid:
        if not os.path.exists(grid_file):
            print("网格文件不存在：%s" % grid_file)
            print("下载：curl -L -o docs/BETA2007.gsb https://raw.githubusercontent.com/OSGeo/PROJ/master/data/tests/BETA2007.gsb")
        else:
            report["grid_file"] = os.path.relpath(grid_file, repo)
            outg = transform_points(
                cli, src, dst, plain, grid_args=["--grid", "BETA2007=" + grid_file]
            )
            rowsg = evaluate(points, outg, lon_key, lat_key)
            report["runs"]["grid"] = rowsg

    # ── 链路二：ED50 → ETRS89 ─────────────────────────────────────────
    edsrc = "+proj=longlat +ellps=intl +datum=ED50"
    ed_pts = [(p["lon_ed50"], p["lat_ed50"]) for p in ED50_POINTS]
    out_ed = transform_points(cli, edsrc, dst, ed_pts)
    rows_ed = evaluate(ED50_POINTS, out_ed, "lon_etrs89", "lat_etrs89")
    report["runs"]["ed50"] = rows_ed

    # ── 落盘 ──────────────────────────────────────────────────────────
    for name, rows in report["runs"].items():
        path = os.path.join(args.out, "residuals_%s.csv" % name)
        with io.open(path, "w", encoding="utf-8", newline="") as fh:
            w = csv.writer(fh)
            w.writerow(["id", "lon_out", "lat_out", "dx_m", "dy_m", "d_m"])
            for r in rows:
                w.writerow(
                    [
                        r["id"],
                        "%.12f" % r["lon_out"],
                        "%.12f" % r["lat_out"],
                        "%.9f" % r["dx_m"],
                        "%.9f" % r["dy_m"],
                        "%.9f" % r["d_m"],
                    ]
                )

    # ── 控制台报告 ────────────────────────────────────────────────────
    print()
    header = "%-8s %14s %14s %8s" % ("点", "dx (m)", "dy (m)", "合成")
    for name, label in (("seven", OPS["seven"]["label"]), ("grid", OPS["grid"]["label"])):
        rows = report["runs"].get(name)
        if not rows:
            continue
        op = OPS[name]
        print("== %s（%s，标称 %.2f m）==" % (label, op["code"], op["accuracy_m"]))
        print(header)
        for r in rows:
            print(
                "%-8s %14s %14s %8s"
                % (r["id"], fmt(r["dx_m"]), fmt(r["dy_m"]), fmt(r["d_m"]))
            )
        s = stats([r["d_m"] for r in rows])
        within = sum(1 for r in rows if r["d_m"] <= op["accuracy_m"] * 2)
        print(
            "  中位 %.3f m  平均 %.3f m  P95 %.3f m  最大 %.3f m"
            % (s["median"], s["mean"], s["p95"], s["max"])
        )
        print(
            "  在 2×标称（%.2f m）以内的点：%d / %d"
            % (op["accuracy_m"] * 2, within, len(rows))
        )
        print()

    if rowsg:
        ratio = stats([r["d_m"] for r in rows7])["median"] / max(
            1e-9, stats([r["d_m"] for r in rowsg])["median"]
        )
        print("网格 / 7 参数 的中位误差之比：%.0f 倍" % ratio)
        print()

    print("== ED50 → ETRS89（LOCAL:ED50_ETRS89_3P，标称 10 m）==")
    for r in rows_ed:
        print("%-8s %14s %14s %8s" % (r["id"], fmt(r["dx_m"]), fmt(r["dy_m"]), fmt(r["d_m"])))
    print()

    with io.open(os.path.join(args.out, "summary.json"), "w", encoding="utf-8") as fh:
        json.dump(
            {
                "grid_file": report["grid_file"],
                "n_points": len(points),
                "seven": stats([r["d_m"] for r in rows7]),
                "grid": stats([r["d_m"] for r in (rowsg or [])]),
                "ed50": stats([r["d_m"] for r in rows_ed]),
            },
            fh,
            ensure_ascii=False,
            indent=2,
        )
    print("明细已写入 %s" % os.path.relpath(args.out, repo))
    return 0


if __name__ == "__main__":
    sys.exit(main())
