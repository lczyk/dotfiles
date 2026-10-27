#!/usr/bin/env python3
# spellchecker: ignore upower amixer nmcli milli battmgr
import subprocess as sub
import os
import threading

# import time
# from contextlib import contextmanager
# import sys

# @contextmanager
# def time_execution(label: str) -> None:
#     start_time = time.time()
#     yield
#     end_time = time.time()
#     elapsed_time = end_time - start_time
#     print(f"{label} took {elapsed_time:.2f} seconds", file=sys.stderr)

def run_date() -> str:
    return sub.getoutput("date +'%b %m-%d %a %H:%M'")  # Feb 02-02 Mon 15:30


def get_date(stdout: str | None = None) -> str:
    now = stdout if stdout else run_date()
    time_fuzzer_path = ""
    if os.path.isfile("/usr/bin/time_fuzzer") and os.access(
        "/usr/bin/time_fuzzer", os.X_OK
    ):
        time_fuzzer_path = "/usr/bin/time_fuzzer"
    elif os.path.isfile(os.path.expanduser("~/.cargo/bin/time_fuzzer")) and os.access(
        os.path.expanduser("~/.cargo/bin/time_fuzzer"), os.X_OK
    ):
        time_fuzzer_path = os.path.expanduser("~/.cargo/bin/time_fuzzer")

    out: str = ""
    if time_fuzzer_path:
        date_part, time_part = now.rsplit(" ", 1)

        # BUG: this does not work with sub.getoutput ??
        fuzzy_time = sub.run(
            [time_fuzzer_path, time_part], capture_output=True, text=True
        )
        out = f"{date_part} . {fuzzy_time.stdout}"

    else:
        out = now

    return out


def run_battery(battery_path: str = "") -> str | None:
    if not battery_path:
        upower_enumerate = sub.getoutput("upower --enumerate")
        # Find the battery path. accept only the first one
        for line in upower_enumerate.splitlines():
            if "battery" in line:
                battery_path = line.strip()
                break

    if not battery_path:
        return None

    upower_info = sub.getoutput(f"upower -i '{battery_path}'")
    return upower_info


def get_battery(stdout: str | None = None, battery_path: str = "") -> str:
    upower_info = stdout if stdout else run_battery(battery_path=battery_path)
    if not upower_info:
        return "no_battery"

    battery_percentage = ""
    battery_state = ""
    time_to_full = ""
    time_to_empty = ""
    for line in upower_info.splitlines():
        line = line.strip()
        if line.startswith("percentage:"):
            battery_percentage = line.split(":", 1)[1].strip().rstrip("%")
        elif line.startswith("state:"):
            battery_state = line.split(":", 1)[1].strip()
        elif line.startswith("time to full:"):
            time_to_full = line.split(":", 1)[1].strip()
        elif line.startswith("time to empty:"):
            time_to_empty = line.split(":", 1)[1].strip()
    battery_str = f"{int(float(battery_percentage))}%"
    if battery_state == "charging":
        battery_str += " ^"
        if time_to_full:
            battery_str += f" ({time_to_full})"
    elif battery_state == "discharging":
        battery_str += " v"
        if time_to_empty:
            battery_str += f" ({time_to_empty})"
    elif battery_state == "fully-charged":
        battery_str += " ~"
    elif battery_state == "unknown":
        battery_str += " ?"
    else:
        battery_str += " x"
    return battery_str


def run_volume() -> str:
    return sub.getoutput("amixer get Master")


def get_volume(stdout: str | None = None) -> str:
    amixer_output = stdout if stdout else run_volume()

    if not amixer_output:
        return "no sound"

    volume_line = ""
    for line in amixer_output.splitlines():
        if "Front Left:" in line:
            volume_line = line
            break

    if not volume_line:
        return "no sound"

    parts = volume_line.split()
    volume = ""
    mute_status = ""
    for part in parts:
        if part.startswith("[") and part.endswith("]"):
            content = part[1:-1]
            if content.endswith("%"):
                volume = content
            elif content in ("on", "off"):
                mute_status = content

    return f"{volume} {mute_status}"


def run_brightness() -> str:
    light_output = sub.getoutput("light")
    return light_output


def get_brightness(stdout: str | None = None) -> str:
    light_output = stdout if stdout else run_brightness()

    if not light_output:
        return "no_brightness"

    brightness_value = light_output.split()[0]
    brightness_int = int(float(brightness_value))
    return f"b{brightness_int}"


def run_network() -> tuple[str, str, str]:
    """return nmcli device, active connection and wifi scan outputs"""
    devices = sub.getoutput("nmcli -t -f TYPE,STATE,IP4-CONNECTIVITY,CONNECTION device")
    connections = sub.getoutput("nmcli -t -f TYPE,NAME con show --active")
    wifi_list = sub.getoutput("nmcli -t -f IN-USE,SIGNAL,FREQ device wifi list --rescan no")
    return devices, connections, wifi_list


def split_terse(line: str) -> list[str]:
    """split a line of `nmcli -t` output on unescaped colons"""
    fields = [""]
    escaped = False
    for char in line:
        if escaped:
            fields[-1] += char
            escaped = False
        elif char == "\\":
            escaped = True
        elif char == ":":
            fields.append("")
        else:
            fields[-1] += char
    return fields


def get_network(stdout: tuple[str, str, str] | None = None) -> str:
    devices, connections, wifi_list = stdout if stdout else run_network()

    # (name, connectivity) of the connected wifi / bluetooth device
    wifi: tuple[str, str] | None = None
    bt: tuple[str, str] | None = None
    for line in devices.splitlines():
        fields = split_terse(line)
        if len(fields) < 4 or fields[1] != "connected":
            continue
        dev_type, _, connectivity, name = fields[:4]
        if dev_type == "wifi" and not wifi:
            wifi = (name, connectivity)
        elif dev_type == "bt" and not bt:
            bt = (name, connectivity)

    vpns = []
    for line in connections.splitlines():
        fields = split_terse(line)
        if len(fields) >= 2 and fields[0] in ("vpn", "wireguard"):
            vpns.append(fields[1])

    def problem(connectivity: str) -> str:
        return "" if connectivity in ("full", "unknown") else f" !{connectivity}"

    if wifi:
        name, connectivity = wifi
        out = name
        for line in wifi_list.splitlines():
            fields = split_terse(line)
            if len(fields) >= 3 and fields[0] == "*":
                signal, freq = fields[1], int(fields[2].split()[0])
                band = "2g" if freq < 3000 else "5g" if freq < 5925 else "6g"
                out += f" {band} {signal}%"
                break
        out += problem(connectivity)
        if bt:
            # NM penalises the default route of a device without full connectivity
            out += " > bt" if problem(connectivity) else " +bt"
    elif bt:
        name, connectivity = bt
        out = f"bt {name}{problem(connectivity)}"
    else:
        out = "no net"

    if vpns:
        out += f" ({', '.join(vpns)})"

    return out


def run_cpu() -> tuple[str, int]:
    """return ps output and pid of the ps process"""
    # ps_output = sub.getoutput("ps -e --format pcpu,pid,comm --sort=-pcpu")
    # return ps_output
    ps_process = sub.Popen(
        ["ps", "-e", "--format", "pcpu,pid,comm", "--sort=-pcpu"],
        stdout=sub.PIPE,
        stderr=sub.PIPE,
        text=True,
    )
    stdout, stderr = ps_process.communicate()
    if ps_process.returncode != 0:
        raise RuntimeError(f"ps command failed: {stderr.strip()}")
    return stdout, ps_process.pid


def get_cpu(stdout: str | None = None, ps_pid: int | None = None) -> str:
    if stdout is None:
        ps_output, ps_pid = run_cpu()
    else:
        ps_output = stdout

    lines = ps_output.splitlines()

    if len(lines) < 2:
        return "no cpu"

    lines = lines[1:4]
    # %CPU PID COMMAND

    python_pid = os.getpid()

    for line in lines:
        parts = line.split()
        if len(parts) < 3:
            break
        cpu, pid, command = float(parts[0]), int(parts[1]), parts[2]
        if pid == python_pid:
            continue
        if ps_pid and pid == ps_pid:
            continue
        return f"{command} {cpu:.1f}%"
    
    return "no cpu"


def get_temperature() -> str:
    thermal_zones = []
    for zone_dir in os.listdir("/sys/class/thermal/"):
        if zone_dir.startswith("thermal_zone"):
            temp_path = os.path.join("/sys/class/thermal/", zone_dir, "temp")
            type_path = os.path.join("/sys/class/thermal/", zone_dir, "type")
            try:
                with open(temp_path, "r") as f:
                    temp_milli = int(f.read().strip())
                with open(type_path, "r") as f:
                    zone_type = f.read().strip()
                thermal_zones.append((temp_milli, zone_type))
            except Exception:
                continue

    if not thermal_zones:
        return "no_temp"

    max_temp_milli = max(thermal_zones, key=lambda x: x[0])[0]
    max_temp_celsius = max_temp_milli / 1000.0
    return f"{max_temp_celsius:.1f}C"


BATTERY_PATH = "/org/freedesktop/UPower/devices/battery_qcom_battmgr_bat"


def main() -> None:

    results: dict[str, str | None] = {}
    threads = {
        "run_date": threading.Thread(target=lambda: results.update({"run_date": run_date()})),
        "run_battery": threading.Thread(target=lambda: results.update({"run_battery": run_battery(battery_path=BATTERY_PATH)})),
        "run_volume": threading.Thread(target=lambda: results.update({"run_volume": run_volume()})),
        "run_brightness": threading.Thread(target=lambda: results.update({"run_brightness": run_brightness()})),
        "run_network": threading.Thread(target=lambda: results.update({"run_network": run_network()})),
        "run_cpu": threading.Thread(target=lambda: results.update({"run_cpu": run_cpu()})),
    }
    
    for thread in threads.values():
        thread.start()
    
    for thread in threads.values():
        thread.join()

    date_stdout = results.get("run_date")
    battery_stdout = results.get("run_battery")
    volume_stdout = results.get("run_volume")
    brightness_stdout = results.get("run_brightness")
    network_stdout = results.get("run_network")
    ps_cpu = results.get("run_cpu", (None, None))

    # date_stdout = run_date()
    # battery_stdout = run_battery(battery_path=BATTERY_PATH)
    # volume_stdout = run_volume()
    # brightness_stdout = run_brightness()
    # network_stdout = run_network()
    # ps_cpu = run_cpu()

    date = get_date(stdout=date_stdout)
    battery = get_battery(stdout=battery_stdout)
    volume = get_volume(stdout=volume_stdout)
    brightness = get_brightness(stdout=brightness_stdout)
    network = get_network(stdout=network_stdout)
    top = get_cpu(stdout=ps_cpu[0], ps_pid=ps_cpu[1])
    temp = get_temperature()

    status = f"{top} | {temp} | {network} | {brightness} | {volume} | {battery} | {date}"
    print(status, end="")


if __name__ == "__main__":
    main()
