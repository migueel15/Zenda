package integration

import (
	_ "embed"
	"strconv"
)

// pinstackLua places the pinned windows of the side column. Quickshell reserves
// the column and owns its width; see quickshell/modules/pinstack.
//
//go:embed pinstack.lua
var pinstackLua string

func renderPinstackModule(in moduleInput) (string, error) {
	return "local zenda_cmd = " + strconv.Quote(in.Command) + "\n" + pinstackLua, nil
}
