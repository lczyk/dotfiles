from unittest.mock import patch

import opacity


def test_set_opacity_invokes_swaymsg():
    with patch("opacity.subprocess.run") as run:
        opacity.set_opacity(42, 0.9)
        args, kwargs = run.call_args
        cmd = args[0]
        assert cmd[0] == "swaymsg"
        assert "[con_id=42]" in cmd
        assert "opacity" in cmd
        assert "0.9" in cmd
        assert kwargs.get("check") is False
