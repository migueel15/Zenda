package main

import (
	"fmt"
	"strconv"

	"github.com/migueel15/Zenda/core/internal/hyprland/hyprctl"
	"github.com/spf13/cobra"
)

// The pinstack column: Hyprland (generated pinstack module) places the windows
// and Quickshell reserves the column and draws its resize handle.
func pinstackCmd() *cobra.Command {
	cmd := &cobra.Command{
		Use:   "pinstack",
		Short: "Bridge the pinned window column between Hyprland and the shell",
	}
	cmd.AddCommand(pinstackWidthCmd(), pinstackStateCmd())
	return cmd
}

func pinstackWidthCmd() *cobra.Command {
	var live bool
	var offset int
	cmd := &cobra.Command{
		Use:   "width <pixels>",
		Short: "Set the column width in Hyprland",
		Args:  cobra.ExactArgs(1),
		RunE: func(cmd *cobra.Command, args []string) error {
			width, err := strconv.Atoi(args[0])
			if err != nil || width <= 0 {
				return fmt.Errorf("ancho inválido: %q", args[0])
			}
			cmd.SilenceUsage = true
			return hyprctl.New(nil).SetPinstackWidth(cmd.Context(), width, offset, live)
		},
	}
	cmd.Flags().IntVar(&offset, "offset", 0, "pixels other exclusive zones take before the column")
	cmd.Flags().BoolVar(&live, "live", false, "the edge is still being dragged")
	return cmd
}

func pinstackStateCmd() *cobra.Command {
	return &cobra.Command{
		Use:    "state <active> <monitor> [min-width] [width]",
		Short:  "Tell the shell that the column was shown or hidden",
		Hidden: true,
		Args:   cobra.RangeArgs(2, 4),
		RunE: func(cmd *cobra.Command, args []string) error {
			active, err := strconv.ParseBool(args[0])
			if err != nil {
				return fmt.Errorf("estado inválido: %q", args[0])
			}
			numbers := []int{0, 0}
			for i, arg := range args[2:] {
				if numbers[i], err = strconv.Atoi(arg); err != nil || numbers[i] < 0 {
					return fmt.Errorf("ancho inválido: %q", arg)
				}
			}
			_, err = callShellIPC(cmd, "pinstack", "setState", strconv.FormatBool(active), args[1], strconv.Itoa(numbers[0]), strconv.Itoa(numbers[1]))
			return err
		},
	}
}
