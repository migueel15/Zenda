package battery

import "testing"

func TestVoltageToPercent(t *testing.T) {
	cases := []struct {
		mv   int
		want int
	}{
		{4250, 100},
		{4186, 100},
		{4067, 90},
		{4061, 89},
		{3989, 80},
		{3811, 50},
		{3717, 20},
		{3500, 0},
		{3200, 0},
	}

	for _, tc := range cases {
		if got := VoltageToPercent(tc.mv); got != tc.want {
			t.Errorf("VoltageToPercent(%d) = %d, want %d", tc.mv, got, tc.want)
		}
	}
}

func TestParseHIDPPBatteryResponse(t *testing.T) {
	valid := []byte{0x11, 0xff, 0x06, 0x0d, 0x0f, 0xdd, 0x01, 0x00, 0x00, 0x00}
	mv, state, ok := ParseHIDPPBatteryResponse(valid)
	if !ok {
		t.Fatalf("expected valid response")
	}
	if mv != 4061 || state != 1 {
		t.Fatalf("got mv=%d state=%d, want mv=4061 state=1", mv, state)
	}

	if _, _, ok := ParseHIDPPBatteryResponse([]byte{0x10, 0xff, 0x06, 0x0d, 0x0f, 0xdd, 0x01}); ok {
		t.Fatalf("expected non-matching header to be rejected")
	}
	if _, _, ok := ParseHIDPPBatteryResponse([]byte{0x11, 0xff}); ok {
		t.Fatalf("expected short packet to be rejected")
	}
}
