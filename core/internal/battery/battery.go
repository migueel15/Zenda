package battery

import (
	"bufio"
	"encoding/binary"
	"fmt"
	"os"
	"path/filepath"
	"strings"
	"time"

	"golang.org/x/sys/unix"
)

// Device represents a peripheral battery reading.
type Device struct {
	ID         string `json:"id"`
	Name       string `json:"name"`
	Kind       string `json:"kind"`
	Percentage int    `json:"percentage"`
	Charging   bool   `json:"charging"`
	Source     string `json:"source"`
}

// hidppDeviceSpec describes a known HID++ 2.0 device that is not exposed by UPower.
type hidppDeviceSpec struct {
	vendorID  string
	productID string
	name      string
	kind      string
}

var knownHIDPPDevices = []hidppDeviceSpec{
	{
		vendorID:  "046D",
		productID: "0ABA",
		name:      "Logitech PRO X Wireless",
		kind:      "headset",
	},
}

// proXDischargeCurve maps millivolts to battery percentage for the
// Logitech PRO X Wireless Gaming Headset (046d:0aba).
var proXDischargeCurve = []struct {
	mv  int
	pct int
}{
	{4186, 100},
	{4067, 90},
	{3989, 80},
	{3922, 70},
	{3859, 60},
	{3811, 50},
	{3778, 40},
	{3751, 30},
	{3717, 20},
	{3671, 10},
	{3500, 0},
}

// VoltageToPercent converts a battery voltage in millivolts to a 0-100 percentage
// using piecewise linear interpolation over the PRO X Wireless discharge curve.
func VoltageToPercent(mv int) int {
	if mv >= proXDischargeCurve[0].mv {
		return 100
	}
	last := proXDischargeCurve[len(proXDischargeCurve)-1]
	if mv <= last.mv {
		return 0
	}
	for i := 0; i < len(proXDischargeCurve)-1; i++ {
		hi := proXDischargeCurve[i]
		lo := proXDischargeCurve[i+1]
		if mv >= lo.mv && mv <= hi.mv {
			span := hi.mv - lo.mv
			if span <= 0 {
				return lo.pct
			}
			pct := lo.pct + ((mv-lo.mv)*(hi.pct-lo.pct)+span/2)/span
			if pct < 0 {
				return 0
			}
			if pct > 100 {
				return 100
			}
			return pct
		}
	}
	return 0
}

// ParseHIDPPBatteryResponse parses a 20-byte HID++ 2.0 feature 0x1f20 response.
// Bytes 4-5 are big-endian millivolts; byte 6 is state (1=discharging, 3=charging, 0=off/disconnected).
func ParseHIDPPBatteryResponse(data []byte) (mv int, state byte, ok bool) {
	if len(data) < 7 {
		return 0, 0, false
	}
	if data[0] != 0x11 || data[1] != 0xff || data[2] != 0x06 || data[3] != 0x0d {
		return 0, 0, false
	}
	mv = int(binary.BigEndian.Uint16(data[4:6]))
	state = data[6]
	return mv, state, true
}

// ListHIDPP scans /sys/class/hidraw for known HID++ 2.0 devices and queries their battery.
func ListHIDPP() []Device {
	entries, err := os.ReadDir("/sys/class/hidraw")
	if err != nil {
		return []Device{}
	}

	devices := make([]Device, 0)
	seen := make(map[string]bool)

	for _, entry := range entries {
		name := entry.Name()
		ueventPath := filepath.Join("/sys/class/hidraw", name, "device", "uevent")
		vendor, product, hidName := readHIDUevent(ueventPath)
		if vendor == "" || product == "" {
			continue
		}

		for _, spec := range knownHIDPPDevices {
			if !strings.EqualFold(vendor, spec.vendorID) || !strings.EqualFold(product, spec.productID) {
				continue
			}
			key := strings.ToLower(spec.vendorID + ":" + spec.productID)
			if seen[key] {
				continue
			}
			devPath := filepath.Join("/dev", name)
			mv, state, err := queryProXBattery(devPath, 500*time.Millisecond)
			if err != nil || state == 0 || mv == 0 {
				continue
			}
			seen[key] = true
			displayName := spec.name
			if displayName == "" && hidName != "" {
				displayName = hidName
			}
			devices = append(devices, Device{
				ID:         "hidpp:" + key,
				Name:       displayName,
				Kind:       spec.kind,
				Percentage: VoltageToPercent(mv),
				Charging:   state == 3,
				Source:     "hidpp",
			})
		}
	}

	return devices
}

func readHIDUevent(path string) (vendor, product, hidName string) {
	f, err := os.Open(path)
	if err != nil {
		return "", "", ""
	}
	defer f.Close()

	scanner := bufio.NewScanner(f)
	for scanner.Scan() {
		line := scanner.Text()
		if strings.HasPrefix(line, "HID_ID=") {
			parts := strings.Split(strings.TrimPrefix(line, "HID_ID="), ":")
			if len(parts) == 3 {
				vendor = strings.TrimLeft(parts[1], "0")
				product = strings.TrimLeft(parts[2], "0")
				// Pad back to 4 hex chars for canonical matching.
				vendor = fmt.Sprintf("%04s", vendor)
				product = fmt.Sprintf("%04s", product)
				vendor = strings.ReplaceAll(vendor, " ", "0")
				product = strings.ReplaceAll(product, " ", "0")
			}
		} else if strings.HasPrefix(line, "HID_NAME=") {
			hidName = strings.TrimSpace(strings.TrimPrefix(line, "HID_NAME="))
		}
	}
	return vendor, product, hidName
}

func queryProXBattery(devPath string, timeout time.Duration) (int, byte, error) {
	fd, err := unix.Open(devPath, unix.O_RDWR|unix.O_NONBLOCK|unix.O_CLOEXEC, 0)
	if err != nil {
		return 0, 0, err
	}
	defer unix.Close(fd)

	// Drain any stale queued reports before sending our query.
	drainBuf := make([]byte, 64)
	for i := 0; i < 8; i++ {
		if _, err := unix.Read(fd, drainBuf); err != nil {
			break
		}
	}

	req := make([]byte, 20)
	req[0] = 0x11
	req[1] = 0xff
	req[2] = 0x06
	req[3] = 0x0d
	if _, err := unix.Write(fd, req); err != nil {
		return 0, 0, err
	}

	deadline := time.Now().Add(timeout)
	buf := make([]byte, 64)
	for {
		remaining := time.Until(deadline)
		if remaining <= 0 {
			return 0, 0, fmt.Errorf("timeout reading %s", devPath)
		}
		fds := []unix.PollFd{{Fd: int32(fd), Events: unix.POLLIN}}
		n, err := unix.Poll(fds, int(remaining.Milliseconds()))
		if err != nil {
			if err == unix.EINTR {
				continue
			}
			return 0, 0, err
		}
		if n == 0 {
			return 0, 0, fmt.Errorf("timeout reading %s", devPath)
		}
		readN, err := unix.Read(fd, buf)
		if err != nil {
			if err == unix.EAGAIN || err == unix.EINTR {
				continue
			}
			return 0, 0, err
		}
		if mv, state, ok := ParseHIDPPBatteryResponse(buf[:readN]); ok {
			return mv, state, nil
		}
	}
}
