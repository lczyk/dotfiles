from status import get_network, primary_device, split_terse



def device(dev_type, name, iface, connectivity="4 (full)", state="100 (connected)"):
    return (
        f"GENERAL.TYPE:{dev_type}\nGENERAL.STATE:{state}\nGENERAL.IP4-CONNECTIVITY:{connectivity}\n"
        f"GENERAL.CONNECTION:{name}\nGENERAL.IP-IFACE:{iface}\n\n"
    )


WIFI_ONLY = device("wifi", "office", "wlan0")
BT_ONLY = device("bt", "phone", "bnep0")
ETH_ONLY = device("ethernet", "Wired connection 1", "enx1234")
NOISE = (
    device("loopback", "lo", "lo", "0 (unknown)", "100 (connected (externally))")
    + device("bridge", "docker0", "docker0", "1 (none)", "100 (connected (externally))")
    + device("wifi-p2p", "", "", "1 (none)", "30 (disconnected)")
    + device("bt", "", "", "0 (unknown)", "30 (disconnected)")
)
DEVICES = WIFI_ONLY + BT_ONLY + NOISE
CONNECTIONS = "802-11-wireless:office\nbridge:docker0\nloopback:lo\n"
WIFI_LIST = " :42:2412 MHz\n*:75:5320 MHz\n :60:5180 MHz\n"
ROUTES_WIFI_FIRST = (
    "default via 10.0.0.1 dev wlan0 proto dhcp src 10.0.0.2 metric 600\n"
    "default via 10.1.0.1 dev bnep0 proto dhcp src 10.1.0.2 metric 750\n"
)
ROUTES_BT_FIRST = (
    "default via 10.0.0.1 dev wlan0 proto dhcp src 10.0.0.2 metric 800\n"
    "default via 10.1.0.1 dev bnep0 proto dhcp src 10.1.0.2 metric 750\n"
)


def net(devices=DEVICES, connections=CONNECTIONS, wifi_list=WIFI_LIST, routes="", probe=""):
    return get_network((devices, connections, wifi_list, routes, probe))


def test_split_terse_keeps_escaped_colons():
    assert split_terse("74\\:29\\:17:bt:connected") == ["74:29:17", "bt", "connected"]


def test_primary_device_is_lowest_metric():
    assert primary_device(ROUTES_WIFI_FIRST) == "wlan0"
    assert primary_device(ROUTES_BT_FIRST) == "bnep0"
    assert primary_device("default via 10.0.0.1 dev eth0\n") == "eth0"
    assert primary_device("") == ""


def test_wifi_only():
    assert net(devices=WIFI_ONLY) == "office 5g 75%"


def test_wifi_band_from_frequency():
    assert net(devices=WIFI_ONLY, wifi_list="*:80:2437 MHz\n") == "office 2g 80%"
    assert net(devices=WIFI_ONLY, wifi_list="*:80:5955 MHz\n") == "office 6g 80%"
    assert net(devices=WIFI_ONLY, wifi_list="") == "office"


def test_bt_standby_and_active_follow_the_routes():
    assert net(routes=ROUTES_WIFI_FIRST) == "office 5g 75% +bt"
    assert net(routes=ROUTES_BT_FIRST) == "office 5g 75% > bt"


def test_without_routes_nm_connectivity_decides():
    limited = device("wifi", "office", "wlan0", "3 (limited)") + BT_ONLY
    assert net() == "office 5g 75% +bt"
    assert net(devices=limited) == "office 5g 75% !limited > bt"


def test_usb_tether_counts_as_eth():
    routes = "default via 172.20.10.1 dev enx1234 proto dhcp metric 100\n" + ROUTES_WIFI_FIRST
    assert net(devices=DEVICES + ETH_ONLY, routes=routes) == "office 5g 75% > eth +bt"
    assert net(devices=ETH_ONLY) == "eth Wired connection 1"


def test_bt_only_and_nothing():
    assert net(devices=BT_ONLY) == "bt phone"
    assert net(devices=device("bt", "phone", "bnep0", "3 (limited)")) == "bt phone !limited"
    assert net(devices=NOISE) == "no net"
    assert net(devices="") == "no net"


def test_vpn_suffix():
    connections = CONNECTIONS + "wireguard:uk\nvpn:us\n"
    assert net(devices=WIFI_ONLY, connections=connections) == "office 5g 75% (uk, us)"


def test_probe_from_netwatch():
    assert net(devices=WIFI_ONLY, probe="wlan0 0 65 ok\n") == "office 5g 75% 65ms"
    assert net(devices=WIFI_ONLY, probe="wlan0 33 1800 bad\n") == "office 5g 75% !1800ms"
    assert net(devices=WIFI_ONLY, probe="wlan0 100 0 bad\n") == "office 5g 75% !100%"
    assert net(devices=WIFI_ONLY, probe="garbage\n") == "office 5g 75%"
