#!/usr/bin/env python3
"""Measure local IPv4 latency and NextTrace routes to Vultr Looking Glass nodes."""
import argparse
import csv
from datetime import datetime
import ipaddress
import os
from pathlib import Path
import platform
import re
import shlex
import shutil
import subprocess
import sys

CATALOG = Path(__file__).with_name("vultr-test-ips.tsv")
FIELDS = ["code", "city", "country", "ipv4", "loss_percent", "min_ms", "avg_ms",
          "max_ms", "ping_status", "trace_status", "looking_glass"]


def positive_int(value):
    try:
        number = int(value)
    except ValueError:
        raise argparse.ArgumentTypeError("请输入正整数") from None
    if number <= 0:
        raise argparse.ArgumentTypeError("请输入正整数")
    return number


def load_nodes(path=CATALOG):
    with path.open(encoding="utf-8", newline="") as file:
        nodes = list(csv.DictReader(file, delimiter="\t"))
    for node in nodes:
        ipaddress.IPv4Address(node["ipv4"])
        if not re.fullmatch(r"[A-Z0-9]+", node["code"]):
            raise ValueError("无效的机房代码")
    return nodes


def select_nodes(nodes, selection):
    if not selection:
        return nodes
    selected = []
    for term in selection.split(","):
        term = term.strip().lower()
        matches = [node for node in nodes if term and
                   (node["code"].lower() == term or term in node["city"].lower())]
        if not matches:
            raise ValueError(f"找不到机房：{term}")
        for node in matches:
            if node not in selected:
                selected.append(node)
    return selected


def parse_ping(text):
    loss = re.search(r"([\d.]+)%\s*packet loss", text)
    rtt = re.search(r"(?:round-trip|rtt)[^\n=]*=\s*([\d.]+)/([\d.]+)/([\d.]+)/", text)
    return {
        "loss_percent": loss.group(1) if loss else "",
        "min_ms": rtt.group(1) if rtt else "",
        "avg_ms": rtt.group(2) if rtt else "",
        "max_ms": rtt.group(3) if rtt else "",
    }


def run_logged(command, log, timeout):
    """Bound each command; preserve partial output even on timeout/failure."""
    with log.open("w", encoding="utf-8") as file:
        file.write("$ " + " ".join(shlex.quote(arg) for arg in command) + "\n\n")
        file.flush()
        try:
            result = subprocess.run(command, stdout=file, stderr=subprocess.STDOUT,
                                    timeout=timeout, env={**os.environ, "LC_ALL": "C"})
            return "ok" if result.returncode == 0 else f"exit_{result.returncode}"
        except subprocess.TimeoutExpired:
            file.write(f"\n[超时：{timeout} 秒；已保留部分输出]\n")
            return "timeout"
        except OSError as error:
            file.write(f"\n[无法执行：{error}]\n")
            return "error"


def trace_command(args):
    executable = args.nt_command or shutil.which("nt") or shutil.which("nexttrace")
    if not executable or not shutil.which(executable):
        raise ValueError("未找到 nt/nexttrace；请安装 NextTrace，或用 --nt-command 指定可执行文件")
    # Older NextTrace releases lack --traceroute; newer releases may default to MTR.
    help_result = subprocess.run([executable, "--help"], capture_output=True,
                                 text=True, timeout=10)
    command = [executable, "-4", "-M", "-C", "-m", str(args.max_hops),
               "-q", "3", "--timeout", "1000"]
    if "--traceroute" in help_result.stdout + help_result.stderr:
        command.append("--traceroute")
    if args.trace_protocol == "tcp":
        command.extend(["-T", "-p", "443"])
    return command


def main():
    parser = argparse.ArgumentParser(description="测试本机到 Vultr 各机房的 IPv4 延迟和路由")
    parser.add_argument("--list", action="store_true", help="列出测试 IP 后退出")
    parser.add_argument("--location", help="机房代码或城市名，多个用逗号分隔，例如 SGP,NRT,LAX")
    parser.add_argument("--count", type=positive_int, default=5, help="每个机房 ping 次数，默认 5")
    parser.add_argument("--ping-only", action="store_true", help="只测延迟，不运行路由命令")
    parser.add_argument("--nt-command", help="nt 或 nexttrace 可执行文件路径（不包含参数）")
    parser.add_argument("--trace-protocol", choices=["icmp", "tcp"], default="icmp",
                        help="路由探测协议；tcp 使用目标端口 443")
    parser.add_argument("--trace-timeout", type=positive_int, default=60,
                        help="每条路由的总超时秒数，默认 60")
    parser.add_argument("--max-hops", type=positive_int, default=30, help="最大路由跳数，默认 30")
    parser.add_argument("--output", type=Path, help="新的结果目录；默认在当前目录创建带时间戳的目录")
    args = parser.parse_args()
    if args.max_hops > 255:
        parser.error("--max-hops 不能超过 255")
    try:
        nodes = select_nodes(load_nodes(), args.location)
        if args.list:
            for node in nodes:
                print(f'{node["code"]:4} {node["city"]:16} {node["ipv4"]:15} {node["looking_glass"]}')
            return 0
        if platform.system() not in ("Linux", "Darwin"):
            parser.error("当前支持 Linux 和 macOS")
        ping = shutil.which("ping")
        if not ping:
            parser.error("未找到 ping 命令")
        trace = None if args.ping_only else trace_command(args)
        output = args.output or Path("vultr-results-" + datetime.now().strftime("%Y%m%d-%H%M%S-%f"))
        output.mkdir(parents=True, exist_ok=False)
    except (OSError, ValueError, subprocess.TimeoutExpired) as error:
        parser.error(str(error))

    print(f"测试 {len(nodes)} 个机房；结果目录：{output.resolve()}", flush=True)
    if trace:
        print(f"路由命令：{trace[0]}；协议：{args.trace_protocol}", flush=True)
    rows = []
    failures = False
    with (output / "summary.csv").open("w", encoding="utf-8", newline="") as file:
        writer = csv.DictWriter(file, fieldnames=FIELDS)
        writer.writeheader()
        file.flush()
        for index, node in enumerate(nodes, 1):
            code, ip = node["code"], node["ipv4"]
            print(f'[{index}/{len(nodes)}] {code} {node["city"]} {ip}', flush=True)
            # Linux -W uses seconds; macOS -W uses milliseconds. IPv4 is explicit.
            wait = "1000" if platform.system() == "Darwin" else "1"
            ping_log = output / f"{code}-ping.txt"
            ping_status = run_logged([ping, "-n", "-c", str(args.count), "-W", wait, ip],
                                     ping_log, args.count * 2 + 5)
            stats = parse_ping(ping_log.read_text(encoding="utf-8", errors="replace"))
            if ping_status == "ok" and not stats["avg_ms"]:
                ping_status = "no_statistics"
            trace_status = "skipped"
            if trace:
                trace_status = run_logged(trace + [ip], output / f"{code}-route.txt",
                                          args.trace_timeout)
            row = {**node, **stats, "ping_status": ping_status, "trace_status": trace_status}
            writer.writerow(row)
            file.flush()
            rows.append(row)
            failures |= ping_status != "ok" or trace_status not in ("ok", "skipped")
            print(f'  平均延迟：{stats["avg_ms"] or "N/A"} ms；丢包：'
                  f'{stats["loss_percent"] or "N/A"}%；路由：{trace_status}', flush=True)

    print("\n按平均延迟排序（无响应节点在最后）：")
    for row in sorted(rows, key=lambda row: float(row["avg_ms"]) if row["avg_ms"] else float("inf")):
        print(f'{row["code"]:4} {row["city"]:16} {row["avg_ms"] or "N/A":>9} ms '
              f'loss={row["loss_percent"] or "N/A"}%')
    print(f"汇总：{(output / 'summary.csv').resolve()}")
    return 1 if failures else 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        print("\n测试已中断，已完成的结果保留。", file=sys.stderr)
        sys.exit(130)
