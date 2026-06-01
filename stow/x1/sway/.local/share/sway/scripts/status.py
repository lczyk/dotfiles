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


def run_wifi_and_vpn() -> str:
    nmcli_output = sub.getoutput("nmcli con show --active")
    return nmcli_output


def get_wifi_and_vpn(stdout: str | None = None) -> str:
    nmcli_output = stdout if stdout else run_wifi_and_vpn()
    wifi = ""
    vpn = ""
    for line in nmcli_output.splitlines():
        if "wifi" in line:
            wifi = line.split()[0]
        elif "vpn" in line:
            vpn = line.split()[0]

    if not wifi:
        return "no wifi"

    wifi_and_vpn = wifi
    if vpn:
        wifi_and_vpn += f" ({vpn})"

    return wifi_and_vpn


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
        "run_wifi_and_vpn": threading.Thread(target=lambda: results.update({"run_wifi_and_vpn": run_wifi_and_vpn()})),
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
    wifi_and_vpn_stdout = results.get("run_wifi_and_vpn")
    ps_cpu = results.get("run_cpu", (None, None))

    # date_stdout = run_date()
    # battery_stdout = run_battery(battery_path=BATTERY_PATH)
    # volume_stdout = run_volume()
    # brightness_stdout = run_brightness()
    # wifi_and_vpn_stdout = run_wifi_and_vpn()
    # ps_cpu = run_cpu()

    date = get_date(stdout=date_stdout)
    battery = get_battery(stdout=battery_stdout)
    volume = get_volume(stdout=volume_stdout)
    brightness = get_brightness(stdout=brightness_stdout)
    wifi_and_vpn = get_wifi_and_vpn(stdout=wifi_and_vpn_stdout)
    top = get_cpu(stdout=ps_cpu[0], ps_pid=ps_cpu[1])
    temp = get_temperature()

    status = f"{top} | {temp} | {wifi_and_vpn} | {brightness} | {volume} | {battery} | {date}"
    print(status, end="")


if __name__ == "__main__":
    main()
